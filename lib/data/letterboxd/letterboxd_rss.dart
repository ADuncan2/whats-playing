import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// The profile feed (`https://letterboxd.com/<user>/rss/`) is public and holds the last 50 activity
/// items. Diary entries carry a TMDB id; list items don't and are skipped.
const letterboxdRssUserAgent = 'WhatsPlaying/1.1';

Uri letterboxdRssUrl(String username) => Uri.https('letterboxd.com', '/${username.trim().toLowerCase()}/rss/');

/// TMDB id -> watched date for every diary/watch item in the feed. Throws [FormatException] when
/// the body isn't the feed (a Cloudflare page, say).
Map<int, DateTime> parseLetterboxdRss(String xml) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    throw FormatException('not an RSS feed: ${e.message}');
  }
  if (doc.findAllElements('channel').isEmpty) throw const FormatException('not an RSS feed');
  final out = <int, DateTime>{};
  for (final item in doc.findAllElements('item')) {
    final id = int.tryParse(item.getElement('tmdb:movieId')?.innerText.trim() ?? '');
    if (id == null) continue;
    final watched = _day(item.getElement('letterboxd:watchedDate')?.innerText);
    final pub = _rfc822(item.getElement('pubDate')?.innerText);
    final date = watched ?? pub ?? DateTime.now().toUtc();
    // Keep the latest date if the film is in the feed more than once (a rewatch).
    final old = out[id];
    if (old == null || date.isAfter(old)) out[id] = date;
  }
  return out;
}

/// Fetch and parse the feed. Any failure (network, non-200, not a feed) throws; the caller keeps
/// its last good data.
Future<Map<int, DateTime>> fetchLetterboxdRss(String username, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c
        .get(letterboxdRssUrl(username), headers: {'User-Agent': letterboxdRssUserAgent})
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}', r.request?.url);
    return parseLetterboxdRss(utf8.decode(r.bodyBytes, allowMalformed: true));
  } finally {
    if (client == null) c.close();
  }
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// "2026-09-24" -> that day, as a UTC midnight.
DateTime? _day(String? s) {
  final d = DateTime.tryParse(s?.trim() ?? '');
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}

/// "Fri, 25 Sep 2026 10:16:37 +1200" -> the date part, as a UTC day.
DateTime? _rfc822(String? s) {
  if (s == null) return null;
  final m = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})').firstMatch(s);
  if (m == null) return null;
  final month = _months[m.group(2)!.toLowerCase()];
  return month == null ? null : DateTime.utc(int.parse(m.group(3)!), month, int.parse(m.group(1)!));
}
