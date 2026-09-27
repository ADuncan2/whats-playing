import '../../data/listings.dart';

/// The cinemas whose names match [query], best first. Every word of the query has to appear
/// somewhere in the name (any case, any order), so "belsize everyman" finds Everyman Belsize Park
/// and "soho" finds both Curzon Soho and Picturehouse Soho. Names that start with the query come
/// first, then names with a word that does, then everything else, alphabetically within each.
List<Venue> searchVenues(Iterable<Venue> venues, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final words = q.split(RegExp(r'\s+'));
  final hits = <(int, Venue)>[];
  for (final v in venues) {
    final name = v.name.toLowerCase();
    if (!words.every(name.contains)) continue;
    final rank = name.startsWith(q)
        ? 0
        : name.split(RegExp(r'[^a-z0-9]+')).any((w) => w.startsWith(q))
        ? 1
        : 2;
    hits.add((rank, v));
  }
  hits.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    return byRank != 0
        ? byRank
        : a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
  });
  return [for (final h in hits) h.$2];
}
