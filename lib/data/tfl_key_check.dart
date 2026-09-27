import 'package:http/http.dart' as http;

import '../core/constants.dart';

/// What TfL said about a pasted app key. [unknown] = TfL couldn't be reached (offline, timeout).
enum KeyCheck { accepted, rejected, unknown }

/// One tiny request with [key], so a mis-pasted key is caught in Settings rather than failing every
/// cinema lookup during a search.
Future<KeyCheck> checkTflKey(String key, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final url = Uri.parse(tflModesUrl).replace(queryParameters: {'app_key': key});
    final r = await c.get(url).timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) return KeyCheck.accepted;
    if (r.statusCode == 401 || r.statusCode == 403) return KeyCheck.rejected;
    return KeyCheck.unknown;
  } catch (_) {
    return KeyCheck.unknown;
  } finally {
    if (client == null) c.close();
  }
}
