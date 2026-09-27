import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../core/geo.dart';

/// A problem the user can act on; the message is shown as-is.
class PlaceException implements Exception {
  PlaceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 'lat,lon' or a UK postcode -> coordinates. Postcodes use postcodes.io (free, no key).
class PostcodeService {
  PostcodeService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<LatLon> locate(String text) async {
    text = text.trim();
    final parts = text.split(',');
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0].trim()), lon = double.tryParse(parts[1].trim());
      if (lat != null && lon != null) return (lat: lat, lon: lon);
    }
    final http.Response r;
    try {
      r = await _client.get(Uri.parse('$postcodeUrl${Uri.encodeComponent(text)}')).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw PlaceException("Couldn't reach the postcode lookup - check your connection");
    }
    if (r.statusCode != 200) throw PlaceException("'$text' is not a postcode I can find");
    final result = (jsonDecode(r.body) as Map<String, dynamic>)['result'] as Map<String, dynamic>;
    return (lat: (result['latitude'] as num).toDouble(), lon: (result['longitude'] as num).toDouble());
  }
}

/// The phone's current position, with the permission dance done politely.
class LocationService {
  Future<LatLon> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw PlaceException('Location is switched off - turn it on, or pick Home / a postcode');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw PlaceException('No location permission - pick Home / a postcode instead');
    }
    // Not supported in a browser (the web build throws), so skip straight to a fresh fix there.
    final last = isWeb ? null : await Geolocator.getLastKnownPosition();
    // A fix from the last few minutes is plenty for choosing cinemas, and instant.
    if (last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 5)) {
      return (lat: last.latitude, lon: last.longitude);
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
      ).timeout(const Duration(seconds: 20)); // belt and braces: some devices ignore timeLimit
      return (lat: p.latitude, lon: p.longitude);
    } catch (_) {
      throw PlaceException("Couldn't get a GPS fix - try again, or pick Home / a postcode");
    }
  }
}

/// Rough check that a point is somewhere near London, where the listings are.
bool nearLondon(LatLon p) => km(p, (lat: 51.5074, lon: -0.1278)) < 60;
