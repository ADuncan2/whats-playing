import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import 'listings.dart';

/// The slim listings file, cached on the phone. Port of `load_listings()`:
/// download to `.part` then rename (so a half download never replaces a good copy), a 3 hour
/// freshness window, the cached copy used if a download fails, and a schema check. A cached copy
/// past its `expiresAt` (or [listingsMaxKeep] old) is deleted rather than used, so TMDB content
/// never outlives its expiry on the device even if new listings stop being published.
///
/// [cacheDir] null = no folder to cache in (the web build, where dart:io files don't exist): the
/// last download is kept in memory for the life of the page instead, with the same freshness rule.
class ListingsRepository {
  ListingsRepository({required this.cacheDir, http.Client? client, this.url = listingsUrl})
    : _client = client ?? http.Client();

  final Directory? cacheDir;
  final String url;
  final http.Client _client;

  // Memory-only cache (cacheDir == null).
  String? _memBody;
  DateTime? _memAt;

  File get _file => File('${cacheDir!.path}${Platform.pathSeparator}listings.json');

  /// How old the cached copy is, or null when there isn't one.
  Future<Duration?> cacheAge() async {
    if (cacheDir == null) return _memAt == null ? null : DateTime.now().difference(_memAt!);
    return await _file.exists() ? DateTime.now().difference(await _file.lastModified()) : null;
  }

  Future<bool> get isStale async {
    final age = await cacheAge();
    return age == null || age > listingsMaxAge;
  }

  /// The cached copy, or null when there isn't a readable one.
  Future<Listings?> readCache() async {
    if (cacheDir == null) {
      if (_memBody == null) return null;
      final listings = await _parse(_memBody!);
      if (!_expired(listings, _memAt!)) return listings;
      _memBody = null;
      _memAt = null;
      return null;
    }
    if (!await _file.exists()) return null;
    try {
      final listings = await _parse(await _file.readAsString());
      if (!_expired(listings, await _file.lastModified())) return listings;
      await _file.delete();
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Past the file's own expiresAt or, without one, [listingsMaxKeep] after it was made ([saved] if
  /// the file doesn't say when).
  static bool _expired(Listings listings, DateTime saved) {
    final made = listings.generatedAt ?? saved;
    final expires = listings.expiresAt ?? made.add(listingsMaxKeep);
    return DateTime.now().isAfter(expires);
  }

  /// Fetch a fresh copy and swap it in. Throws if the download or the file is bad; the cache is untouched then.
  Future<Listings> download() async {
    final dir = cacheDir;
    await dir?.create(recursive: true);
    // No User-Agent in a browser: it can't be set there, and a custom header would force a CORS
    // preflight that GitHub Pages doesn't answer.
    final r = await _client
        .get(Uri.parse(url), headers: kIsWeb ? null : {'User-Agent': 'whats-playing-app'})
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw HttpException('Listings download failed (HTTP ${r.statusCode})');
    final body = utf8.decode(r.bodyBytes);
    final listings = await _parse(body); // check it before it replaces anything
    if (dir == null) {
      _memBody = body;
      _memAt = DateTime.now();
      return listings;
    }
    final part = File('${_file.path}.part');
    await part.writeAsString(body, flush: true);
    await part.rename(_file.path);
    return listings;
  }

  /// Cached copy if fresh; otherwise download, falling back to a stale cached copy if that fails.
  Future<Listings> load({bool refresh = false}) async {
    if (!refresh && !await isStale) {
      final cached = await readCache();
      if (cached != null) return cached;
    }
    try {
      return await download();
    } catch (_) {
      final cached = await readCache();
      if (cached == null) rethrow; // nothing cached to fall back on
      return cached;
    }
  }

  static Future<Listings> _parse(String body) async {
    // 1.7 MB of JSON: decode off the UI thread so the splash animation doesn't stutter.
    final listings = await compute(_decode, body);
    if (listings.schema != listingsSchema) {
      throw FormatException('listings file is schema ${listings.schema}, this app expects $listingsSchema');
    }
    return listings;
  }
}

Listings _decode(String body) => Listings.fromJson(jsonDecode(body) as Map<String, dynamic>);
