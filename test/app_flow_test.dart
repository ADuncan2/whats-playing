// The core loop, end to end with fakes for the network: open the app -> Solo -> Find films ->
// a row per film -> sort -> tap a row to open every cinema and time.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:whats_playing/app.dart';
import 'package:whats_playing/core/geo.dart';
import 'package:whats_playing/core/london_time.dart';
import 'package:whats_playing/data/listings.dart';
import 'package:whats_playing/data/place_services.dart';
import 'package:whats_playing/data/settings_store.dart';
import 'package:whats_playing/engine/journey_router.dart';
import 'package:whats_playing/engine/search.dart';
import 'package:whats_playing/state/app_state.dart';

const origin = (lat: 51.5226, lon: -0.1320); // WC1E 6BT-ish
const cinema = (lat: 51.5136, lon: -0.1318); // ~1 km south

/// Two films at one cinema, starting 1 and 2 hours from now. No posters, so no image loading.
Listings listingsFromNow() {
  final now = londonNow();
  int inHours(int h) => now.add(Duration(hours: h)).millisecondsSinceEpoch ~/ 1000;
  final today = dayOf(now);
  return Listings.fromJson({
    'schema': 1,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'from': '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
    'days': 7,
    'venues': {
      'curzon': {'name': 'Curzon Soho', 'lat': cinema.lat, 'lon': cinema.lon, 'chain': 'Curzon'},
    },
    'films': {
      'f1': {
        'title': 'Alpha',
        'runtime': 95,
        'year': '2026',
        'certificate': '15',
        'summary': 'A film about alphas.',
        'genres': ['Drama'],
      },
      'f2': {
        'title': 'Beta',
        'runtime': 100,
        'summary': 'Beta summary.',
        'genres': ['Comedy'],
      },
    },
    'showings': [
      {'film': 'f1', 'venue': 'curzon', 'title': null, 'runtime': null, 'url': 'https://curzon/alpha'},
      {'film': 'f2', 'venue': 'curzon', 'title': null, 'runtime': null, 'url': 'https://curzon/beta'},
    ],
    'performances': [
      [0, inHours(1), 'https://book/alpha', 0],
      [1, inHours(2), 'https://book/beta', 0],
    ],
  });
}

class _FakeListings extends ListingsNotifier {
  @override
  Future<Listings> build() async => listingsFromNow();
}

class _FakePostcodes extends PostcodeService {
  @override
  Future<LatLon> locate(String text) async => origin;
}

class _FakeLocation extends LocationService {
  @override
  Future<LatLon> current() async => origin;
}

/// "TfL" that answers instantly with a 10-minute journey each way.
class _FakeTfl extends JourneyRouter {
  @override
  bool get isEstimate => false;

  @override
  Future<Leg> earliestArrival(LatLon a, LatLon b, tz.TZDateTime depart) async {
    calls++;
    return Leg(depart.add(const Duration(minutes: 10)), 'Tube', const Duration(minutes: 10));
  }

  @override
  Future<Leg> latestDeparture(LatLon a, LatLon b, tz.TZDateTime arriveBy) async {
    calls++;
    return Leg(arriveBy.subtract(const Duration(minutes: 10)), 'Tube', const Duration(minutes: 10));
  }
}

void main() {
  setUpAll(tz_data.initializeTimeZones);

  testWidgets('open -> Solo -> Find films -> sort -> open a row', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final now = londonNow();
    final homeBy = now.add(const Duration(hours: 6));
    SharedPreferences.setMockInitialValues({'homeBy': '${homeBy.hour}:${homeBy.minute}'});
    final store = SettingsStore(await SharedPreferences.getInstance());
    final tfl = _FakeTfl();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          listingsProvider.overrideWith(_FakeListings.new),
          postcodeServiceProvider.overrideWithValue(_FakePostcodes()),
          locationServiceProvider.overrideWithValue(_FakeLocation()),
          tflRouterProvider.overrideWithValue(tfl),
        ],
        child: const WhatsPlayingApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The mode picker: Solo works, Group is flagged as not ready yet (below the watchlist prompt).
    expect(find.text('Solo'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Still in development'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Group'));
    await tester.pumpAndSettle();
    expect(find.text('Group'), findsOneWidget);
    expect(find.text('Still in development'), findsOneWidget);
    await tester.tap(find.text('Group'));
    await tester.pumpAndSettle();
    expect(find.text('Find films'), findsNothing);
    await tester.tap(find.text('Solo'));
    await tester.pumpAndSettle();

    // Start and end, each with where and when, pre-filled from the defaults; filters below.
    expect(find.text('Where and when are you starting?'), findsOneWidget);
    expect(find.text('Where and when are you ending up?'), findsOneWidget);
    expect(find.text('Postcode'), findsNWidgets(2));
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Where I am now')).selected, isTrue);
    expect(find.text('Same as start'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.textContaining('from '), findsOneWidget);
    expect(find.text('Back by'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Films'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Cinemas'), findsOneWidget);
    expect(find.text('Films'), findsOneWidget);

    // Arrive early, this search only.
    await tester.scrollUntilVisible(find.byType(Slider), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byType(Slider));
    await tester.pumpAndSettle();
    expect(find.text('At the listed time'), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('min before'), findsWidgets);

    // Everything is pre-filled: one tap gets to the results: a row per film, soonest to leave first.
    expect(find.text('Find films'), findsOneWidget);
    await tester.tap(find.text('Find films'));
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('2 films · 2 screenings at 1 cinema'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Leave'), findsNWidgets(2));
    expect(find.descendant(of: find.byType(ListView), matching: find.text('Home')), findsNWidgets(2));
    expect(find.text('Curzon Soho'), findsNWidgets(2));
    expect(tester.getTopLeft(find.text('Alpha')).dy, lessThan(tester.getTopLeft(find.text('Beta')).dy));

    // TfL answered (fake, instantly), so the search is done and the rows can be sorted.
    expect(tfl.calls, greaterThan(0));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final sortButton = find.byTooltip('Sort');
    expect(sortButton, findsOneWidget);
    await tester.tap(sortButton);
    await tester.pumpAndSettle();
    expect(find.text('Start time'), findsOneWidget);
    await tester.tap(find.text('Start time'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sorted by start time'), findsOneWidget);
    expect(store.load().sortBy, SortBy.start);

    // Filter: pick a genre in the sheet; the button says what that leaves, the list narrows, and the
    // filter shows as a chip that can be taken off again. One chain only, so no cinema section.
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    expect(find.text('Filter results'), findsOneWidget);
    expect(find.text('Cinemas'), findsNothing);
    expect(find.text('Genres'), findsOneWidget);
    expect(find.text('Show all'), findsOneWidget);
    await tester.tap(find.text('Comedy'));
    await tester.pumpAndSettle();
    expect(find.text('Show 1 film'), findsOneWidget);
    await tester.tap(find.text('Show 1 film'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 films · 1 screening at 1 cinema'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    expect(find.byTooltip('Filter (1 on)'), findsOneWidget);
    expect(find.byType(InputChip), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(InputChip), matching: find.byIcon(Icons.clear)));
    await tester.pumpAndSettle();
    expect(find.text('2 films · 2 screenings at 1 cinema'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);

    // Tap a row to open it in place: description, runtime, and a Book link per screening.
    expect(find.text('A film about alphas.'), findsNothing);
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.text('A film about alphas.'), findsOneWidget);
    expect(find.textContaining('1h 35m'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('Route there'), findsOneWidget);
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(find.text('Beta summary.'), findsOneWidget);

    // Back returns to the form with the search just run, but nothing from it went into Settings.
    await tester.tap(find.byTooltip('Change search'));
    await tester.pumpAndSettle();
    expect(find.text('Find films'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(Slider), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('min before'), findsWidgets);
    expect(store.load().arriveMin, 0);

    // Tapping the Home tab from the form goes back to the mode picker.
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Home')));
    await tester.pumpAndSettle();
    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Find films'), findsNothing);

    // A new search starts from the defaults again.
    await tester.tap(find.text('Solo'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(Slider), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('At the listed time'), findsOneWidget);
    expect(find.textContaining('min before'), findsNothing);
  });
}
