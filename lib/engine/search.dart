import 'package:timezone/timezone.dart' as tz;

import '../core/constants.dart';
import '../core/geo.dart';
import '../core/london_time.dart';
import '../data/listings.dart';
import 'journey_router.dart';
import 'tfl_link.dart';

// Port of `search()` from the Python prototype. Split in two so the app can show instant estimates
// and refine cinema by cinema:
//   [plan]       stages 1-2, purely local (clock times, straight-line bound, which cinemas to check)
//   [routeVenue] stage 3 for one cinema, with whichever [JourneyRouter] is given
//   [search]     both, over every planned cinema - the same thing the prototype does

class Person {
  const Person(this.name, this.origin, this.freeFrom);
  final String name;
  final LatLon origin;
  final tz.TZDateTime freeFrom;
}

enum RankBy { soonest, fairest }

enum RuntimeSource { cinema, tmdb }

class SearchOptions {
  const SearchOptions({
    this.home,
    this.homeBy,
    this.finishBy,
    this.arriveMin = 0,
    this.adsMin = adsAllowanceMin,
    this.meetMin = 0,
    this.maxVenues,
    this.rankBy = RankBy.soonest,
    this.chains,
    this.films,
    this.genres,
    this.excludeFilms,
    this.runtimeFrom = RuntimeSource.cinema,
  }) : assert(home == null || homeBy != null, 'a home needs a home-by time');

  /// Solo: where to get back to, and by when (adds a journey-home check).
  final LatLon? home;
  final tz.TZDateTime? homeBy;

  /// Group: the film must have ended by this time.
  final tz.TZDateTime? finishBy;

  /// When to arrive, in minutes after the listed time (negative = before it).
  final int arriveMin;

  /// Ads and trailers assumed before the film, for when it ends. Arriving later than this means
  /// you expect the film later still, so the later of the two is used.
  final int adsMin;

  /// Be there this many minutes before the arrival deadline (tickets, drinks).
  final int meetMin;
  final int? maxVenues;
  final RankBy rankBy;

  /// Only these chains / film titles / genres (a film needs any one of the genres). All applied
  /// before any lookups.
  final Set<String>? chains, films, genres;

  /// Listings film ids to leave out: "Hide films I've seen" (Letterboxd). Applied before any
  /// lookups, so a seen film costs no journey requests.
  final Set<String>? excludeFilms;
  final RuntimeSource runtimeFrom;
}

/// A performance whose clock times can work, before any journeys are looked up.
class Candidate {
  Candidate({
    required this.venue,
    required this.filmId,
    required this.title,
    required this.film,
    required this.start,
    required this.deadline,
    required this.out,
    required this.filmStarts,
    required this.ends,
    required this.runtime,
    required this.runtimeKnown,
    required this.bookingUrl,
    required this.infoUrl,
    required this.tmdbUrl,
    required this.summary,
    required this.poster,
    this.year,
    this.certificate,
    this.genres = const [],
  });

  final String venue, filmId;
  final String title; // the cinema's own title when it has one
  final String film; // the film's canonical title
  final tz.TZDateTime start, deadline, out, filmStarts, ends;
  final Duration runtime;
  final bool runtimeKnown;
  final String? bookingUrl, infoUrl, tmdbUrl, poster;
  final String summary;
  final String? year, certificate;
  final List<String> genres;
}

class Traveller {
  Traveller({
    required this.name,
    required this.origin,
    required this.freeFrom,
    required this.arrive,
    required this.mode,
    required this.journey,
    this.setOff,
    this.spare,
    this.link,
  });

  final String name;
  final LatLon origin;
  final tz.TZDateTime freeFrom, arrive;
  final String mode;
  final Duration journey;
  final tz.TZDateTime? setOff;
  final Duration? spare;
  final String? link;
}

/// A screening someone can make, with its journeys.
class ResultRow {
  ResultRow({
    required this.c,
    required this.travellers,
    required this.estimated,
    this.leaveBy,
    this.modeHome,
    this.timeHome,
    this.homeAt,
    this.inBed,
    this.linkHome,
    Duration? slack,
  }) : _slack = slack;

  final Candidate c;
  final List<Traveller> travellers; // least spare time first
  final bool estimated;
  final tz.TZDateTime? leaveBy, homeAt, inBed;
  final String? modeHome, linkHome;
  final Duration? timeHome;
  final Duration? _slack;

  Traveller get tight => travellers.first; // least spare time = most constrained
  String get who => tight.name;
  tz.TZDateTime get setOff => tight.setOff!;
  Duration get timeOut => tight.journey;
  String get modeOut => tight.mode;
  String get linkOut => tight.link!;
  Duration get slack => _slack ?? tight.spare!;
  Duration get longest => travellers.map((t) => t.journey).reduce((a, b) => a > b ? a : b);
  Duration get totalTravel => travellers.fold(Duration.zero, (s, t) => s + t.journey);

  String get venue => c.venue;
  tz.TZDateTime get start => c.start;
  String get title => c.title;
}

/// What to put first when the results are sorted. Each key orders screenings; a film or a cinema
/// is placed by its best screening under the same key.
enum SortBy {
  leave('Leave time', 'Soonest to set off first'),
  start('Start time', 'Earliest screening first'),
  home('Home time', 'Earliest back home first'),
  travel('Journey', 'Shortest journey there first');

  const SortBy(this.label, this.hint);
  final String label, hint;

  int compare(ResultRow a, ResultRow b) {
    final c = switch (this) {
      leave => a.setOff.compareTo(b.setOff),
      start => a.start.compareTo(b.start),
      // Without a home to get back to, "home" is when the film lets out.
      home => (a.homeAt ?? a.c.ends).compareTo(b.homeAt ?? b.c.ends),
      travel => a.timeOut.compareTo(b.timeOut),
    };
    if (c != 0) return c;
    final s = a.start.compareTo(b.start);
    return s != 0 ? s : a.setOff.compareTo(b.setOff);
  }
}

class FunnelStep {
  const FunnelStep(this.label, this.performances, [this.venues]);
  final String label;
  final int performances;
  final int? venues;
}

class SearchPlan {
  SearchPlan(this.data, this.people, this.options, this.order, this.byVenue, this.funnel);
  final Listings data;
  final List<Person> people;
  final SearchOptions options;

  /// Cinemas to check, most promising first.
  final List<String> order;
  final Map<String, List<Candidate>> byVenue;
  final List<FunnelStep> funnel;
}

/// What one cinema's journey lookups came to. `failed` = a lookup errored, so "no rows" means
/// "unknown" rather than "can't make it".
class VenueOutcome {
  const VenueOutcome(this.rows, {this.failed = false});
  final List<ResultRow> rows;
  final bool failed;
}

class SearchResult {
  const SearchResult(this.rows, this.funnel, this.errors);
  final List<ResultRow> rows;
  final List<FunnelStep> funnel;
  final List<String> errors;
}

tz.TZDateTime _maxTime(Iterable<tz.TZDateTime> xs) => xs.reduce((a, b) => a.isAfter(b) ? a : b);
tz.TZDateTime _minTime(Iterable<tz.TZDateTime> xs) => xs.reduce((a, b) => a.isBefore(b) ? a : b);
Duration _maxDuration(Iterable<Duration> xs) => xs.reduce((a, b) => a > b ? a : b);

/// Stable sort (Dart's List.sort is not guaranteed stable, Python's is).
List<T> _stableSorted<T>(Iterable<T> xs, int Function(T a, T b) compare) {
  final indexed = xs.toList().asMap().entries.toList()
    ..sort((a, b) {
      final c = compare(a.value, b.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

/// Film titles with at least one performance on `day`, optionally only those starting at or after
/// `after` (hour, minute): the choices for the film filter.
List<String> filmsOn(Listings data, DateTime day, {({int hour, int minute})? after}) {
  final titles = <String>{};
  for (final p in data.performances) {
    final start = fromUnix(p.start);
    if (dayOf(start) != day) continue;
    if (after != null && start.hour * 60 + start.minute < after.hour * 60 + after.minute) continue;
    final film = data.films[data.showings[p.showing].film];
    if (film != null && film.title.isNotEmpty) titles.add(film.title);
  }
  return titles.toList()..sort();
}

/// Genres with at least one film on `day`, optionally only films with a performance at or after
/// `after`: the choices for the genre filter. Alphabetical.
List<String> genresOn(Listings data, DateTime day, {({int hour, int minute})? after}) {
  final genres = <String>{};
  for (final p in data.performances) {
    final start = fromUnix(p.start);
    if (dayOf(start) != day) continue;
    if (after != null && start.hour * 60 + start.minute < after.hour * 60 + after.minute) continue;
    final film = data.films[data.showings[p.showing].film];
    if (film != null) genres.addAll(film.genres);
  }
  return genres.toList()..sort();
}

/// Stages 1-2: everything that can be ruled out without a journey lookup.
SearchPlan plan(Listings data, List<Person> people, SearchOptions o) {
  final venues = data.venues;
  final arrive = Duration(minutes: o.arriveMin), meet = Duration(minutes: o.meetMin);
  final ads = Duration(minutes: o.adsMin > o.arriveMin ? o.adsMin : o.arriveMin);
  final allFree = _maxTime(people.map((p) => p.freeFrom)); // the moment everyone is free
  final day = dayOf(_minTime(people.map((p) => p.freeFrom)));
  final lastStart = at(day.add(const Duration(days: 1)), 4, 0); // up to 4am next day
  final funnel = <FunnelStep>[];
  final films = o.films?.isNotEmpty == true ? o.films : null;
  final genres = o.genres?.isNotEmpty == true ? o.genres : null;
  final chainSet = o.chains?.isNotEmpty == true ? o.chains : null;
  final exclude = o.excludeFilms?.isNotEmpty == true ? o.excludeFilms : null;

  // Stage 1 - purely local: keep performances whose clock times can work at all.
  var perfs = <Candidate>[];
  var nDay = 0;
  for (final perf in data.performances) {
    final s = data.showings[perf.showing];
    final film = data.films[s.film];
    final start = fromUnix(perf.start);
    if (dayOf(start) == day) nDay++;
    if (film == null || perf.soldOut || !venues.containsKey(s.venue) || start.isAfter(lastStart)) continue;
    if (films != null && !films.contains(film.title)) continue;
    if (genres != null && !film.genres.any(genres.contains)) continue;
    // Two runtimes are on offer: the cinema's own (can include adverts) and TMDB's (film only).
    final mins = o.runtimeFrom == RuntimeSource.cinema ? (s.runtime ?? film.runtime) : (film.runtime ?? s.runtime);
    final runtime = Duration(minutes: mins ?? defaultRuntimeMin);
    // There by the listed time plus the chosen offset (minus any meeting-up time).
    final deadline = start.add(arrive).subtract(meet);
    final ends = start.add(ads).add(runtime);
    final out = ends.add(const Duration(minutes: exitBufferMin));
    if (deadline.isBefore(allFree) ||
        (o.homeBy != null && out.isAfter(o.homeBy!)) ||
        (o.finishBy != null && ends.isAfter(o.finishBy!))) {
      continue;
    }
    final tmdbUrl = film.tmdb != null ? '$tmdbMovieUrl${film.tmdb}' : null;
    perfs.add(
      Candidate(
        venue: s.venue,
        filmId: s.film,
        title: s.title ?? film.title,
        film: film.title,
        start: start,
        deadline: deadline,
        out: out,
        filmStarts: start.add(ads),
        ends: ends,
        runtime: runtime,
        runtimeKnown: mins != null,
        bookingUrl: perf.bookingUrl,
        infoUrl: s.url ?? tmdbUrl,
        tmdbUrl: tmdbUrl,
        summary: film.summary ?? '',
        poster: film.poster,
        year: film.year,
        certificate: film.certificate,
        genres: film.genres,
      ),
    );
  }
  FunnelStep count(String label, List<Candidate> ps) =>
      FunnelStep(label, ps.length, {for (final p in ps) p.venue}.length);
  funnel.add(FunnelStep('Performances listed on ${_dayLabel(day)}', nDay));
  final picked = [if (films != null) 'films', if (genres != null) 'genres'];
  funnel.add(
    count('Clock times could work (ignoring travel)${picked.isEmpty ? '' : ', your ${picked.join(' and ')}'}', perfs),
  );
  if (chainSet != null) {
    perfs = [
      for (final p in perfs)
        if (chainSet.contains(venues[p.venue]!.chainOrOther)) p,
    ];
    funnel.add(count('At the chains you picked', perfs));
  }
  if (exclude != null) {
    perfs = [
      for (final p in perfs)
        if (!exclude.contains(p.filmId)) p,
    ];
    funnel.add(count("Films you haven't seen (Letterboxd)", perfs));
  }

  // Stage 2 - still local: straight-line lower bound on travel, for every person (and the way home).
  LatLon geo(String v) => venues[v]!.geo;
  perfs = [
    for (final p in perfs)
      if (people.every((q) => notAfter(q.freeFrom.add(bound(q.origin, geo(p.venue))), p.deadline)) &&
          (o.home == null || notAfter(p.out.add(bound(geo(p.venue), o.home!)), o.homeBy!)))
        p,
  ];
  final byVenue = <String, List<Candidate>>{};
  for (final p in perfs) {
    byVenue.putIfAbsent(p.venue, () => []).add(p);
  }
  funnel.add(count('Not ruled out by straight-line distance', perfs));

  // Which cinemas get the lookups? Those where everyone could be assembled soonest, by rough estimate.
  // (For one person that is simply nearest first. For a group it beats "nearest the midpoint",
  // which ignores who is free when.)
  DateTime ready(String v) => _maxTime(people.map((q) => q.freeFrom.add(guess(q.origin, geo(v)))));
  Duration worst(String v) => _maxDuration(people.map((q) => guess(q.origin, geo(v))));
  var order = o.rankBy == RankBy.fairest
      ? _stableSorted(byVenue.keys, (a, b) => worst(a).compareTo(worst(b)))
      : _stableSorted(byVenue.keys, (a, b) => ready(a).compareTo(ready(b)));
  final cap = o.maxVenues;
  if (cap != null && order.length > cap) {
    order = order.sublist(0, cap);
    final label = people.length == 1
        ? 'Nearest $cap cinemas only'
        : o.rankBy == RankBy.fairest
        ? 'The $cap cinemas with the shortest worst journey'
        : 'The $cap cinemas the group can reach soonest';
    funnel.add(FunnelStep(label, order.fold(0, (n, v) => n + byVenue[v]!.length), order.length));
  }
  return SearchPlan(data, people, o, order, byVenue, funnel);
}

/// Stage 3 for one cinema. One lookup per person (leave when free -> earliest arrival), slowest-looking
/// person first so a cinema is dropped after one lookup if they can't make any screening there.
/// Solo adds one more: home by X -> latest departure from the cinema.
Future<VenueOutcome> routeVenue(SearchPlan sp, String vid, JourneyRouter router) async {
  final o = sp.options;
  final venue = sp.data.venues[vid]!;
  final here = venue.geo;
  var ps = sp.byVenue[vid] ?? const <Candidate>[];
  final arrivals = <Traveller>[];
  final slowestFirst = _stableSorted(
    sp.people,
    (a, b) => b.freeFrom.add(guess(b.origin, here)).compareTo(a.freeFrom.add(guess(a.origin, here))),
  );
  for (final q in slowestFirst) {
    final leg = await router.earliestArrival(q.origin, here, q.freeFrom);
    if (!leg.found) {
      if (leg.error == null) router.errors.add('No journey found for ${q.name} to ${venue.name}');
      return VenueOutcome(const [], failed: leg.error != null);
    }
    ps = [
      for (final p in ps)
        if (notAfter(leg.time!, p.deadline)) p,
    ];
    if (ps.isEmpty) return const VenueOutcome([]);
    arrivals.add(
      Traveller(
        name: q.name,
        origin: q.origin,
        freeFrom: q.freeFrom,
        arrive: leg.time!,
        mode: leg.mode!,
        journey: leg.journey!,
      ),
    );
  }
  Leg? home;
  if (o.home != null) {
    home = await router.latestDeparture(here, o.home!, o.homeBy!);
    if (!home.found) return VenueOutcome(const [], failed: home.error != null);
    final leaveBy = home.time!;
    ps = [
      for (final p in ps)
        if (notAfter(p.out, leaveBy)) p,
    ];
  }
  final rows = <ResultRow>[];
  for (final p in ps) {
    // Journey times come from one lookup per person (and one for the way home). Applying them to
    // each screening's own times is an approximation: timetables shift a little through the evening.
    final travellers = _stableSorted([
      for (final a in arrivals)
        Traveller(
          name: a.name,
          origin: a.origin,
          freeFrom: a.freeFrom,
          arrive: a.arrive,
          mode: a.mode,
          journey: a.journey,
          setOff: latest(a.freeFrom, p.deadline.subtract(a.journey)),
          spare: p.deadline.difference(a.arrive),
          link: tflLink(a.origin, here, p.deadline, true, a.name, venue.name),
        ),
    ], (x, y) => x.spare!.compareTo(y.spare!));
    if (home != null) {
      final homeAt = p.out.add(home.journey!);
      rows.add(
        ResultRow(
          c: p,
          travellers: travellers,
          estimated: router.isEstimate,
          leaveBy: home.time,
          slack: home.time!.difference(p.out),
          modeHome: home.mode,
          timeHome: home.journey,
          homeAt: homeAt,
          inBed: homeAt.add(const Duration(minutes: bedBufferMin)),
          linkHome: tflLink(here, o.home!, p.out, false, venue.name, 'Home'),
        ),
      );
    } else {
      rows.add(ResultRow(c: p, travellers: travellers, estimated: router.isEstimate));
    }
  }
  return VenueOutcome(rows);
}

/// The whole search, as the prototype does it: plan, then look up every planned cinema, 4 at a time.
Future<SearchResult> search(
  Listings data,
  List<Person> people,
  JourneyRouter router, {
  SearchOptions options = const SearchOptions(),
  void Function(String label, int done, int total)? progress,
}) async {
  final sp = plan(data, people, options);
  final results = <ResultRow>[];
  var next = 0, done = 0;
  Future<void> worker() async {
    while (next < sp.order.length) {
      final vid = sp.order[next++];
      results.addAll((await routeVenue(sp, vid, router)).rows);
      progress?.call('Checking journeys', ++done, sp.order.length);
    }
  }

  await Future.wait([for (var i = 0; i < 4; i++) worker()]);
  final funnel = [
    ...sp.funnel,
    FunnelStep(
      options.home != null ? 'Reachable, and home in time' : 'Everyone can get there in time',
      results.length,
      {for (final r in results) r.venue}.length,
    ),
  ];
  results.sort((a, b) {
    final c = a.start.compareTo(b.start);
    return c != 0 ? c : a.venue.compareTo(b.venue);
  });
  return SearchResult(results, funnel, List.of(router.errors));
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _dayLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]}';
