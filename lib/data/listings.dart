import '../core/constants.dart';
import '../core/geo.dart';

/// The slim listings file (schema 1) published by the london-film-data repo.
/// Films and venues are keyed by id; performances point at showings by array index.
class Listings {
  Listings({
    required this.schema,
    required this.generatedAt,
    this.expiresAt,
    required this.from,
    required this.days,
    required this.attribution,
    required this.venues,
    required this.films,
    required this.showings,
    required this.performances,
  });

  final int schema;
  final DateTime? generatedAt;
  final DateTime? expiresAt; // after this the file must not be used (TMDB content)
  final DateTime? from; // first day covered (a UTC midnight)
  final int days;
  final Map<String, String> attribution;
  final Map<String, Venue> venues;
  final Map<String, Film> films;
  final List<Showing> showings;
  final List<Performance> performances;

  /// The days the file covers, from `today` on (never empty: `today` alone if the file is stale).
  List<DateTime> coveredDays(DateTime today) {
    final first = from ?? today;
    final covered = [
      for (var i = 0; i < days; i++) first.add(Duration(days: i)),
    ].where((d) => !d.isBefore(today)).toList();
    return covered.isEmpty ? [today] : covered;
  }

  factory Listings.fromJson(Map<String, dynamic> j) {
    final from = j['from'] as String?;
    return Listings(
      schema: j['schema'] as int? ?? 0,
      generatedAt: DateTime.tryParse(j['generatedAt'] as String? ?? ''),
      expiresAt: DateTime.tryParse(j['expiresAt'] as String? ?? ''),
      from: from == null ? null : DateTime.parse('${from}T00:00:00Z'),
      days: j['days'] as int? ?? 7,
      attribution: {for (final e in ((j['attribution'] as Map?) ?? {}).entries) '${e.key}': '${e.value}'},
      venues: {
        for (final e in (j['venues'] as Map<String, dynamic>).entries)
          e.key: Venue.fromJson(e.key, e.value as Map<String, dynamic>),
      },
      films: {
        for (final e in (j['films'] as Map<String, dynamic>).entries)
          e.key: Film.fromJson(e.key, e.value as Map<String, dynamic>),
      },
      showings: [for (final s in j['showings'] as List) Showing.fromJson(s as Map<String, dynamic>)],
      performances: [for (final p in j['performances'] as List) Performance.fromJson(p as List)],
    );
  }
}

class Venue {
  Venue({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.chain,
    this.address,
    this.url,
  });

  final String id, name;
  final double lat, lon;
  final String? chain, address, url;

  LatLon get geo => (lat: lat, lon: lon);

  /// The big chains by name; everything else is one bucket. (The listings file has done the sorting.)
  String get chainOrOther => chain ?? otherChain;

  factory Venue.fromJson(String id, Map<String, dynamic> j) => Venue(
    id: id,
    name: j['name'] as String? ?? id,
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    chain: j['chain'] as String?,
    address: j['address'] as String?,
    url: j['url'] as String?,
  );
}

class Film {
  Film({
    required this.id,
    required this.title,
    this.runtime,
    this.year,
    this.certificate,
    this.tmdb,
    this.imdb,
    this.poster,
    this.summary,
    this.genres = const [],
  });

  final String id, title;
  final int? runtime; // TMDB's figure, film only
  final String? year, certificate, imdb, poster, summary;
  final int? tmdb;

  /// TMDB genre names, e.g. ['Drama', 'Thriller']. Empty when the film wasn't matched to TMDB.
  final List<String> genres;

  factory Film.fromJson(String id, Map<String, dynamic> j) => Film(
    id: id,
    title: j['title'] as String? ?? '',
    runtime: j['runtime'] as int?,
    year: j['year']?.toString(),
    certificate: j['certificate'] as String?,
    tmdb: j['tmdb'] as int?,
    imdb: j['imdb'] as String?,
    poster: j['poster'] as String?,
    summary: j['summary'] as String?,
    genres: [for (final g in (j['genres'] as List?) ?? const []) '$g'],
  );
}

/// A film at a venue.
class Showing {
  Showing({required this.film, required this.venue, this.title, this.runtime, this.url});

  final String film, venue;
  final String? title; // the cinema's own title when it differs, e.g. "BETA (35mm)"
  final int? runtime; // the cinema's figure (may include adverts)
  final String? url;

  factory Showing.fromJson(Map<String, dynamic> j) => Showing(
    film: j['film'] as String,
    venue: j['venue'] as String,
    title: j['title'] as String?,
    runtime: j['runtime'] as int?,
    url: j['url'] as String?,
  );
}

/// One screening: [showingIndex, startUnixSeconds, bookingUrl, soldOut].
class Performance {
  Performance(this.showing, this.start, this.bookingUrl, this.soldOut);

  final int showing, start;
  final String? bookingUrl;
  final bool soldOut;

  factory Performance.fromJson(List p) => Performance(p[0] as int, p[1] as int, p[2] as String?, (p[3] ?? 0) != 0);
}
