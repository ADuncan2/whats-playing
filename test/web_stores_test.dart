// The web build's storage: ListingsRepository with no cache folder (kept in memory) and the
// Letterboxd data in shared_preferences. No dart:io here, so this file also runs under
// `flutter test --platform chrome`, which is the point.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whats_playing/data/letterboxd/letterboxd_data.dart';
import 'package:whats_playing/data/letterboxd/letterboxd_store.dart';
import 'package:whats_playing/data/listings_repository.dart';

String listingsJson({int schema = 1}) => jsonEncode({
  'schema': schema,
  'generatedAt': DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String(), // not expired
  'from': '2026-09-21',
  'days': 7,
  'venues': {
    'v': {'name': 'V', 'lat': 51.5, 'lon': -0.1, 'chain': null},
  },
  'films': {
    'f': {'title': 'F', 'runtime': 90},
  },
  'showings': [
    {'film': 'f', 'venue': 'v', 'title': null, 'runtime': null, 'url': null},
  ],
  'performances': [
    [0, 1789981200, 'https://book', 0],
  ],
});

void main() {
  group('ListingsRepository without a cache folder', () {
    var calls = 0;
    setUp(() => calls = 0);

    MockClient serving(String body, {int status = 200}) => MockClient((_) async {
      calls++;
      return http.Response(body, status);
    });
    final failing = MockClient((_) async {
      calls++;
      throw http.ClientException('offline');
    });

    test('starts empty and stale', () async {
      final repo = ListingsRepository(cacheDir: null, client: serving(listingsJson()));
      expect(await repo.cacheAge(), isNull);
      expect(await repo.isStale, isTrue);
      expect(await repo.readCache(), isNull);
    });

    test('downloads once, then serves the in-memory copy', () async {
      final repo = ListingsRepository(cacheDir: null, client: serving(listingsJson()));
      final l = await repo.load();
      expect(l.venues.keys, ['v']);
      expect(calls, 1);
      expect((await repo.cacheAge())!, lessThan(const Duration(minutes: 1)));
      expect(await repo.isStale, isFalse);

      final again = await repo.load();
      expect(again.venues.keys, ['v']);
      expect(calls, 1, reason: 'a fresh in-memory copy should not hit the network');
      expect((await repo.readCache())!.venues.keys, ['v']);
    });

    test('refresh re-downloads; a failed refresh keeps the memory copy', () async {
      final repo = ListingsRepository(cacheDir: null, client: serving(listingsJson()));
      await repo.load();
      await repo.load(refresh: true);
      expect(calls, 2);

      final offline = ListingsRepository(cacheDir: null, client: failing);
      await expectLater(offline.load(), throwsA(isA<http.ClientException>()));
      expect(await offline.readCache(), isNull);
    });

    test('a bad file is rejected and nothing is kept', () async {
      final repo = ListingsRepository(cacheDir: null, client: serving(listingsJson(schema: 99)));
      await expectLater(repo.load(), throwsA(isA<FormatException>()));
      expect(await repo.readCache(), isNull);
      expect(await repo.cacheAge(), isNull);
    });
  });

  group('PrefsLetterboxdStore', () {
    late SharedPreferences prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    final data = LetterboxdData(
      exportedAt: DateTime.utc(2026, 9, 1),
      importedAt: DateTime.utc(2026, 9, 2),
      username: 'dave',
      watchlist: const [LetterboxdEntry(name: 'Alpha', year: 2026, uri: 'https://boxd.it/a')],
      watched: const [LetterboxdEntry(name: 'Beta', year: 2020)],
      rssWatchedTmdb: {2: DateTime.utc(2026, 9, 3)},
      rssFetchedAt: DateTime.utc(2026, 9, 4),
    );

    test('empty until written', () async {
      expect(await PrefsLetterboxdStore(prefs).read(), isNull);
    });

    test('round-trips through shared_preferences', () async {
      await PrefsLetterboxdStore(prefs).write(data);
      final back = await PrefsLetterboxdStore(await SharedPreferences.getInstance()).read();
      expect(back, isNotNull);
      expect(back!.username, 'dave');
      expect(back.exportedAt, data.exportedAt);
      expect(back.watchlist.single.name, 'Alpha');
      expect(back.watchlist.single.year, 2026);
      expect(back.watched.single.name, 'Beta');
      expect(back.rssWatchedTmdb, {2: DateTime.utc(2026, 9, 3)});
      expect(back.rssFetchedAt, DateTime.utc(2026, 9, 4));
    });

    test('delete unlinks', () async {
      final store = PrefsLetterboxdStore(prefs);
      await store.write(data);
      await store.delete();
      expect(await store.read(), isNull);
    });

    test('garbage in storage reads as unlinked', () async {
      await prefs.setString('letterboxd.json', '{not json');
      expect(await PrefsLetterboxdStore(prefs).read(), isNull);
    });
  });
}
