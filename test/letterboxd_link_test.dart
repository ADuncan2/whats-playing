// Settings -> Letterboxd: import an export, see the watchlist strip on Home, search from it with
// "Hide films I've seen", then unlink. The file picker, RSS fetch and store are faked.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:whats_playing/app.dart';
import 'package:whats_playing/core/london_time.dart';
import 'package:whats_playing/data/letterboxd/letterboxd_data.dart';
import 'package:whats_playing/data/letterboxd/letterboxd_store.dart';
import 'package:whats_playing/data/listings.dart';
import 'package:whats_playing/data/settings_store.dart';
import 'package:whats_playing/features/search_form/search_form.dart';
import 'package:whats_playing/features/settings/letterboxd_screen.dart';
import 'package:whats_playing/state/app_state.dart';

/// Alpha (2026) and Beta (2020) at one cinema, 1 and 2 hours from now.
class _FakeListings extends ListingsNotifier {
  @override
  Future<Listings> build() async {
    final now = londonNow();
    int inHours(int h) => now.add(Duration(hours: h)).millisecondsSinceEpoch ~/ 1000;
    final today = dayOf(now);
    return Listings.fromJson({
      'schema': 1,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'from': '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
      'days': 7,
      'venues': {
        'v': {'name': 'Curzon Soho', 'lat': 51.5136, 'lon': -0.1318, 'chain': 'Curzon'},
      },
      'films': {
        'f1': {'title': 'Alpha', 'runtime': 95, 'year': '2026', 'tmdb': 1},
        'f2': {'title': 'Beta', 'runtime': 100, 'year': '2020', 'tmdb': 2},
      },
      'showings': [
        {'film': 'f1', 'venue': 'v'},
        {'film': 'f2', 'venue': 'v'},
      ],
      'performances': [
        [0, inHours(1), null, 0],
        [1, inHours(2), null, 0],
      ],
    });
  }
}

Uint8List zip(Map<String, String> files) {
  final a = Archive();
  for (final e in files.entries) {
    a.addFile(ArchiveFile.string(e.key, e.value));
  }
  return ZipEncoder().encodeBytes(a);
}

final export = (
  name: 'letterboxd-exampleuser-2026-09-25-09-48-utc.zip',
  bytes: zip({
    'watchlist.csv': 'Date,Name,Year,Letterboxd URI\n2026-01-01,Alpha,2026,https://boxd.it/a\n',
    'watched.csv': 'Date,Name,Year,Letterboxd URI\n2026-01-01,Beta,2020,https://boxd.it/b\n',
    'profile.csv': 'Date Joined,Username\n2018-08-29,ExampleUser\n',
  }),
);

final notAnExport = (name: 'holiday-photos.zip', bytes: zip({'readme.txt': 'hi'}));

void main() {
  setUpAll(tz_data.initializeTimeZones);

  late MemoryLetterboxdStore store;
  late SettingsStore settings;
  late List<String> rssAsked;
  late PickedFile? Function() picker;

  Future<void> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    settings = SettingsStore(await SharedPreferences.getInstance());
    store = MemoryLetterboxdStore();
    rssAsked = [];
    picker = () => export;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(settings),
          listingsProvider.overrideWith(_FakeListings.new),
          letterboxdStoreProvider.overrideWithValue(store),
          letterboxdRssFetcherProvider.overrideWithValue((user) async {
            rssAsked.add(user);
            return {2: DateTime.utc(2026, 9, 24)};
          }),
          letterboxdFilePickerProvider.overrideWithValue(() async => picker()),
        ],
        child: const WhatsPlayingApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The Letterboxd screen is a lazy list: bring a widget into view (from the top, so it works
  /// whichever way the list was last scrolled).
  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    final list = find.descendant(of: find.byType(LetterboxdScreen), matching: find.byType(Scrollable)).first;
    await tester.drag(list, const Offset(0, 4000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(f, 150, scrollable: list);
    await tester.pumpAndSettle();
  }

  Future<void> goToLetterboxd(WidgetTester tester) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate((w) => w is ListTile && w.leading is Icon && (w.leading as Icon).icon == Icons.link),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LetterboxdScreen), findsOneWidget);
  }

  testWidgets('link, watchlist on Home, search from it with hide-seen, unlink', (tester) async {
    await openApp(tester);
    // Not linked yet: the watchlist is on Home, greyed out, with a line saying how to turn it on.
    expect(find.text('On your watchlist this week'), findsOneWidget);
    expect(find.textContaining('Link Letterboxd in Settings to see'), findsOneWidget);

    // The search form has the hide-seen toggle, greyed out.
    await tester.tap(find.text('Solo'));
    await tester.pumpAndSettle();
    final unlinkedForm = find.descendant(of: find.byType(SearchForm), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text("Hide films I've seen"), 150, scrollable: unlinkedForm);
    await tester.pumpAndSettle();
    expect(find.text('Link Letterboxd in Settings to use this'), findsOneWidget);
    final toggle = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, "Hide films I've seen"));
    expect(toggle.onChanged, isNull);
    expect(toggle.value, isFalse);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Home')));
    await tester.pumpAndSettle();

    // Tapping the line opens the Letterboxd screen.
    await tester.tap(find.textContaining('Link Letterboxd in Settings to see'));
    await tester.pumpAndSettle();
    expect(find.byType(LetterboxdScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await goToLetterboxd(tester);
    expect(find.text('Link your Letterboxd account'), findsOneWidget);
    expect(find.text('Open in browser'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('https://letterboxd.com/user/exportdata/'), findsOneWidget);
    await scrollTo(tester, find.byType(TextField));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse); // username needs an import first

    await scrollTo(tester, find.text('Choose file'));
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(find.text('Imported 1 watchlist film and 1 watched film (exported 25 Sep 2026)'), findsWidgets);
    expect(store.data?.watchlist.single.name, 'Alpha');
    await scrollTo(tester, find.text('Linked as ExampleUser'));
    expect(find.text('Re-import'), findsOneWidget);
    expect(find.text('Unlink'), findsOneWidget);
    await scrollTo(tester, find.byType(TextField));
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, 'ExampleUser');
    // profile.csv gave a username, so the diary feed was checked and merged in.
    expect(rssAsked, ['ExampleUser']);
    expect(store.data?.rssWatchedTmdb, {2: DateTime.utc(2026, 9, 24)});

    // Back to Settings: the tile now says what is linked.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('1 on watchlist · 1 watched'), findsOneWidget);

    // Home: the watchlist strip, with Alpha playing today.
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Home')));
    await tester.pumpAndSettle();
    expect(find.text('On your watchlist this week'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.textContaining('Today'), findsOneWidget);
    expect(find.textContaining('1 cinema · 1 screening'), findsOneWidget);
    expect(find.textContaining('Refresh your Letterboxd'), findsNothing); // export is fresh

    // Tapping it opens the search form preset to that film, with the hide-seen toggle available.
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.text('Find films'), findsOneWidget);
    final form = find.descendant(of: find.byType(SearchForm), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Films'), 150, scrollable: form);
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget); // the Films filter row's value
    await tester.scrollUntilVisible(find.text("Hide films I've seen"), 150, scrollable: form);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).last).value, isTrue);
    expect(settings.load().hideSeen, isFalse); // this search only: the default is in Settings

    // Unlink deletes everything.
    await goToLetterboxd(tester);
    await scrollTo(tester, find.text('Unlink'));
    await tester.tap(find.text('Unlink'));
    await tester.pumpAndSettle();
    expect(find.text('Unlink Letterboxd?'), findsOneWidget);
    await tester.tap(find.text('Unlink').last);
    await tester.pumpAndSettle();
    expect(store.data, isNull);
    expect(find.text('Letterboxd unlinked'), findsOneWidget);
    await scrollTo(tester, find.text('Link your Letterboxd account'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Link Letterboxd'), findsOneWidget);
    // Home, then Home again to leave the search form for the mode picker: the prompt is back.
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Home')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Home')));
    await tester.pumpAndSettle();
    expect(find.text('On your watchlist this week'), findsOneWidget);
    expect(find.textContaining('Link Letterboxd in Settings to see'), findsOneWidget);
  });

  testWidgets('a ZIP that is not an export is refused, and cancelling the picker does nothing', (tester) async {
    await openApp(tester);
    await goToLetterboxd(tester);
    picker = () => notAnExport;
    await scrollTo(tester, find.text('Choose file'));
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(find.text("That doesn't look like a Letterboxd export"), findsOneWidget);
    expect(store.data, isNull);

    picker = () => null;
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(store.data, isNull);
    await scrollTo(tester, find.text('Link your Letterboxd account'));
  });

  testWidgets('an old export gets a refresh nudge on Home and on the Letterboxd screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final old = DateTime.now().subtract(const Duration(days: 45));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(SettingsStore(await SharedPreferences.getInstance())),
          listingsProvider.overrideWith(_FakeListings.new),
          letterboxdStoreProvider.overrideWithValue(
            MemoryLetterboxdStore(
              LetterboxdData(
                exportedAt: old,
                importedAt: old,
                username: '',
                watchlist: const [LetterboxdEntry(name: 'Alpha', year: 2026)],
                watched: const [],
              ),
            ),
          ),
          letterboxdRssFetcherProvider.overrideWithValue((user) async => fail('no username: no fetch')),
        ],
        child: const WhatsPlayingApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Refresh your Letterboxd watchlist: your export is 45 days old'), findsOneWidget);
    await tester.tap(find.textContaining('Refresh your Letterboxd watchlist'));
    await tester.pumpAndSettle();
    expect(find.byType(LetterboxdScreen), findsOneWidget);
    expect(find.textContaining('Your export is 45 days old'), findsOneWidget);
    expect(find.text('Letterboxd linked'), findsOneWidget); // no username known
  });
}
