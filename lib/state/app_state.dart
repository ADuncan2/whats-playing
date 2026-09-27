import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../data/letterboxd/letterboxd_data.dart';
import '../data/letterboxd/letterboxd_import.dart';
import '../data/letterboxd/letterboxd_rss.dart';
import '../data/letterboxd/letterboxd_store.dart';
import '../data/listings.dart';
import '../data/listings_repository.dart';
import '../data/place_services.dart';
import '../data/settings_store.dart';
import '../data/tfl_key_check.dart';
import '../engine/film_match.dart';
import '../engine/journey_router.dart';

/// Overridden in main() once the platform bits (prefs, cache folder) are ready.
final settingsStoreProvider = Provider<SettingsStore>((ref) => throw UnimplementedError());
final listingsRepositoryProvider = Provider<ListingsRepository>((ref) => throw UnimplementedError());

final postcodeServiceProvider = Provider((ref) => PostcodeService());
final locationServiceProvider = Provider((ref) => LocationService());

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() => ref.read(settingsStoreProvider).load();

  void update(Settings Function(Settings s) change) {
    state = change(state);
    ref.read(settingsStoreProvider).save(state);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

/// Where the TfL key in use comes from.
enum TflKeySource { user, builtIn, none }

/// The TfL key in use: the one pasted into Settings, else the built-in one, else none (anonymous).
/// Both the request rate and how many cinemas a search checks follow this.
final tflKeyProvider = Provider<String>((ref) {
  final user = ref.watch(settingsProvider.select((s) => s.tflKey)).trim();
  return user.isNotEmpty ? user : tflAppKey;
});

final tflKeySourceProvider = Provider<TflKeySource>((ref) {
  if (ref.watch(settingsProvider.select((s) => s.tflKey)).trim().isNotEmpty) return TflKeySource.user;
  return tflAppKey.isEmpty ? TflKeySource.none : TflKeySource.builtIn;
});

/// One TfL router for the whole app, so its rate limiting spans searches. Rebuilt when the key changes.
final tflRouterProvider = Provider<JourneyRouter>((ref) {
  final router = TflRouter(key: ref.watch(tflKeyProvider));
  ref.onDispose(router.close);
  return router;
});

/// Checks a pasted key against TfL. Overridden in tests.
final tflKeyCheckerProvider = Provider<Future<KeyCheck> Function(String key)>((ref) => checkTflKey);

/// The listings. Start-up is as quick as the cache allows: a cached copy is shown at once, and if it
/// is over 3 hours old a fresh one is fetched in the background and swapped in.
class ListingsNotifier extends AsyncNotifier<Listings> {
  ListingsRepository get _repo => ref.read(listingsRepositoryProvider);

  @override
  Future<Listings> build() async {
    final cached = await _repo.readCache();
    if (cached == null) return _repo.load();
    if (await _repo.isStale) _refreshQuietly();
    return cached;
  }

  Future<void> _refreshQuietly() async {
    try {
      state = AsyncData(await _repo.download());
    } catch (_) {
      // keep showing the cached copy
    }
  }

  /// User-initiated refresh. Returns an error message, or null on success.
  Future<String?> refresh() async {
    try {
      state = AsyncData(await _repo.download());
      return null;
    } catch (e) {
      return "Couldn't refresh the listings: $e";
    }
  }
}

final listingsProvider = AsyncNotifierProvider<ListingsNotifier, Listings>(
  ListingsNotifier.new,
  retry: (_, _) => null, // show the error screen with its own retry button instead
);

/// Overridden in main() with a file store; in memory (nothing linked) until then and in tests.
final letterboxdStoreProvider = Provider<LetterboxdStore>((ref) => MemoryLetterboxdStore());

/// Fetches the public diary feed. Overridden in tests.
final letterboxdRssFetcherProvider = Provider<Future<Map<int, DateTime>> Function(String username)>(
  (ref) => fetchLetterboxdRss,
);

/// A picked file: its name (for the export date) and bytes.
typedef PickedFile = ({String name, Uint8List bytes});

/// How often the RSS feed is checked at most, and how old an export is before we nudge.
const letterboxdRssEvery = Duration(hours: 6);
const letterboxdExportStale = Duration(days: 30);

/// The linked Letterboxd data, or null when not linked. On start-up, if a username is set and the
/// feed hasn't been checked for 6 hours, it is refreshed quietly in the background.
class LetterboxdNotifier extends AsyncNotifier<LetterboxdData?> {
  LetterboxdStore get _store => ref.read(letterboxdStoreProvider);

  @override
  Future<LetterboxdData?> build() async {
    final data = await _store.read();
    if (data != null && _rssDue(data)) _refreshRssQuietly(data);
    return data;
  }

  static bool _rssDue(LetterboxdData d) =>
      d.username.trim().isNotEmpty &&
      (d.rssFetchedAt == null || DateTime.now().difference(d.rssFetchedAt!) > letterboxdRssEvery);

  Future<void> _refreshRssQuietly(LetterboxdData data) async {
    try {
      await refreshRss(data);
    } catch (_) {
      // keep the last good data
    }
  }

  /// Fetch the feed now and merge it in. Throws on failure (network, blocked, not a feed).
  Future<void> refreshRss([LetterboxdData? current]) async {
    final data = current ?? state.value;
    if (data == null || data.username.trim().isEmpty) return;
    final fresh = await ref.read(letterboxdRssFetcherProvider)(data.username);
    final latest = state.value ?? data;
    if (latest.username != data.username) return; // changed meanwhile
    // Only ever grows between exports: an item dropping off the 50-item feed is still watched.
    await _save(latest.copyWith(rssWatchedTmdb: {...latest.rssWatchedTmdb, ...fresh}, rssFetchedAt: DateTime.now()));
  }

  /// Import an export ZIP. A username typed earlier is kept if the export has none. Throws
  /// [LetterboxdImportException] when the file isn't an export.
  Future<LetterboxdData> importZip(PickedFile file) async {
    final imported = importLetterboxdZip(file.bytes, fileName: file.name);
    final previous = state.value;
    final data = imported.username.isEmpty && previous != null
        ? imported.copyWith(username: previous.username)
        : imported;
    await _save(data);
    if (_rssDue(data)) _refreshRssQuietly(data);
    return data;
  }

  Future<void> setUsername(String username) async {
    final data = state.value;
    if (data == null) return;
    final u = username.trim().replaceFirst(RegExp(r'^@'), '');
    if (u == data.username) return;
    // A new username means the old feed's films no longer apply.
    await _save(
      LetterboxdData(
        exportedAt: data.exportedAt,
        importedAt: data.importedAt,
        username: u,
        watchlist: data.watchlist,
        watched: data.watched,
      ),
    );
    if (u.isNotEmpty) _refreshRssQuietly(state.value!);
  }

  /// Unlink: delete everything stored.
  Future<void> unlink() async {
    await _store.delete();
    state = const AsyncData(null);
  }

  Future<void> _save(LetterboxdData data) async {
    await _store.write(data);
    state = AsyncData(data);
  }
}

final letterboxdProvider = AsyncNotifierProvider<LetterboxdNotifier, LetterboxdData?>(LetterboxdNotifier.new);

/// Which films in the current listings are on the watchlist / already seen. Empty until Letterboxd
/// is linked; recomputed when the listings or the Letterboxd data change.
final filmMatchesProvider = Provider<FilmMatches>((ref) {
  final listings = ref.watch(listingsProvider).value;
  final lb = ref.watch(letterboxdProvider).value;
  if (listings == null || lb == null) return const FilmMatches();
  return matchFilms(listings, lb);
});
