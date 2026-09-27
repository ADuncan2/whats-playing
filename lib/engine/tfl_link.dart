import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/geo.dart';

/// A tfl.gov.uk journey-planner page, pre-filled. Coordinates drive the search; labels are just shown.
/// (Undocumented URL format, checked by hand in Sept 2026.)
String tflLink(LatLon a, LatLon b, tz.TZDateTime when, bool arriving, String labelA, String labelB) {
  final q = {
    'InputFrom': labelA,
    'FromId': fmtLatLon(a),
    'InputTo': labelB,
    'ToId': fmtLatLon(b),
    'Date': DateFormat('yyyyMMdd').format(when),
    'Time': DateFormat('HHmm').format(when),
    'TimeIs': arriving ? 'arriving' : 'departing',
    'JourneyPreference': 'leasttime',
  };
  final encoded = q.entries
      .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return 'https://tfl.gov.uk/plan-a-journey/results?$encoded';
}
