// A TfL app key pasted into Settings: it is remembered, it wins over the built-in one, and both the
// request rate and the number of cinemas a search checks follow it.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:whats_playing/core/constants.dart';
import 'package:whats_playing/core/london_time.dart';
import 'package:whats_playing/data/settings_store.dart';
import 'package:whats_playing/data/tfl_key_check.dart';
import 'package:whats_playing/engine/journey_router.dart';
import 'package:whats_playing/state/app_state.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('the key is saved and loaded, and absent = empty', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore(await SharedPreferences.getInstance());
    expect(store.load().tflKey, '');
    await store.save(store.load().copyWith(tflKey: 'abc123'));
    expect(store.load().tflKey, 'abc123');
    await store.save(store.load().copyWith(tflKey: ''));
    expect(store.load().tflKey, '');
  });

  test('a pasted key is the one in use and the router follows it', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [settingsStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);

    // Nothing pasted: the built-in key (empty in tests) is in use.
    expect(container.read(tflKeyProvider), tflAppKey);
    expect(container.read(tflKeySourceProvider), tflAppKey.isEmpty ? TflKeySource.none : TflKeySource.builtIn);
    final before = container.read(tflRouterProvider) as TflRouter;
    expect(before.key, tflAppKey);

    container.read(settingsProvider.notifier).update((s) => s.copyWith(tflKey: ' user-key '));
    expect(container.read(tflKeyProvider), 'user-key');
    expect(container.read(tflKeySourceProvider), TflKeySource.user);
    final after = container.read(tflRouterProvider) as TflRouter;
    expect(after, isNot(same(before)));
    expect(after.key, 'user-key');
    expect(after.gap, TflRouter.gapFor('user-key'));

    container.read(settingsProvider.notifier).update((s) => s.copyWith(tflKey: ''));
    expect(container.read(tflKeyProvider), tflAppKey);
  });

  test('rate and search size: anonymous is spaced out and capped, keyed is neither', () {
    expect(TflRouter.gapFor(''), greaterThanOrEqualTo(const Duration(milliseconds: 1200))); // <50/min
    expect(TflRouter.gapFor('key'), lessThanOrEqualTo(const Duration(milliseconds: 150))); // <500/min
    expect(TflRouter.gapFor('key'), lessThan(TflRouter.gapFor('')));
    expect(TflRouter.venueCapFor(''), anonymousVenueCap);
    expect(TflRouter.venueCapFor('  '), anonymousVenueCap);
    expect(TflRouter.venueCapFor('key'), isNull);
    expect(TflRouter(key: 'key').gap, TflRouter.gapFor('key'));
    expect(TflRouter().gap, TflRouter.gapFor(''));
  });

  group('checking a key with TfL', () {
    MockClient answering(int status) => MockClient((r) async {
      expect(r.url.queryParameters['app_key'], 'the-key');
      return http.Response('{}', status);
    });

    test('200 = accepted', () async {
      expect(await checkTflKey('the-key', client: answering(200)), KeyCheck.accepted);
    });
    test('401 or 403 = rejected', () async {
      expect(await checkTflKey('the-key', client: answering(401)), KeyCheck.rejected);
      expect(await checkTflKey('the-key', client: answering(403)), KeyCheck.rejected);
    });
    test('offline or an odd status = unknown', () async {
      final offline = MockClient((_) async => throw const SocketException('offline'));
      expect(await checkTflKey('the-key', client: offline), KeyCheck.unknown);
      expect(await checkTflKey('the-key', client: answering(500)), KeyCheck.unknown);
    });
  });

  test('a rejected key during a search is reported as such', () async {
    final tfl = TflRouter(key: 'bad', client: MockClient((_) async => http.Response('{}', 401)));
    final leg = await tfl.earliestArrival(
      (lat: 51.5, lon: -0.1),
      (lat: 51.51, lon: -0.11),
      londonNow(),
    );
    expect(leg.found, isFalse);
    expect(leg.error, contains('rejected'));
    expect(tfl.errors.single, contains('Settings'));
  });
}
