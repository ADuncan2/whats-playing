import 'dart:math' as math;

import 'constants.dart';

/// A point on the map. Records compare by value, so these work as map keys.
typedef LatLon = ({double lat, double lon});

/// Great-circle distance in km.
double km(LatLon a, LatLon b) {
  double rad(double d) => d * math.pi / 180;
  final x =
      math.pow(math.sin(rad(b.lat - a.lat) / 2), 2) +
      math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(rad(b.lon - a.lon) / 2), 2);
  return 2 * 6371 * math.asin(math.sqrt(x));
}

/// Rough door-to-door journey time from straight-line distance (a fit to a few TfL results).
/// Used to rank cinemas before any lookups, and as the instant estimate shown before TfL answers.
Duration guess(LatLon a, LatLon b) => Duration(minutes: (12 + 3.2 * km(a, b)).round());

/// Optimistic travel time: a lower bound used to rule screenings out without any lookups.
Duration bound(LatLon a, LatLon b) =>
    Duration(microseconds: (km(a, b) / boundSpeedKmh * Duration.microsecondsPerHour).round());

String fmtLatLon(LatLon p) => '${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)}';
