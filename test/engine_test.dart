// Port of `Movie search/test_filmfinder.py`: a tiny made-up listings file and scripted journey
// times (no network). Same fixture, same expected times as the Python suite.
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:whats_playing/core/constants.dart';
import 'package:whats_playing/core/geo.dart';
import 'package:whats_playing/core/london_time.dart';
import 'package:whats_playing/data/listings.dart';
import 'package:whats_playing/engine/journey_router.dart';
import 'package:whats_playing/engine/search.dart';
import 'package:whats_playing/engine/tfl_link.dart';

final day = DateTime.utc(2026, 9, 24);
tz.TZDateTime t(String hhmm) => parseClock(hhmm, day);

const venues = <String, LatLon>{
  'near': (lat: 51.52, lon: -0.13),
  'mid': (lat: 51.51, lon: -0.10),
  'far': (lat: 51.50, lon: -0.02),
};
const a = (lat: 51.525, lon: -0.134), b = (lat: 51.505, lon: -0.023), home = (lat: 51.46, lon: -0.11);

late Listings data;

Listings fixture() {
  int unix(String hhmm) => t(hhmm).millisecondsSinceEpoch ~/ 1000;
  return Listings.fromJson({
    'schema': 1,
    'generatedAt': '2026-09-24T06:40:00Z',
    'venues': {
      for (final e in venues.entries)
        e.key: {
          'name': e.key[0].toUpperCase() + e.key.substring(1),
          'lat': e.value.lat,
          'lon': e.value.lon,
          'chain': e.key == 'near' ? 'Curzon' : null,
        },
    },
    'films': {
      'f1': {
        'title': 'Alpha',
        'runtime': 100,
        'tmdb': 1,
        'poster': '/a.jpg',
        'summary': 's',
        'genres': ['Drama'],
      },
      'f2': {'title': 'Beta', 'runtime': 90, 'tmdb': null, 'poster': null, 'summary': null},
    },
    'showings': [
      {'film': 'f1', 'venue': 'near', 'title': null, 'runtime': 100, 'url': 'u'},
      {'film': 'f2', 'venue': 'mid', 'title': 'BETA (35mm)', 'runtime': null, 'url': 'u'},
      {'film': 'f1', 'venue': 'far', 'title': null, 'runtime': 120, 'url': 'u'},
    ],
    'performances': [
      [0, unix('19:00'), 'b', 0],
      [0, unix('20:30'), 'b', 0],
      [0, unix('21:00'), 'b', 1], // sold out
      [1, unix('19:30'), 'b', 0],
      [2, unix('19:15'), 'b', 0],
    ],
  });
}

/// Journey minutes looked up from a table: {(person origin, venue id): minutes}.
class ScriptedRouter extends JourneyRouter {
  ScriptedRouter(this.minutes, {this.homeMinutes = 30});
  final Map<(LatLon, String), int> minutes;
  final int homeMinutes;
  final log = <(LatLon, String)>[];

  @override
  bool get isEstimate => false;

  @override
  Future<Leg> earliestArrival(LatLon from, LatLon to, tz.TZDateTime depart) async {
    calls++;
    final venue = venues.entries.firstWhere((e) => e.value == to).key;
    log.add((from, venue));
    final m = minutes[(from, venue)];
    return m == null ? const Leg.none() : Leg(depart.add(Duration(minutes: m)), 'Tube', Duration(minutes: m));
  }

  @override
  Future<Leg> latestDeparture(LatLon from, LatLon to, tz.TZDateTime arriveBy) async {
    calls++;
    final m = Duration(minutes: homeMinutes);
    return Leg(arriveBy.subtract(m), 'Bus', m);
  }
}

Person person(String name, LatLon origin, String free) => Person(name, origin, t(free));

List<(String, String)> keys(List<ResultRow> results) {
  String hm(tz.TZDateTime x) => '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
  return [for (final r in results) (r.venue, hm(r.start))]..sort((x, y) {
    final c = x.$1.compareTo(y.$1);
    return c != 0 ? c : x.$2.compareTo(y.$2);
  });
}

Map<(LatLon, String), int> everywhere(int m) => {
  for (final p in [a, b])
    for (final v in venues.keys) (p, v): m,
};

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    data = fixture();
  });

  test('most constrained person and set off', () async {
    final r = ScriptedRouter({
      (a, 'near'): 10, (b, 'near'): 40, (a, 'mid'): 20, (b, 'mid'): 20, (a, 'far'): 40, (b, 'far'): 10, //
    });
    final res = (await search(
      data,
      [person('Asha', a, '18:00'), person('Ben', b, '18:00')],
      r,
      options: const SearchOptions(arriveMin: 20),
    )).rows;
    final near = res.firstWhere((x) => x.venue == 'near' && x.start == t('19:00'));
    expect(near.who, 'Ben'); // 40 min journey beats 10
    expect(near.c.deadline, t('19:20')); // arrive 20 min after the listed 19:00
    expect(near.setOff, t('18:40'));
    expect(near.timeOut, const Duration(minutes: 40));
    final asha = near.travellers.firstWhere((x) => x.name == 'Asha');
    expect(asha.setOff, t('19:10'));
    expect(asha.spare, const Duration(minutes: 70));
    expect(res.firstWhere((x) => x.venue == 'far').who, 'Asha');
    expect(near.homeAt, isNull); // no journey home in group mode
    expect(near.linkHome, isNull);
  });

  test('free-from decides who is tight', () async {
    final r = ScriptedRouter({(a, 'near'): 10, (b, 'near'): 40});
    final res = (await search(
      data,
      [person('Asha', a, '19:05'), person('Ben', b, '18:00')],
      r,
      options: const SearchOptions(chains: {'Curzon'}, arriveMin: 20),
    )).rows;
    final first = res.firstWhere((x) => x.start == t('19:00'));
    expect(first.who, 'Asha'); // arrives 19:15 vs Ben's 18:40
    expect(first.setOff, t('19:10'));
  });

  test('arrive before or after the listed time; the film end allows for the ads either way', () async {
    Future<ResultRow> near19(int arriveMin) async => (await search(
      data,
      [person('Asha', a, '18:00')],
      ScriptedRouter({(a, 'near'): 10}),
      options: SearchOptions(chains: const {'Curzon'}, arriveMin: arriveMin),
    )).rows.firstWhere((x) => x.start == t('19:00'));

    final early = await near19(-15);
    expect(early.c.deadline, t('18:45'));
    expect(early.setOff, t('18:35'));
    // Arriving early doesn't make the film end sooner: the usual ads allowance still applies.
    expect(early.c.ends, t('19:00').add(const Duration(minutes: adsAllowanceMin)).add(early.c.runtime));

    final onTime = await near19(0);
    expect(onTime.c.deadline, t('19:00'));
    expect(onTime.c.ends, early.c.ends);

    // Arriving later than the allowance means the film is expected later still.
    final late = await near19(25);
    expect(late.c.deadline, t('19:25'));
    expect(late.c.ends, t('19:25').add(late.c.runtime));
  });

  test('never set off before free', () async {
    final r = ScriptedRouter({(a, 'near'): 10});
    final res = (await search(
      data,
      [person('Asha', a, '18:00')],
      r,
      options: SearchOptions(home: home, homeBy: t('23:59'), chains: const {'Curzon'}),
    )).rows;
    expect(res, isNotEmpty);
    expect(res.every((x) => !x.setOff.isBefore(t('18:00'))), isTrue);
  });

  test('early stop saves lookups', () async {
    // Ben cannot reach "near" for any screening (needs 200 min), and is looked up first as the slower guess
    final r = ScriptedRouter({(a, 'near'): 10, (b, 'near'): 200});
    final res = (await search(
      data,
      [person('Asha', a, '18:00'), person('Ben', b, '18:00')],
      r,
      options: const SearchOptions(chains: {'Curzon'}),
    )).rows;
    expect(res, isEmpty);
    expect(r.calls, 1);
    expect(r.log, [(b, 'near')]);
  });

  test('finish-by, meet buffer, film filter, sold out', () async {
    final people = [person('Asha', a, '18:00'), person('Ben', b, '18:00')];
    final everything = (await search(data, people, ScriptedRouter(everywhere(15)))).rows;
    expect(keys(everything), [
      ('far', '19:15'),
      ('mid', '19:30'),
      ('near', '19:00'),
      ('near', '20:30'),
    ]); // 21:00 sold out
    final early = (await search(
      data,
      people,
      ScriptedRouter(everywhere(15)),
      options: SearchOptions(finishBy: t('21:30')),
    )).rows;
    expect(keys(early), [('mid', '19:30'), ('near', '19:00')]); // far ends 21:35 (120 min), near 20:30 ends 22:30
    final alpha = (await search(
      data,
      people,
      ScriptedRouter(everywhere(15)),
      options: const SearchOptions(films: {'Alpha'}),
    )).rows;
    expect({for (final x in alpha) x.venue}, {'near', 'far'});
    expect(alpha.first.c.genres, ['Drama']);
    final drama = (await search(
      data,
      people,
      ScriptedRouter(everywhere(15)),
      options: const SearchOptions(genres: {'Drama', 'Horror'}),
    )).rows;
    expect({for (final x in drama) x.venue}, {'near', 'far'}); // Beta has no genres, so it is left out
    expect(
      (await search(
        data,
        people,
        ScriptedRouter(everywhere(15)),
        options: const SearchOptions(genres: {'Comedy'}),
      )).rows,
      isEmpty,
    );
    final late = [person('Asha', a, '19:00'), person('Ben', b, '19:00')];
    expect(
      keys(
        (await search(data, late, ScriptedRouter(everywhere(15)), options: const SearchOptions(arriveMin: 20))).rows,
      ),
      contains(('near', '19:00')),
    ); // arrive 19:15 <= 19:20
    expect(
      keys(
        (await search(
          data,
          late,
          ScriptedRouter(everywhere(15)),
          options: const SearchOptions(meetMin: 10, arriveMin: 20),
        )).rows,
      ),
      isNot(contains(('near', '19:00'))), // deadline now 19:10
    );
    final beta = everything.firstWhere((x) => x.venue == 'mid');
    expect(beta.title, 'BETA (35mm)');
    expect(beta.c.film, 'Beta');
    expect(beta.c.runtime, const Duration(minutes: 90));
  });

  test('cinema cap prefers soonest assembled', () async {
    // Ben (east) is free last, so the cinema nearest Ben should be kept, not the one nearest Asha
    final people = [person('Asha', a, '17:00'), person('Ben', b, '18:30')];
    var res = (await search(
      data,
      people,
      ScriptedRouter(everywhere(15)),
      options: const SearchOptions(maxVenues: 1),
    )).rows;
    expect({for (final x in res) x.venue}, {'far'});
    // "fairest" ignores free-from times and keeps the cinema with the shortest worst journey: the middle one
    res = (await search(
      data,
      people,
      ScriptedRouter(everywhere(15)),
      options: const SearchOptions(maxVenues: 1, rankBy: RankBy.fairest),
    )).rows;
    expect({for (final x in res) x.venue}, {'mid'});
  });

  test('solo has journey home', () async {
    final r = ScriptedRouter({for (final v in venues.keys) (a, v): 15}, homeMinutes: 30);
    final res = (await search(
      data,
      [person('You', a, '18:00')],
      r,
      options: SearchOptions(home: home, homeBy: t('22:00')),
    )).rows;
    // leave-by is 21:30. far is out at 21:40 and near's 20:30 at 22:35, so both go; mid is out at 21:25
    expect(keys(res), [('mid', '19:30'), ('near', '19:00')]);
    final x = res.firstWhere((y) => y.venue == 'near');
    expect(x.leaveBy, t('21:30'));
    expect(x.c.out, t('21:05'));
    expect(x.homeAt, t('21:35'));
    expect(x.inBed, t('21:40'));
    expect(x.slack, const Duration(minutes: 25));
    expect(x.linkHome, contains('TimeIs=departing'));
    expect(x.linkHome, contains('Time=2105'));
  });

  test('missing journey is reported by name', () async {
    final r = ScriptedRouter({(a, 'near'): 10}); // nothing for Ben
    final res = (await search(
      data,
      [person('Asha', a, '18:00'), person('Ben', b, '18:00')],
      r,
      options: const SearchOptions(chains: {'Curzon'}),
    )).rows;
    expect(res, isEmpty);
    expect(r.errors.any((e) => e.contains('Ben')), isTrue);
  });

  test('tfl link format', () {
    final url = tflLink(a, venues['near']!, t('19:20'), true, 'Asha', 'Curzon Soho');
    expect(
      url,
      'https://tfl.gov.uk/plan-a-journey/results?InputFrom=Asha&FromId=51.52500%2C-0.13400'
      '&InputTo=Curzon+Soho&ToId=51.52000%2C-0.13000&Date=20260924&Time=1920'
      '&TimeIs=arriving&JourneyPreference=leasttime',
    );
  });

  test('films on', () {
    expect(filmsOn(data, day), ['Alpha', 'Beta']);
    expect(filmsOn(data, day.add(const Duration(days: 1))), isEmpty);
    expect(filmsOn(data, day, after: (hour: 20, minute: 0)), ['Alpha']); // only Alpha has a screening from 20:00
    expect(genresOn(data, day), ['Drama']);
    expect(genresOn(data, day.add(const Duration(days: 1))), isEmpty);
  });

  // ---- Beyond the Python suite: the two things most likely to go wrong in a port ----

  test('clocks going back (25 Oct 2026) keeps London wall times right', () {
    // 19:00 UTC on 24 Oct is 20:00 BST; 19:00 UTC on 25 Oct is 19:00 GMT.
    final before = fromUnix(DateTime.utc(2026, 10, 24, 19).millisecondsSinceEpoch ~/ 1000);
    final after = fromUnix(DateTime.utc(2026, 10, 25, 19).millisecondsSinceEpoch ~/ 1000);
    expect((before.hour, dayOf(before)), (20, DateTime.utc(2026, 10, 24)));
    expect((after.hour, dayOf(after)), (19, DateTime.utc(2026, 10, 25)));
    // A journey across the change is measured in real time: 00:30 BST + 90 min = 01:00 GMT.
    final halfPast = tz.TZDateTime(london, 2026, 10, 25, 0, 30);
    final plus90 = halfPast.add(const Duration(minutes: 90));
    expect((plus90.hour, plus90.minute, plus90.timeZoneName), (1, 0, 'GMT'));
  });

  test('home-by past midnight means tomorrow', () {
    final free = t('18:00');
    expect(later(0, 30, free), parseClock('00:30', day.add(const Duration(days: 1))));
    expect(later(23, 0, free), t('23:00'));
  });

  test('estimate router gives instant, marked-as-estimate results', () async {
    final res = (await search(
      data,
      [person('You', a, '18:00')],
      EstimateRouter(),
      options: SearchOptions(home: home, homeBy: t('23:30')),
    )).rows;
    expect(res, isNotEmpty);
    expect(res.every((r) => r.estimated && r.modeOut == 'estimate'), isTrue);
  });
}
