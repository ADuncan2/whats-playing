import 'package:timezone/timezone.dart' as tz;

import '../core/london_time.dart';
import '../data/letterboxd/letterboxd_data.dart';
import '../data/listings.dart';

// Matching Letterboxd's Name + Year rows to the films in the listings window, locally: no TMDB
// lookups. Conservative on purpose: a false "seen" hides a film the user wanted, which is worse
// than a missed match. See docs/letterboxd-linking.md section 4.

/// Letters with diacritics -> plain letters, for the ones that turn up in film titles.
const _folded = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae', 'ç': 'c', //
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', //
  'ð': 'd', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'þ': 'th', 'ß': 'ss', //
  'ā': 'a', 'ă': 'a', 'ą': 'a', 'ć': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd', 'ē': 'e', //
  'ė': 'e', 'ę': 'e', 'ě': 'e', 'ğ': 'g', 'ī': 'i', 'ı': 'i', 'ł': 'l', 'ń': 'n', //
  'ň': 'n', 'ō': 'o', 'ő': 'o', 'œ': 'oe', 'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's', //
  'ț': 't', 'ť': 't', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ź': 'z', 'ż': 'z', 'ž': 'z', //
};

final _punctuation = RegExp(r'[^a-z0-9\s]');
final _spaces = RegExp(r'\s+');

/// Lowercase, diacritics stripped, `&` -> `and`, punctuation dropped, whitespace collapsed, and a
/// leading "the " dropped: "The Girl with the Dragon Tattoo" and "Amélie" match their Letterboxd rows.
String normaliseTitle(String title) {
  final sb = StringBuffer();
  for (final r in title.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    sb.write(_folded[ch] ?? ch);
  }
  var s = sb.toString().replaceAll('&', ' and ').replaceAll(_punctuation, ' ').replaceAll(_spaces, ' ').trim();
  if (s.startsWith('the ')) s = s.substring(4);
  return s;
}

/// Which films in the listings window are on the user's watchlist, and which they have seen
/// (watched.csv or a logged diary item in the RSS feed). Listings film ids.
class FilmMatches {
  const FilmMatches({this.onWatchlist = const {}, this.seen = const {}});

  final Set<String> onWatchlist, seen;

  bool get isEmpty => onWatchlist.isEmpty && seen.isEmpty;
}

/// A film in the window, indexed for matching.
class _Indexed {
  _Indexed(this.film) : title = normaliseTitle(film.title), year = int.tryParse(film.year ?? '');
  final Film film;
  final String title;
  final int? year;
}

/// The listings film ids each Letterboxd row matches, by the rules in the spec:
///   1. same normalised title and same year
///   2. else same title, year within +-1 (festival vs release year)  [tmdb films only]
///   3. else same title, no year on either side, and the title unique in the window  [tmdb films only]
/// A film without a TMDB id (events, double bills, "+ Q&A") only matches by rule 1.
Set<String> matchEntries(Listings data, Iterable<LetterboxdEntry> entries) {
  final byTitle = <String, List<_Indexed>>{};
  for (final f in data.films.values) {
    if (f.title.isEmpty) continue;
    final ix = _Indexed(f);
    if (ix.title.isNotEmpty) byTitle.putIfAbsent(ix.title, () => []).add(ix);
  }
  final out = <String>{};
  for (final e in entries) {
    final same = byTitle[normaliseTitle(e.name)];
    if (same == null) continue;
    final exact = [
      for (final f in same)
        if (e.year != null && f.year == e.year) f,
    ];
    if (exact.isNotEmpty) {
      out.addAll(exact.map((f) => f.film.id));
      continue;
    }
    if (e.year != null) {
      out.addAll([
        for (final f in same)
          if (f.film.tmdb != null && f.year != null && (f.year! - e.year!).abs() <= 1) f.film.id,
      ]);
    } else if (same.length == 1 && same.single.year == null && same.single.film.tmdb != null) {
      out.add(same.single.film.id);
    }
  }
  return out;
}

/// Both sets at once, for one listings load.
FilmMatches matchFilms(Listings data, LetterboxdData lb) {
  final seen = matchEntries(data, lb.watched);
  if (lb.rssWatchedTmdb.isNotEmpty) {
    for (final f in data.films.values) {
      if (f.tmdb != null && lb.rssWatchedTmdb.containsKey(f.tmdb)) seen.add(f.id);
    }
  }
  return FilmMatches(onWatchlist: matchEntries(data, lb.watchlist), seen: seen);
}

/// A film with screenings still to come: the next one, and how widely it is on.
class FilmShowing {
  const FilmShowing({required this.film, required this.next, required this.cinemas, required this.screenings});
  final Film film;
  final tz.TZDateTime next;
  final int cinemas, screenings;
}

/// The [films] with a screening (not sold out) at or after [now], soonest first.
List<FilmShowing> upcomingShowings(Listings data, Set<String> films, tz.TZDateTime now) {
  if (films.isEmpty) return const [];
  final next = <String, tz.TZDateTime>{}, venues = <String, Set<String>>{}, count = <String, int>{};
  for (final p in data.performances) {
    if (p.soldOut) continue;
    final s = data.showings[p.showing];
    if (!films.contains(s.film) || !data.venues.containsKey(s.venue)) continue;
    final start = fromUnix(p.start);
    if (start.isBefore(now)) continue;
    if (next[s.film] == null || start.isBefore(next[s.film]!)) next[s.film] = start;
    venues.putIfAbsent(s.film, () => {}).add(s.venue);
    count[s.film] = (count[s.film] ?? 0) + 1;
  }
  return [
    for (final e in next.entries)
      FilmShowing(
        film: data.films[e.key]!,
        next: e.value,
        cinemas: venues[e.key]!.length,
        screenings: count[e.key]!,
      ),
  ]..sort((a, b) {
    final c = a.next.compareTo(b.next);
    return c != 0 ? c : a.film.title.compareTo(b.film.title);
  });
}

/// The shortest query [searchShowings] answers: one letter would match half the window.
const minSearchLength = 2;

/// Films in the window whose title matches [query], with a screening (not sold out) at or after
/// [now]. A title matches when every query word starts a word of it, in order and next to each
/// other (after [normaliseTitle] on both): "dragon tat" finds "The Girl with the Dragon Tattoo",
/// "art" does not find "Dune: Part Two". Best match first: the exact title, then titles starting
/// with the query, then the rest; soonest first within each.
List<FilmShowing> searchShowings(Listings data, String query, tz.TZDateTime now) {
  final q = normaliseTitle(query);
  if (q.length < minSearchLength) return const [];
  final rank = <String, int>{};
  for (final f in data.films.values) {
    final t = normaliseTitle(f.title);
    if (t == q) {
      rank[f.id] = 0;
    } else if (t.startsWith(q)) {
      rank[f.id] = 1;
    } else if (' $t'.contains(' $q')) {
      rank[f.id] = 2;
    }
  }
  if (rank.isEmpty) return const [];
  return upcomingShowings(data, rank.keys.toSet(), now)..sort((a, b) {
    final c = rank[a.film.id]!.compareTo(rank[b.film.id]!);
    if (c != 0) return c;
    final d = a.next.compareTo(b.next);
    return d != 0 ? d : a.film.title.compareTo(b.film.title);
  });
}

/// One screening of a film: when, the booking link, and the cinema's own title when it
/// differs from the film's (a format or event variant, e.g. "Dune (70mm)").
class FilmScreening {
  const FilmScreening({required this.start, this.bookingUrl, this.soldOut = false, this.label});
  final tz.TZDateTime start;
  final String? bookingUrl;
  final bool soldOut;
  final String? label;
}

/// A venue's upcoming screenings of one film, grouped by calendar day
/// (days ascending, times ascending within a day).
class VenueScreenings {
  const VenueScreenings({required this.venue, required this.days});
  final Venue venue;
  final List<({DateTime day, List<FilmScreening> screenings})> days;
}

/// Every screening of [filmId] at or after [now] at known venues, grouped venue -> day.
/// Sold-out screenings are included (shown disabled), unlike [upcomingShowings], which
/// only counts bookable ones. Venues come soonest screening first, then by name.
List<VenueScreenings> filmScreenings(Listings data, String filmId, tz.TZDateTime now) {
  final title = data.films[filmId]?.title;
  final byVenue = <String, List<FilmScreening>>{};
  for (final p in data.performances) {
    final s = data.showings[p.showing];
    if (s.film != filmId || !data.venues.containsKey(s.venue)) continue;
    final start = fromUnix(p.start);
    if (start.isBefore(now)) continue;
    byVenue.putIfAbsent(s.venue, () => []).add(FilmScreening(
      start: start,
      bookingUrl: p.bookingUrl,
      soldOut: p.soldOut,
      label: s.title != null && s.title != title ? s.title : null,
    ));
  }
  final out = <VenueScreenings>[];
  for (final e in byVenue.entries) {
    e.value.sort((a, b) => a.start.compareTo(b.start));
    final days = <({DateTime day, List<FilmScreening> screenings})>[];
    for (final sc in e.value) {
      final day = dayOf(sc.start);
      if (days.isEmpty || days.last.day != day) days.add((day: day, screenings: []));
      days.last.screenings.add(sc);
    }
    out.add(VenueScreenings(venue: data.venues[e.key]!, days: days));
  }
  return out..sort((a, b) {
    final c = a.days.first.screenings.first.start.compareTo(b.days.first.screenings.first.start);
    return c != 0 ? c : a.venue.name.compareTo(b.venue.name);
  });
}
