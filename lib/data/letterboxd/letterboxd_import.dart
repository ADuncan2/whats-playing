import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';

import 'letterboxd_data.dart';

/// The file wasn't a Letterboxd export (or couldn't be read at all).
class LetterboxdImportException implements Exception {
  const LetterboxdImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The export's filename: `letterboxd-<username>-<yyyy>-<mm>-<dd>-<hh>-<mm>-utc.zip`.
final _fileName = RegExp(r'^letterboxd-(.+)-(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-utc\.zip$', caseSensitive: false);

/// Letterboxd's data export ZIP -> [LetterboxdData]. A pure function over the bytes: the CSVs at the
/// root are read, the sub-folders (lists/, likes/, deleted/ ...) ignored. Throws
/// [LetterboxdImportException] when it isn't a Letterboxd export.
LetterboxdData importLetterboxdZip(Uint8List bytes, {String? fileName, DateTime? now}) {
  now ??= DateTime.now();
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: false);
  } catch (_) {
    throw const LetterboxdImportException("That file couldn't be opened as a ZIP");
  }
  final files = {
    for (final f in archive.files)
      if (f.isFile && !f.name.contains('/') && !f.name.contains(r'\')) f.name.toLowerCase(): f,
  };
  String? text(String name) {
    final f = files[name];
    if (f == null) return null;
    final s = utf8.decode(f.content, allowMalformed: true);
    return s.startsWith('﻿') ? s.substring(1) : s;
  }

  final watchlist = text('watchlist.csv'), watched = text('watched.csv');
  if (watchlist == null && watched == null) {
    throw const LetterboxdImportException("That doesn't look like a Letterboxd export");
  }

  var username = '';
  DateTime? exportedAt;
  final m = fileName == null ? null : _fileName.firstMatch(fileName.split(RegExp(r'[\\/]')).last);
  if (m != null) {
    username = m.group(1)!;
    exportedAt = DateTime.utc(
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }
  final profile = text('profile.csv');
  if (profile != null) {
    final rows = _rows(profile);
    final u = rows.isEmpty ? null : rows.first['Username'];
    if (u is String && u.trim().isNotEmpty) username = u.trim();
  }

  return LetterboxdData(
    exportedAt: exportedAt ?? now,
    importedAt: now,
    username: username,
    watchlist: _films(watchlist),
    watched: _films(watched),
  );
}

/// Rows keyed by header name. Letterboxd titles contain commas and quotes, so this is a real CSV parse.
List<CsvRow> _rows(String csv) => [
  for (final r in const CsvDecoder(parseHeaders: true).convert(csv.replaceAll('\r\n', '\n')))
    if (r is CsvRow) r,
];

List<LetterboxdEntry> _films(String? csv) {
  if (csv == null) return const [];
  final out = <LetterboxdEntry>[];
  for (final r in _rows(csv)) {
    final name = '${r['Name'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    final uri = '${r['Letterboxd URI'] ?? ''}'.trim();
    out.add(
      LetterboxdEntry(name: name, year: int.tryParse('${r['Year'] ?? ''}'.trim()), uri: uri.isEmpty ? null : uri),
    );
  }
  return out;
}
