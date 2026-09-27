import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'app.dart';
import 'core/constants.dart';
import 'data/letterboxd/letterboxd_store.dart';
import 'data/listings_repository.dart';
import 'data/settings_store.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  final store = await SettingsStore.open();
  // The web build (GitHub Pages, for iPhone) has no app folder: listings are cached in memory and
  // the Letterboxd data goes in the browser's storage instead of files. On a phone the listings
  // go in the cache folder (which "Clear cache" empties) and the Letterboxd data in the support folder.
  final support = isWeb ? null : await getApplicationSupportDirectory();
  final cache = isWeb ? null : await getApplicationCacheDirectory();
  if (support != null) {
    // Listings used to be kept in the support folder: remove that copy.
    final old = File('${support.path}${Platform.pathSeparator}listings.json');
    if (await old.exists()) await old.delete();
  }
  final LetterboxdStore letterboxd = support == null
      ? PrefsLetterboxdStore(await SharedPreferences.getInstance())
      : FileLetterboxdStore(support);
  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        listingsRepositoryProvider.overrideWithValue(ListingsRepository(cacheDir: cache)),
        letterboxdStoreProvider.overrideWithValue(letterboxd),
      ],
      child: const WhatsPlayingApp(),
    ),
  );
}
