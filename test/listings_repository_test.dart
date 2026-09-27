import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whats_playing/data/listings_repository.dart';

/// A day old unless said otherwise: dates are relative to now, since old files expire.
String listingsJson({int schema = 1, DateTime? generatedAt, DateTime? expiresAt}) => jsonEncode({
  'schema': schema,
  'generatedAt': (generatedAt ?? DateTime.now().subtract(const Duration(days: 1))).toUtc().toIso8601String(),
  'expiresAt': ?expiresAt?.toUtc().toIso8601String(),
  'from': '2026-09-21',
  'days': 7,
  'venues': {
    'v': {'name': 'V', 'lat': 51.5, 'lon': -0.1, 'chain': null},
  },
  'films': {
    'f': {'title': 'F', 'runtime': 90},
  },
  'showings': [
    {'film': 'f', 'venue': 'v', 'title': null, 'runtime': null, 'url': null},
  ],
  'performances': [
    [0, 1789981200, 'https://book', 0],
  ],
});

void main() {
  late Directory dir;
  var calls = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('listings_test');
    calls = 0;
  });
  tearDown(() => dir.delete(recursive: true));

  MockClient serving(String body, {int status = 200}) => MockClient((_) async {
    calls++;
    return http.Response(body, status);
  });
  final failing = MockClient((_) async {
    calls++;
    throw const SocketException('offline');
  });
  File cached() => File('${dir.path}${Platform.pathSeparator}listings.json');

  test('downloads when nothing is cached, and leaves no .part file', () async {
    final l = await ListingsRepository(cacheDir: dir, client: serving(listingsJson())).load();
    expect(l.venues.keys, ['v']);
    expect(l.from, DateTime.utc(2026, 9, 21));
    expect(l.performances.single.bookingUrl, 'https://book');
    expect(cached().existsSync(), isTrue);
    expect(File('${cached().path}.part').existsSync(), isFalse);
  });

  test('a fresh cache is used without touching the network', () async {
    cached().writeAsStringSync(listingsJson());
    await ListingsRepository(cacheDir: dir, client: serving(listingsJson())).load();
    expect(calls, 0);
  });

  test('a stale cache is refreshed', () async {
    final newer = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
    cached().writeAsStringSync(listingsJson(generatedAt: DateTime.now().subtract(const Duration(days: 2))));
    cached().setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 4)));
    final l = await ListingsRepository(
      cacheDir: dir,
      client: serving(listingsJson(generatedAt: newer)),
    ).load();
    expect(calls, 1);
    expect(l.generatedAt, DateTime.parse(newer.toIso8601String()));
  });

  test('offline with a stale cache carries on with the cached copy', () async {
    cached().writeAsStringSync(listingsJson());
    cached().setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 10)));
    final l = await ListingsRepository(cacheDir: dir, client: failing).load();
    expect(calls, 1);
    expect(l.venues, contains('v'));
  });

  test('offline with nothing cached is an error', () async {
    expect(ListingsRepository(cacheDir: dir, client: failing).load(), throwsA(isA<SocketException>()));
  });

  test('a file with the wrong schema never replaces a good cached copy', () async {
    cached().writeAsStringSync(listingsJson());
    final repo = ListingsRepository(cacheDir: dir, client: serving(listingsJson(schema: 2)));
    expect(repo.download(), throwsA(isA<FormatException>()));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(jsonDecode(cached().readAsStringSync())['schema'], 1);
  });

  test('an HTTP error keeps the cached copy', () async {
    cached().writeAsStringSync(listingsJson());
    final l = await ListingsRepository(cacheDir: dir, client: serving('nope', status: 500)).load(refresh: true);
    expect(l.schema, 1);
  });

  test('a cached file past its expiresAt is deleted, not used', () async {
    cached().writeAsStringSync(listingsJson(expiresAt: DateTime.now().subtract(const Duration(minutes: 1))));
    expect(await ListingsRepository(cacheDir: dir, client: failing).readCache(), isNull);
    expect(cached().existsSync(), isFalse);
  });

  test('without expiresAt, a file made more than 14 days ago is deleted', () async {
    cached().writeAsStringSync(listingsJson(generatedAt: DateTime.now().subtract(const Duration(days: 15))));
    expect(await ListingsRepository(cacheDir: dir, client: failing).readCache(), isNull);
    expect(cached().existsSync(), isFalse);
  });

  test('a fresh cached file is returned and kept', () async {
    cached().writeAsStringSync(listingsJson(expiresAt: DateTime.now().add(const Duration(days: 7))));
    final l = await ListingsRepository(cacheDir: dir, client: failing).readCache();
    expect(l?.venues, contains('v'));
    expect(l?.expiresAt, isNotNull);
    expect(cached().existsSync(), isTrue);
  });

  test('offline with only an expired cache is an error', () async {
    cached().writeAsStringSync(listingsJson(generatedAt: DateTime.now().subtract(const Duration(days: 15))));
    cached().setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 10)));
    expect(ListingsRepository(cacheDir: dir, client: failing).load(), throwsA(isA<SocketException>()));
  });
}
