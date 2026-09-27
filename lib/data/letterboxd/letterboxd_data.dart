/// What the app keeps from a Letterboxd export (and the RSS top-up). See docs/letterboxd-linking.md.
class LetterboxdEntry {
  const LetterboxdEntry({required this.name, this.year, this.uri});

  final String name;

  /// Release year as Letterboxd gives it; null for the few films without one.
  final int? year;
  final String? uri;

  Map<String, dynamic> toJson() => {'name': name, if (year != null) 'year': year, if (uri != null) 'uri': uri};

  factory LetterboxdEntry.fromJson(Map<String, dynamic> j) =>
      LetterboxdEntry(name: j['name'] as String, year: j['year'] as int?, uri: j['uri'] as String?);
}

class LetterboxdData {
  const LetterboxdData({
    required this.exportedAt,
    required this.importedAt,
    required this.username,
    required this.watchlist,
    required this.watched,
    this.rssWatchedTmdb = const {},
    this.rssFetchedAt,
  });

  /// From the export's filename, else the import time.
  final DateTime exportedAt;
  final DateTime importedAt;

  /// From profile.csv, the filename, or typed in; may be empty.
  final String username;
  final List<LetterboxdEntry> watchlist, watched;

  /// Films logged in the public diary feed (TMDB id -> watched date). Refreshed between exports;
  /// unioned with [watched] for "seen".
  final Map<int, DateTime> rssWatchedTmdb;
  final DateTime? rssFetchedAt;

  LetterboxdData copyWith({String? username, Map<int, DateTime>? rssWatchedTmdb, DateTime? rssFetchedAt}) =>
      LetterboxdData(
        exportedAt: exportedAt,
        importedAt: importedAt,
        username: username ?? this.username,
        watchlist: watchlist,
        watched: watched,
        rssWatchedTmdb: rssWatchedTmdb ?? this.rssWatchedTmdb,
        rssFetchedAt: rssFetchedAt ?? this.rssFetchedAt,
      );

  Map<String, dynamic> toJson() => {
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'importedAt': importedAt.toUtc().toIso8601String(),
    'username': username,
    'watchlist': [for (final e in watchlist) e.toJson()],
    'watched': [for (final e in watched) e.toJson()],
    'rssWatchedTmdb': {for (final e in rssWatchedTmdb.entries) '${e.key}': e.value.toUtc().toIso8601String()},
    'rssFetchedAt': ?rssFetchedAt?.toUtc().toIso8601String(),
  };

  factory LetterboxdData.fromJson(Map<String, dynamic> j) => LetterboxdData(
    exportedAt: DateTime.parse(j['exportedAt'] as String),
    importedAt: DateTime.parse(j['importedAt'] as String),
    username: j['username'] as String? ?? '',
    watchlist: [
      for (final e in (j['watchlist'] as List?) ?? const []) LetterboxdEntry.fromJson(e as Map<String, dynamic>),
    ],
    watched: [for (final e in (j['watched'] as List?) ?? const []) LetterboxdEntry.fromJson(e as Map<String, dynamic>)],
    rssWatchedTmdb: {
      for (final e in ((j['rssWatchedTmdb'] as Map?) ?? const {}).entries)
        ?int.tryParse('${e.key}'): DateTime.parse('${e.value}'),
    },
    rssFetchedAt: j['rssFetchedAt'] == null ? null : DateTime.parse(j['rssFetchedAt'] as String),
  );
}
