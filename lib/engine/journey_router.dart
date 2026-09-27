import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants.dart';
import '../core/geo.dart';
import '../core/london_time.dart';

/// One journey answer. `time` is the arrival (earliestArrival) or departure (latestDeparture);
/// all null when there is no journey. `error` is set when the lookup itself failed (network, HTTP),
/// as opposed to TfL finding no route.
class Leg {
  const Leg(this.time, this.mode, this.journey, {this.error});
  const Leg.none({this.error}) : time = null, mode = null, journey = null;

  final tz.TZDateTime? time;
  final String? mode;
  final Duration? journey;
  final String? error;

  bool get found => time != null;
}

/// Travel times. Counts calls and keeps errors for display.
abstract class JourneyRouter {
  int calls = 0;
  final List<String> errors = [];

  /// True when times are rough straight-line estimates rather than timetable lookups.
  bool get isEstimate;

  /// Leave `a` at `depart`: soonest I can be at `b`.
  Future<Leg> earliestArrival(LatLon a, LatLon b, tz.TZDateTime depart);

  /// Must be at `b` by `arriveBy`: latest I can leave `a`.
  Future<Leg> latestDeparture(LatLon a, LatLon b, tz.TZDateTime arriveBy);
}

/// Instant, offline: 12 min + 3.2 min/km.
class EstimateRouter extends JourneyRouter {
  @override
  bool get isEstimate => true;

  @override
  Future<Leg> earliestArrival(LatLon a, LatLon b, tz.TZDateTime depart) async {
    calls++;
    final g = guess(a, b);
    return Leg(depart.add(g), 'estimate', g);
  }

  @override
  Future<Leg> latestDeparture(LatLon a, LatLon b, tz.TZDateTime arriveBy) async {
    calls++;
    final g = guess(a, b);
    return Leg(arriveBy.subtract(g), 'estimate', g);
  }
}

typedef _Journey = ({tz.TZDateTime start, tz.TZDateTime arrive, String mode});

/// TfL Journey Planner. Anonymous access allows 50 requests a minute; a free key allows 500.
class TflRouter extends JourneyRouter {
  TflRouter({http.Client? client, String key = '', this.backoff = const Duration(seconds: 15)})
    : _client = client ?? http.Client(),
      key = key.trim(),
      gap = gapFor(key);

  /// How far apart requests are spaced: just under 50 a minute anonymously, well under 500 with a key.
  static Duration gapFor(String key) =>
      key.trim().isEmpty ? const Duration(milliseconds: 1300) : const Duration(milliseconds: 150);

  /// Solo mode: how many cinemas one search may check. Null = every candidate.
  static int? venueCapFor(String key) => key.trim().isEmpty ? anonymousVenueCap : null;

  final http.Client _client;
  final String key;
  final Duration gap, backoff;
  DateTime _next = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  bool get isEstimate => false;

  void close() => _client.close();

  /// Spaces requests `gap` apart. Single isolate, so no lock is needed.
  Future<void> _wait() async {
    final now = DateTime.now();
    final pause = _next.difference(now);
    _next = (_next.isAfter(now) ? _next : now).add(gap);
    if (pause > Duration.zero) await Future<void>.delayed(pause);
  }

  Future<(List<_Journey>, String?)> _tfl(LatLon a, LatLon b, tz.TZDateTime when, bool arriving) async {
    final q = {
      'date': _two(when.year, 4) + _two(when.month) + _two(when.day),
      'time': _two(when.hour) + _two(when.minute),
      'timeIs': arriving ? 'Arriving' : 'Departing',
      'journeyPreference': 'LeastTime',
      if (key.isNotEmpty) 'app_key': key,
    };
    final url = Uri.parse('$tflJourneyUrl/${fmtLatLon(a)}/to/${fmtLatLon(b)}').replace(queryParameters: q);
    for (var attempt = 0; attempt < 3; attempt++) {
      await _wait();
      calls++;
      try {
        final r = await _client.get(url).timeout(const Duration(seconds: 30));
        if (r.statusCode == 429) {
          // rate limited: back off and retry
          await Future<void>.delayed(backoff * (attempt + 1));
          continue;
        }
        if (r.statusCode == 404) return (<_Journey>[], null); // 404 = TfL found no journey
        if (r.statusCode == 401 || r.statusCode == 403) {
          const e = 'TfL rejected the app key - check it in Settings';
          errors.add(e);
          return (<_Journey>[], e);
        }
        if (r.statusCode != 200) {
          final e = 'TfL HTTP ${r.statusCode} for ${fmtLatLon(a)} -> ${fmtLatLon(b)}';
          errors.add(e);
          return (<_Journey>[], e);
        }
        final journeys = (jsonDecode(r.body) as Map<String, dynamic>)['journeys'] as List? ?? [];
        return (
          [
            for (final j in journeys.cast<Map<String, dynamic>>())
              (
                start: parseTflTime(j['startDateTime'] as String),
                arrive: parseTflTime(j['arrivalDateTime'] as String),
                mode: describe((j['legs'] as List).cast<Map<String, dynamic>>()),
              ),
          ],
          null,
        );
      } catch (e) {
        final msg = 'TfL ${e.runtimeType}: $e';
        errors.add(msg);
        return (<_Journey>[], msg);
      }
    }
    const msg = 'TfL rate limit (429) persisted after 3 tries - add a TfL key in Settings';
    errors.add(msg);
    return (<_Journey>[], msg);
  }

  @override
  Future<Leg> earliestArrival(LatLon a, LatLon b, tz.TZDateTime depart) async {
    final (js, error) = await _tfl(a, b, depart, false);
    final ok = js.where((j) => !j.start.isBefore(depart.subtract(const Duration(minutes: 1))));
    if (ok.isEmpty) return Leg.none(error: error);
    final best = ok.reduce((x, y) => y.arrive.isBefore(x.arrive) ? y : x);
    return Leg(best.arrive, best.mode, best.arrive.difference(best.start));
  }

  @override
  Future<Leg> latestDeparture(LatLon a, LatLon b, tz.TZDateTime arriveBy) async {
    final (js, error) = await _tfl(a, b, arriveBy, true);
    final ok = js.where((j) => !j.arrive.isAfter(arriveBy));
    if (ok.isEmpty) return Leg.none(error: error);
    final best = ok.reduce((x, y) => y.start.isAfter(x.start) ? y : x);
    return Leg(best.start, best.mode, best.arrive.difference(best.start));
  }
}

String _two(int n, [int width = 2]) => n.toString().padLeft(width, '0');

/// 'Tube + Bus' rather than 'walking + tube + walking + bus + walking'.
String describe(List<Map<String, dynamic>> legs) {
  final names = <String>{for (final l in legs) ((l['mode'] as Map)['name'] as String).replaceAll('-', ' ')}.toList();
  final ridden = names.where((n) => n != 'walking').toList();
  return (ridden.isEmpty ? names : ridden).map((n) => n[0].toUpperCase() + n.substring(1).toLowerCase()).join(' + ');
}
