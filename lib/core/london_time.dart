import 'package:timezone/timezone.dart' as tz;

/// Every time in the app is London wall-clock time. Call `tz_data.initializeTimeZones()` first.
tz.Location get london => tz.getLocation('Europe/London');

tz.TZDateTime fromUnix(int seconds) => tz.TZDateTime.fromMillisecondsSinceEpoch(london, seconds * 1000);

tz.TZDateTime londonNow() => tz.TZDateTime.now(london);

/// A calendar day, held as a UTC midnight so it has no zone of its own.
DateTime dayOf(tz.TZDateTime t) => DateTime.utc(t.year, t.month, t.day);

tz.TZDateTime at(DateTime day, int hour, int minute) =>
    tz.TZDateTime(london, day.year, day.month, day.day, hour, minute);

/// "HH:MM" on `day`.
tz.TZDateTime parseClock(String text, DateTime day) {
  final parts = text.split(':').map(int.parse).toList();
  return at(day, parts[0], parts[1]);
}

/// The first time strictly after `after` with this clock time: "home by 00:30" means tomorrow.
tz.TZDateTime later(int hour, int minute, tz.TZDateTime after) {
  final t = at(dayOf(after), hour, minute);
  return t.isAfter(after) ? t : at(dayOf(after).add(const Duration(days: 1)), hour, minute);
}

/// A TfL timestamp such as "2026-09-24T19:05:00" (London wall time, no offset).
tz.TZDateTime parseTflTime(String s) {
  final d = DateTime.parse(s.substring(0, 19));
  return tz.TZDateTime(london, d.year, d.month, d.day, d.hour, d.minute, d.second);
}

bool notAfter(DateTime a, DateTime b) => !a.isAfter(b);

T latest<T extends DateTime>(T a, T b) => a.isAfter(b) ? a : b;
