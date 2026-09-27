// Settings -> Defaults for search: every new search starts from them, a search never writes back,
// and cinemas, films and genres always start as any (even with values left over from before).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:whats_playing/app.dart';
import 'package:whats_playing/core/london_time.dart';
import 'package:whats_playing/data/listings.dart';
import 'package:whats_playing/data/settings_store.dart';
import 'package:whats_playing/features/search_form/search_form.dart';
import 'package:whats_playing/features/settings/settings_screen.dart';
import 'package:whats_playing/state/app_state.dart';

class _FakeListings extends ListingsNotifier {
  @override
  Future<Listings> build() async {
    final today = dayOf(londonNow());
    return Listings.fromJson({
      'schema': 1,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'from': '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
      'days': 7,
      'venues': {
        'v': {'name': 'Curzon Soho', 'lat': 51.5136, 'lon': -0.1318, 'chain': 'Curzon'},
      },
      'films': {
        'f': {'title': 'Alpha', 'runtime': 90},
      },
      'showings': [
        {'film': 'f', 'venue': 'v'},
      ],
      'performances': [
        [0, londonNow().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000, null, 0],
      ],
    });
  }
}

void main() {
  setUpAll(tz_data.initializeTimeZones);

  testWidgets('the form starts from the defaults in Settings, and follows changes to them', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'homeBy': '22:45',
      'setOff': '19:20',
      'setOffNowToday': false,
      'arriveMin': -10,
      // Left over from earlier versions: ignored now.
      'arriveFor': 'trailers',
      'adsMin': 30,
      'startFrom': 'postcode',
      'lastPostcode': 'WC1E 6BT',
      'chains': ['Curzon'],
    });
    final store = SettingsStore(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsStoreProvider.overrideWithValue(store), listingsProvider.overrideWith(_FakeListings.new)],
        child: const WhatsPlayingApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solo'));
    await tester.pumpAndSettle();

    final form = find.descendant(of: find.byType(SearchForm), matching: find.byType(Scrollable)).first;
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Where I am now')).selected, isTrue);
    expect(find.byType(TextField), findsNothing); // no postcode carried over
    expect(find.text('22:45'), findsOneWidget);

    // Another day: the default set-off time.
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomorrow'));
    await tester.pumpAndSettle();
    expect(find.text('from 19:20'), findsOneWidget);

    await tester.scrollUntilVisible(find.byType(Slider), 200, scrollable: form);
    expect(find.text('Any'), findsNWidgets(3)); // cinemas, films, genres
    expect(find.text('10 min before'), findsOneWidget);

    // Change a default in Settings: the open form takes it, and it is saved.
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
    await tester.pumpAndSettle();
    expect(find.text('Defaults for search'), findsOneWidget);
    expect(find.text('Timing'), findsOneWidget);
    final settingsList = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first;
    final settingsSlider = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Slider));
    await tester.scrollUntilVisible(settingsSlider, 200, scrollable: settingsList);
    await tester.ensureVisible(settingsSlider);
    await tester.pumpAndSettle();
    expect(find.text('10 min before'), findsOneWidget);
    await tester.drag(settingsSlider, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(store.load().arriveMin, 25);

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Home')));
    await tester.pumpAndSettle();
    expect(find.text('25 min after'), findsOneWidget);

    // Leftovers are cleared from storage on the next save.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('chains'), isFalse);
    expect(prefs.containsKey('lastPostcode'), isFalse);
    expect(prefs.containsKey('arriveFor'), isFalse);
    expect(prefs.containsKey('adsMin'), isFalse);
  });

  testWidgets('the genre sheet scrolls when there are more genres than fit', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore(await SharedPreferences.getInstance());
    final genres = [for (var i = 0; i < 60; i++) 'Genre number $i'];
    final today = dayOf(londonNow());
    final listings = Listings.fromJson({
      'schema': 1,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'from': '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
      'days': 7,
      'venues': {
        'v': {'name': 'V', 'lat': 51.5, 'lon': -0.1, 'chain': null},
      },
      'films': {
        'f': {'title': 'F', 'runtime': 90, 'genres': genres},
      },
      'showings': [
        {'film': 'f', 'venue': 'v'},
      ],
      'performances': [
        [0, londonNow().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000, null, 0],
      ],
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          listingsProvider.overrideWith(() => _Fixed(listings)),
        ],
        child: const WhatsPlayingApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solo'));
    await tester.pumpAndSettle();
    final form = find.descendant(of: find.byType(SearchForm), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Genres'), 200, scrollable: form);
    await tester.ensureVisible(find.text('Genres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genres'));
    await tester.pumpAndSettle();

    // No overflow, the buttons are on screen, and the last genre can be scrolled to and picked.
    expect(tester.takeException(), isNull);
    expect(find.text('Done'), findsOneWidget);
    final sheet = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Genre number 59'), 200, scrollable: sheet);
    await tester.ensureVisible(find.text('Genre number 59'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genre number 59'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Genre number 59'), findsOneWidget); // the Genres row's value
  });
}

class _Fixed extends ListingsNotifier {
  _Fixed(this.listings);
  final Listings listings;

  @override
  Future<Listings> build() async => listings;
}
