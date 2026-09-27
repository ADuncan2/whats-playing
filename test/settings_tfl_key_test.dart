// Settings -> TfL app key: the explainer, pasting a key, TfL rejecting one, and clearing it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:whats_playing/app.dart';
import 'package:whats_playing/data/listings.dart';
import 'package:whats_playing/data/settings_store.dart';
import 'package:whats_playing/data/tfl_key_check.dart';
import 'package:whats_playing/features/settings/settings_screen.dart';
import 'package:whats_playing/state/app_state.dart';

class _FakeListings extends ListingsNotifier {
  @override
  Future<Listings> build() async => Listings.fromJson({
    'schema': 1,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'from': '2026-09-24',
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
      [0, DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000, null, 0],
    ],
  });
}

void main() {
  setUpAll(tz_data.initializeTimeZones);

  Future<SettingsStore> openSettings(WidgetTester tester, KeyCheck answer, List<String> asked) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          listingsProvider.overrideWith(_FakeListings.new),
          tflKeyCheckerProvider.overrideWithValue((key) async {
            asked.add(key);
            return answer;
          }),
        ],
        child: const WhatsPlayingApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
    await tester.pumpAndSettle();
    // The tile is below the fold of the (lazy) settings list.
    await tester.scrollUntilVisible(
      find.text('TfL app key'),
      200,
      scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('paste a key: TfL confirms it, it is saved, and the tile says so', (tester) async {
    final asked = <String>[];
    final store = await openSettings(tester, KeyCheck.accepted, asked);
    expect(find.textContaining('No key'), findsOneWidget);

    await tester.tap(find.text('TfL app key'));
    await tester.pumpAndSettle();
    expect(find.textContaining('500 requests a minute'), findsOneWidget);
    expect(find.text('Open the TfL API portal'), findsOneWidget);
    expect(find.text('Clear'), findsNothing); // nothing to clear yet

    await tester.enterText(find.byType(TextField), ' abc 123 ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(asked, ['abc123']); // whitespace stripped before checking
    expect(store.load().tflKey, 'abc123');
    expect(find.textContaining('Your key'), findsOneWidget);
    expect(find.text('TfL key saved'), findsOneWidget);

    // Clear it again.
    await tester.tap(find.text('TfL app key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(store.load().tflKey, '');
    expect(find.textContaining('No key'), findsOneWidget);
  });

  testWidgets('a key TfL rejects is not saved', (tester) async {
    final store = await openSettings(tester, KeyCheck.rejected, []);
    await tester.tap(find.text('TfL app key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('TfL rejected this key'), findsOneWidget);
    expect(store.load().tflKey, '');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No key'), findsOneWidget);
  });

  testWidgets('offline: the key is saved with a warning', (tester) async {
    final store = await openSettings(tester, KeyCheck.unknown, []);
    await tester.tap(find.text('TfL app key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'maybe');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.load().tflKey, 'maybe');
    expect(find.textContaining("couldn't be reached"), findsOneWidget);
  });
}
