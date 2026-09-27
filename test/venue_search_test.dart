import 'package:flutter_test/flutter_test.dart';
import 'package:whats_playing/data/listings.dart';
import 'package:whats_playing/features/map/venue_search.dart';

Venue v(String name) => Venue(id: name, name: name, lat: 0, lon: 0);

void main() {
  final venues = [
    v('Curzon Soho'),
    v('Picturehouse Central'),
    v('Everyman Belsize Park'),
    v('Soho Theatre'),
    v('BFI Southbank'),
  ];

  List<String> names(String q) =>
      searchVenues(venues, q).map((v) => v.name).toList();

  test('empty query finds nothing', () {
    expect(names(''), isEmpty);
    expect(names('   '), isEmpty);
  });

  test('a partial word anywhere in the name matches, any case', () {
    expect(names('soh'), ['Soho Theatre', 'Curzon Soho']);
    expect(names('SIZE'), ['Everyman Belsize Park']);
  });

  test('every word has to appear, in any order', () {
    expect(names('belsize everyman'), ['Everyman Belsize Park']);
    expect(names('everyman central'), isEmpty);
  });

  test(
    'names starting with the query rank above word starts, above the rest',
    () {
      // "so": Soho Theatre starts with it; Curzon Soho has a word starting with it.
      expect(names('so'), ['Soho Theatre', 'BFI Southbank', 'Curzon Soho']);
      // "an": no name or word starts with it, so alphabetical.
      expect(names('an'), ['BFI Southbank', 'Everyman Belsize Park']);
      expect(names('ho'), [
        'Curzon Soho',
        'Picturehouse Central',
        'Soho Theatre',
      ]);
    },
  );
}
