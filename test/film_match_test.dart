// Letterboxd rows <-> films in the listings window, and "hide films I've seen" in plan().
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:whats_playing/core/london_time.dart';
import 'package:whats_playing/data/letterboxd/letterboxd_data.dart';
import 'package:whats_playing/data/listings.dart';
import 'package:whats_playing/engine/film_match.dart';
import 'package:whats_playing/engine/search.dart';

final day = DateTime.utc(2026, 9, 24);
int unix(String hhmm) => parseClock(hhmm, day).millisecondsSinceEpoch ~/ 1000;

Listings fixture() => Listings.fromJson({
  'schema': 1,
  'from': '2026-09-24',
  'days': 7,
  'venues': {
    'v1': {'name': 'One', 'lat': 51.52, 'lon': -0.13},
    'v2': {'name': 'Two', 'lat': 51.51, 'lon': -0.10},
  },
  'films': {
    'amelie': {'title': 'Amélie', 'year': '2001', 'tmdb': 194},
    'dragon': {'title': 'The Girl with the Dragon Tattoo', 'year': '2011', 'tmdb': 65754},
    'fast': {'title': 'Fast & Furious', 'year': '2009', 'tmdb': 13804},
    'susp77': {'title': 'Suspiria', 'year': '1977', 'tmdb': 11906},
    'susp18': {'title': 'Suspiria', 'year': '2018', 'tmdb': 401981},
    'fest': {'title': 'Festival Film', 'year': '2026', 'tmdb': 999},
    'event': {'title': 'Category H: SEYTAN + THE FLY'},
    'noyear': {'title': 'Frontline Folklore', 'tmdb': 1234},
    'noyear2': {'title': 'Untitled Doc'},
    'dune': {'title': 'Dune', 'year': '2021', 'tmdb': 438631},
  },
  'showings': [
    {'film': 'amelie', 'venue': 'v1', 'runtime': 120},
    {'film': 'dune', 'venue': 'v1', 'runtime': 150},
    {'film': 'dune', 'venue': 'v2', 'runtime': 150},
    {'film': 'susp18', 'venue': 'v2', 'runtime': 150},
  ],
  'performances': [
    [0, unix('19:00'), null, 0],
    [1, unix('19:30'), null, 0],
    [2, unix('20:00'), null, 0],
    [2, unix('21:00'), null, 1], // sold out
    [3, unix('18:00'), null, 0],
  ],
});

LetterboxdEntry e(String name, [int? year]) => LetterboxdEntry(name: name, year: year);

void main() {
  tz_data.initializeTimeZones();
  final data = fixture();

  group('normaliseTitle', () {
    test('lowercases, strips diacritics and punctuation, & -> and, drops a leading The', () {
      expect(normaliseTitle('Amélie'), 'amelie');
      expect(normaliseTitle('The Girl with the Dragon Tattoo'), 'girl with the dragon tattoo');
      expect(normaliseTitle('Fast & Furious'), 'fast and furious');
      expect(normaliseTitle('Fast and Furious'), 'fast and furious');
      expect(normaliseTitle('Mission: Impossible – Fallout'), 'mission impossible fallout');
      expect(normaliseTitle("Where'd You Go,  Bernadette"), 'where d you go bernadette');
      expect(normaliseTitle('WALL·E'), 'wall e');
      expect(normaliseTitle('Theatre of Blood'), 'theatre of blood'); // "the" only as a word
    });
  });

  group('matchEntries', () {
    test('exact title and year', () {
      expect(matchEntries(data, [e('Amelie', 2001)]), {'amelie'});
      expect(matchEntries(data, [e('Girl with the Dragon Tattoo', 2011)]), {'dragon'});
      expect(matchEntries(data, [e('Fast and Furious', 2009)]), {'fast'});
    });

    test('year within +-1 for festival vs release years, only when there is no exact hit', () {
      expect(matchEntries(data, [e('Festival Film', 2025)]), {'fest'});
      expect(matchEntries(data, [e('Festival Film', 2027)]), {'fest'});
      expect(matchEntries(data, [e('Festival Film', 2024)]), isEmpty);
    });

    test('same title, different years: only the right one', () {
      expect(matchEntries(data, [e('Suspiria', 1977)]), {'susp77'});
      expect(matchEntries(data, [e('Suspiria', 2018)]), {'susp18'});
      // 2019 is within a year of 2018 but not of 1977
      expect(matchEntries(data, [e('Suspiria', 2019)]), {'susp18'});
    });

    test('no year on either side needs a unique title and a TMDB id', () {
      expect(matchEntries(data, [e('Frontline Folklore')]), {'noyear'});
      expect(matchEntries(data, [e('Untitled Doc')]), isEmpty); // no tmdb: rule 1 only
      expect(matchEntries(data, [e('Dune')]), isEmpty); // film has a year, entry doesn't
    });

    test('an event title without a TMDB id only matches exactly', () {
      expect(matchEntries(data, [e('Category H: Seytan + The Fly')]), isEmpty);
      expect(matchEntries(data, [e('Category H: Seytan + The Fly', 2026)]), isEmpty);
      expect(matchEntries(data, [e('Seytan', 1974)]), isEmpty);
    });

    test('nothing in the window', () {
      expect(matchEntries(data, [e('Columbus', 2017), e('', 2000)]), isEmpty);
    });
  });

  test('matchFilms: seen is watched.csv plus the RSS tmdb ids', () {
    final lb = LetterboxdData(
      exportedAt: DateTime.utc(2026, 9, 25),
      importedAt: DateTime.utc(2026, 9, 25),
      username: 'x',
      watchlist: [e('Dune', 2021), e('Suspiria', 2018)],
      watched: [e('Amélie', 2001)],
      rssWatchedTmdb: {65754: DateTime.utc(2026, 9, 24), 1: DateTime.utc(2026, 9, 24)},
    );
    final m = matchFilms(data, lb);
    expect(m.onWatchlist, {'dune', 'susp18'});
    expect(m.seen, {'amelie', 'dragon'});
  });

  test('watchlistShowings: next screening from now, cinema and screening counts, sold-out ignored', () {
    final shows = watchlistShowings(data, {'dune', 'susp18', 'amelie'}, parseClock('19:45', day));
    expect(shows.map((s) => s.film.id), ['dune']); // Suspiria 18:00 and Amélie 19:00 have gone
    expect(shows.single.next, parseClock('20:00', day));
    expect(shows.single.cinemas, 1);
    expect(shows.single.screenings, 1);

    final all = watchlistShowings(data, {'dune', 'susp18'}, parseClock('12:00', day));
    expect(all.map((s) => s.film.id), ['susp18', 'dune']);
    expect(all.last.cinemas, 2);
    expect(all.last.screenings, 2);
  });

  test('plan(): excluded (seen) films drop out before any routing, with a funnel step', () {
    const origin = (lat: 51.515, lon: -0.12);
    final people = [Person('You', origin, parseClock('17:00', day))];
    final without = plan(data, people, const SearchOptions());
    expect(without.byVenue.values.expand((x) => x).map((c) => c.filmId).toSet(), {'amelie', 'dune', 'susp18'});

    final with_ = plan(data, people, const SearchOptions(excludeFilms: {'dune', 'amelie'}));
    expect(with_.byVenue.values.expand((x) => x).map((c) => c.filmId).toSet(), {'susp18'});
    expect(with_.order, ['v2']); // v1 only had seen films: no lookups planned for it
    expect(with_.funnel.map((f) => f.label), contains("Films you haven't seen (Letterboxd)"));

    final empty = plan(data, people, const SearchOptions(excludeFilms: {}));
    expect(empty.funnel.map((f) => f.label), isNot(contains("Films you haven't seen (Letterboxd)")));
  });
}
