// The results controller: one row per film, arriving cinema by cinema and only ever on the end. A
// cinema answering with a film already shown joins behind that film's row without moving its front.
// Sortable, by a choice of keys, once every cinema has been checked.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:whats_playing/core/geo.dart';
import 'package:whats_playing/core/london_time.dart';
import 'package:whats_playing/data/listings.dart';
import 'package:whats_playing/data/settings_store.dart';
import 'package:whats_playing/engine/journey_router.dart';
import 'package:whats_playing/engine/search.dart';
import 'package:whats_playing/features/results/results_controller.dart';
import 'package:whats_playing/state/app_state.dart';

const origin = (lat: 51.5226, lon: -0.1320);
const near = (lat: 51.5136, lon: -0.1318); // ~1 km
const far = (lat: 51.5033, lon: -0.1195); // ~2.3 km
const broken = (lat: 51.5300, lon: -0.1240); // ~1 km

/// Alpha at the near cinema in 1 hour and at the far one in 3 (as "Alpha (35mm)"), Beta at the far
/// one in 2, Gamma at one TfL can't answer for.
Listings listings(tz.TZDateTime now) {
  int inHours(int h) => now.add(Duration(hours: h)).millisecondsSinceEpoch ~/ 1000;
  final today = dayOf(now);
  return Listings.fromJson({
    'schema': 1,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'from': '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
    'days': 7,
    'venues': {
      'near': {'name': 'Near', 'lat': near.lat, 'lon': near.lon, 'chain': 'Curzon'},
      'far': {'name': 'Far', 'lat': far.lat, 'lon': far.lon, 'chain': null},
      'broken': {'name': 'Broken', 'lat': broken.lat, 'lon': broken.lon, 'chain': 'Curzon'},
    },
    'films': {
      'f1': {
        'title': 'Alpha',
        'runtime': 95,
        'genres': ['Drama', 'Thriller'],
      },
      'f2': {
        'title': 'Beta',
        'runtime': 95,
        'genres': ['Comedy'],
      },
      'f3': {'title': 'Gamma', 'runtime': 95},
    },
    'showings': [
      {'film': 'f1', 'venue': 'near', 'title': null, 'runtime': null, 'url': null},
      {'film': 'f2', 'venue': 'far', 'title': null, 'runtime': null, 'url': null},
      {'film': 'f3', 'venue': 'broken', 'title': null, 'runtime': null, 'url': null},
      {'film': 'f1', 'venue': 'far', 'title': 'Alpha (35mm)', 'runtime': null, 'url': null},
    ],
    'performances': [
      [0, inHours(1), null, 0],
      [1, inHours(2), null, 0],
      [2, inHours(1), null, 0],
      [3, inHours(3), null, 0],
    ],
  });
}

/// "TfL" that holds each answer until the test releases that cinema. 10 minutes to anywhere.
class _GatedTfl extends JourneyRouter {
  final gates = <LatLon, Completer<void>>{};

  @override
  bool get isEstimate => false;

  void release(LatLon b) => gates.putIfAbsent(b, Completer.new).complete();

  @override
  Future<Leg> earliestArrival(LatLon a, LatLon b, tz.TZDateTime depart) async {
    calls++;
    await gates.putIfAbsent(b, Completer.new).future;
    if (b == broken) return const Leg.none(error: 'TfL HTTP 500');
    return Leg(depart.add(const Duration(minutes: 10)), 'Tube', const Duration(minutes: 10));
  }

  @override
  Future<Leg> latestDeparture(LatLon a, LatLon b, tz.TZDateTime arriveBy) async =>
      Leg(arriveBy.subtract(const Duration(minutes: 10)), 'Tube', const Duration(minutes: 10));
}

void main() {
  setUpAll(tz_data.initializeTimeZones);

  late SettingsStore store;
  late _GatedTfl tfl;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = SettingsStore(await SharedPreferences.getInstance());
    tfl = _GatedTfl();
    container = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(store), tflRouterProvider.overrideWithValue(tfl)],
    );
    addTearDown(container.dispose);
  });

  test('films are appended as cinemas answer, grouped by film, then sorted on request', () async {
    final ctrl = container.read(resultsProvider.notifier);
    ResultsState s() => container.read(resultsProvider)!;
    List<String> films() => [for (final c in s().cards) c.c.film];
    FilmCard alpha() => s().cards.singleWhere((c) => c.c.film == 'Alpha');

    final now = londonNow();
    ctrl.start(listings(now), [Person('You', origin, now)], const SearchOptions());
    await pumpEventQueue();
    expect(s().cards, isEmpty);
    expect((s().checked, s().total, s().finished), (0, 3, false));

    // The far cinema answers first: both its films go up straight away, soonest to leave for first.
    tfl.release(far);
    await pumpEventQueue();
    expect(films(), ['Beta', 'Alpha']);
    expect(alpha().here.venue.id, 'far');
    expect(alpha().c.title, 'Alpha (35mm)');
    expect(alpha().otherCinemas, 0);

    // The near one has Alpha too, an hour sooner. It joins behind the existing row: the row stays
    // where it is and keeps its front, so nothing moves under the user.
    tfl.release(near);
    await pumpEventQueue();
    expect(films(), ['Beta', 'Alpha']);
    expect(alpha().here.venue.id, 'far');
    expect(alpha().otherCinemas, 1);
    expect(alpha().screenings, 2);
    expect([for (final a in alpha().cinemas) a.venue.id], ['far', 'near']);
    expect(s().finished, isFalse);

    ctrl.sort(SortBy.leave); // not yet: still checking
    expect(films(), ['Beta', 'Alpha']);
    expect(s().sorted, isFalse);

    // A failed lookup counts as checked, with no card.
    tfl.release(broken);
    await pumpEventQueue();
    expect((s().checked, s().failed, s().finished), (3, 1, true));
    expect(films(), ['Beta', 'Alpha']);

    // Sorting puts the best screening on the front of each film, and the films in that order.
    ctrl.sort(SortBy.leave);
    expect(films(), ['Alpha', 'Beta']);
    expect(alpha().here.venue.id, 'near');
    expect(alpha().c.title, 'Alpha');
    expect([for (final a in alpha().cinemas) a.venue.id], ['near', 'far']);
    expect((s().sorted, s().sortBy), (true, SortBy.leave));

    // Another key re-sorts, and the choice is remembered for next time.
    ctrl.sort(SortBy.start);
    expect(films(), ['Alpha', 'Beta']);
    expect(s().sortBy, SortBy.start);
    await pumpEventQueue(); // the save is not awaited
    expect(store.load().sortBy, SortBy.start);
  });

  test('filters narrow what is shown without touching what was found', () async {
    final ctrl = container.read(resultsProvider.notifier);
    ResultsState s() => container.read(resultsProvider)!;
    List<String> shown() => [for (final c in s().shown) c.c.film];

    final now = londonNow();
    ctrl.start(listings(now), [Person('You', origin, now)], const SearchOptions());
    await pumpEventQueue();
    tfl.release(far);
    await pumpEventQueue();
    expect(shown(), ['Beta', 'Alpha']);

    // The choices on offer are what has been found so far, and the filter can be set mid-search.
    expect(s().filmChoices, [('f1', 'Alpha'), ('f2', 'Beta')]);
    expect(s().chainChoices, ['Independent / other']);
    expect(s().genreChoices, ['Comedy', 'Drama', 'Thriller']);
    ctrl.filter(const ResultsFilter(genres: {'Thriller'}));
    expect(shown(), ['Alpha']);
    expect(s().cards.length, 2);
    expect(s().nothingShown, isFalse);

    // Alpha's front stays at the far cinema (an "other"); Curzon only leaves the near cinema, so
    // the front becomes the near screening. Alpha at the far one is still there behind the filter.
    tfl.release(near);
    tfl.release(broken);
    await pumpEventQueue();
    expect(s().chainChoices, ['Curzon', 'Independent / other']);
    ctrl.filter(const ResultsFilter(chains: {'Curzon'}));
    expect(shown(), ['Alpha']);
    final alpha = s().shown.single;
    expect(alpha.here.venue.id, 'near');
    expect(alpha.c.title, 'Alpha');
    expect(alpha.otherCinemas, 0);
    expect(s().cards.singleWhere((c) => c.key == 'f1').cinemas.length, 2);

    // Both chains = the same as no chain filter; a film filter picks by listings id.
    ctrl.filter(const ResultsFilter(chains: {'Curzon', 'Independent / other'}, films: {'f2'}));
    expect(shown(), ['Beta']);
    expect(s().filter.count, 3);

    // Filters that nothing satisfies leave the list empty but the results intact.
    ctrl.filter(const ResultsFilter(films: {'f2'}, genres: {'Thriller'}));
    expect(shown(), isEmpty);
    expect((s().isEmpty, s().nothingShown), (false, true));

    // Sorting and filtering are independent; the filter survives a sort.
    ctrl.filter(const ResultsFilter(chains: {'Independent / other'}));
    ctrl.sort(SortBy.leave);
    expect([for (final c in s().cards) c.c.film], ['Alpha', 'Beta']);
    expect(shown(), ['Alpha', 'Beta']);
    expect(s().shown.first.here.venue.id, 'far');
    expect(s().shown.first.c.title, 'Alpha (35mm)');

    // A new search starts unfiltered.
    ctrl.start(listings(now), [Person('You', origin, now)], const SearchOptions());
    expect(s().filter.isEmpty, isTrue);
  });

  test('a new search abandons the old one', () async {
    final ctrl = container.read(resultsProvider.notifier);

    final now = londonNow();
    ctrl.start(listings(now), [Person('You', origin, now)], const SearchOptions());
    await pumpEventQueue();
    ctrl.clear();
    tfl
      ..release(near)
      ..release(far)
      ..release(broken);
    await pumpEventQueue();
    expect(container.read(resultsProvider), isNull);
  });
}
