import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'letterboxd_data.dart';

/// Where the imported Letterboxd data lives between runs. A watched list runs to thousands of rows,
/// too big for shared_preferences, so it is one JSON file in the app's private folder.
abstract class LetterboxdStore {
  Future<LetterboxdData?> read();
  Future<void> write(LetterboxdData data);

  /// Unlink: every trace of the Letterboxd data goes.
  Future<void> delete();
}

class FileLetterboxdStore implements LetterboxdStore {
  FileLetterboxdStore(this.dir);
  final Directory dir;

  File get _file => File('${dir.path}${Platform.pathSeparator}letterboxd.json');

  @override
  Future<LetterboxdData?> read() async {
    if (!await _file.exists()) return null;
    try {
      return LetterboxdData.fromJson(jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null; // unreadable = as good as unlinked
    }
  }

  @override
  Future<void> write(LetterboxdData data) async {
    await dir.create(recursive: true);
    final part = File('${_file.path}.part');
    await part.writeAsString(jsonEncode(data.toJson()), flush: true);
    await part.rename(_file.path);
  }

  @override
  Future<void> delete() async {
    if (await _file.exists()) await _file.delete();
  }
}

/// The web build's store: there are no files in a browser, so the JSON goes in shared_preferences
/// (the browser's localStorage). A few thousand watched films is a few hundred KB, well inside the
/// ~5 MB a site gets.
class PrefsLetterboxdStore implements LetterboxdStore {
  PrefsLetterboxdStore(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'letterboxd.json';

  @override
  Future<LetterboxdData?> read() async {
    final s = _prefs.getString(_key);
    if (s == null) return null;
    try {
      return LetterboxdData.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null; // unreadable = as good as unlinked
    }
  }

  @override
  Future<void> write(LetterboxdData data) async {
    await _prefs.setString(_key, jsonEncode(data.toJson()));
  }

  @override
  Future<void> delete() async {
    await _prefs.remove(_key);
  }
}

/// Nothing persisted: for tests, and the default before main() wires the real one up.
class MemoryLetterboxdStore implements LetterboxdStore {
  MemoryLetterboxdStore([this.data]);
  LetterboxdData? data;

  @override
  Future<LetterboxdData?> read() async => data;

  @override
  Future<void> write(LetterboxdData d) async => data = d;

  @override
  Future<void> delete() async => data = null;
}
