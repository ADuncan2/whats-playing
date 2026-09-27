// The Letterboxd export ZIP -> LetterboxdData: real CSV quoting, missing optional files, the date
// and username from the filename, and a ZIP that isn't a Letterboxd export at all.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whats_playing/data/letterboxd/letterboxd_data.dart';
import 'package:whats_playing/data/letterboxd/letterboxd_import.dart';

Uint8List zip(Map<String, String> files) {
  final a = Archive();
  for (final e in files.entries) {
    a.addFile(ArchiveFile.string(e.key, e.value));
  }
  return ZipEncoder().encodeBytes(a);
}

const watchlist =
    'Date,Name,Year,Letterboxd URI\n'
    '2019-04-16,Columbus,2017,https://boxd.it/eCuA\n'
    '2019-10-22,"Where\'d You Go, Bernadette",2019,https://boxd.it/efuC\n'
    '2020-01-01,"The ""Quoted"" One, Part 2",2020,https://boxd.it/x1\n'
    '2026-03-03,Frontline Folklore,,https://boxd.it/10nCK\n';

const watched =
    'Date,Name,Year,Letterboxd URI\r\n'
    '2018-08-29,Amélie,2001,https://boxd.it/2aUc\r\n'
    '2018-08-29,WALL·E,2008,https://boxd.it/1VEo\r\n';

const profile =
    'Date Joined,Username,Given Name,Family Name,Email Address,Location,Website,Bio,Pronoun,Favorite Films\n'
    '2018-08-29,ExampleUser,Example,User,,London,,,,"https://boxd.it/27zg, https://boxd.it/20UQ"\n';

void main() {
  test('reads the watchlist and watched list, with commas and quotes in titles', () {
    final data = importLetterboxdZip(
      zip({
        'watchlist.csv': watchlist,
        'watched.csv': watched,
        'profile.csv': profile,
        'lists/2024.csv': 'Letterboxd list export v7\nDate,Name,Tags,URL,Description\n',
        'likes/films.csv': 'Date,Name,Year,Letterboxd URI\n2020-01-01,Not Counted,2000,https://boxd.it/n\n',
      }),
      fileName: 'letterboxd-exampleuser-2026-09-25-09-48-utc.zip',
      now: DateTime.utc(2026, 9, 26, 12),
    );
    expect(data.watchlist.map((e) => e.name), [
      'Columbus',
      "Where'd You Go, Bernadette",
      'The "Quoted" One, Part 2',
      'Frontline Folklore',
    ]);
    expect(data.watchlist.map((e) => e.year), [2017, 2019, 2020, null]);
    expect(data.watchlist[1].uri, 'https://boxd.it/efuC');
    expect(data.watched.map((e) => e.name), ['Amélie', 'WALL·E']);
    expect(data.username, 'ExampleUser'); // profile.csv beats the filename
    expect(data.exportedAt, DateTime.utc(2026, 9, 25, 9, 48));
    expect(data.importedAt, DateTime.utc(2026, 9, 26, 12));
    expect(data.rssWatchedTmdb, isEmpty);
  });

  test('tolerates a missing diary.csv and profile.csv; username and date fall back to the filename', () {
    final data = importLetterboxdZip(
      zip({'watchlist.csv': watchlist, 'watched.csv': watched}),
      fileName: '/storage/emulated/0/Download/letterboxd-someone-2026-01-02-03-04-utc.zip',
      now: DateTime.utc(2026, 2, 1),
    );
    expect(data.username, 'someone');
    expect(data.exportedAt, DateTime.utc(2026, 1, 2, 3, 4));
    expect(data.watched, hasLength(2));
  });

  test('an unrecognisable filename means the export date is the import time', () {
    final data = importLetterboxdZip(
      zip({'watched.csv': watched}),
      fileName: 'download (3).zip',
      now: DateTime.utc(2026, 2, 1),
    );
    expect(data.exportedAt, DateTime.utc(2026, 2, 1));
    expect(data.username, '');
    expect(data.watchlist, isEmpty);
  });

  test('rejects a ZIP that is not a Letterboxd export', () {
    expect(
      () => importLetterboxdZip(zip({'readme.txt': 'hello', 'lists/x.csv': 'Date,Name\n'})),
      throwsA(isA<LetterboxdImportException>().having((e) => e.message, 'message', contains('Letterboxd export'))),
    );
  });

  test('rejects bytes that are not a ZIP', () {
    expect(() => importLetterboxdZip(Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<LetterboxdImportException>()));
  });

  test('round-trips through JSON', () {
    final data = importLetterboxdZip(
      zip({'watchlist.csv': watchlist, 'watched.csv': watched}),
      fileName: 'letterboxd-a-2026-09-25-09-48-utc.zip',
      now: DateTime.utc(2026, 9, 26),
    ).copyWith(rssWatchedTmdb: {812583: DateTime.utc(2026, 9, 24)}, rssFetchedAt: DateTime.utc(2026, 9, 26, 1));
    final back = LetterboxdData.fromJson(data.toJson());
    expect(back.watchlist.map((e) => e.name), data.watchlist.map((e) => e.name));
    expect(back.watchlist.map((e) => e.year), data.watchlist.map((e) => e.year));
    expect(back.watched.map((e) => e.uri), data.watched.map((e) => e.uri));
    expect(back.exportedAt, data.exportedAt);
    expect(back.username, 'a');
    expect(back.rssWatchedTmdb, {812583: DateTime.utc(2026, 9, 24)});
    expect(back.rssFetchedAt, DateTime.utc(2026, 9, 26, 1));
  });
}
