// The profile RSS feed: a review item and a plain watch item carry a TMDB id; a list item doesn't.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whats_playing/data/letterboxd/letterboxd_rss.dart';

void main() {
  final feed = File('test/fixtures/letterboxd_rss.xml').readAsStringSync();

  test('diary items give tmdb id -> watched date; list items are skipped; rewatches keep the latest', () {
    final seen = parseLetterboxdRss(feed);
    expect(seen, {
      812583: DateTime.utc(2026, 9, 24), // reviewed 24 Sep, and watched again 30 May: the later one
      1456349: DateTime.utc(2025, 12, 11),
    });
  });

  test('a Cloudflare page or other non-feed body is rejected', () {
    expect(() => parseLetterboxdRss('<html><body>Just a moment...</body></html>'), throwsFormatException);
    expect(() => parseLetterboxdRss('not xml at all <<'), throwsFormatException);
  });

  test('the feed URL uses the lower-cased username', () {
    expect(letterboxdRssUrl(' ExampleUser '), Uri.parse('https://letterboxd.com/exampleuser/rss/'));
  });

  test('fetch sends a plain User-Agent and throws on a non-200', () async {
    final asked = <http.Request>[];
    final ok = MockClient((r) async {
      asked.add(r);
      return http.Response.bytes(utf8.encode(feed), 200);
    });
    expect(await fetchLetterboxdRss('example', client: ok), hasLength(2));
    expect(asked.single.url.toString(), 'https://letterboxd.com/example/rss/');
    expect(asked.single.headers['User-Agent'], letterboxdRssUserAgent);

    final blocked = MockClient((r) async => http.Response('nope', 403));
    expect(() => fetchLetterboxdRss('example', client: blocked), throwsA(isA<http.ClientException>()));
  });
}
