import 'package:intl/intl.dart';

final _hm = DateFormat('HH:mm');

/// "19:30", or "~19:30" when it is only an estimate.
String hm(DateTime t, {bool estimate = false}) => '${estimate ? '~' : ''}${_hm.format(t)}';

/// "1h 58m" / "45 min".
String duration(Duration d) =>
    d.inHours > 0 ? '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m' : '${d.inMinutes} min';

final _day = DateFormat('EEE d MMM');

/// "Today", "Tomorrow" or "Wed 23 Sep".
String dayLabel(DateTime day, DateTime today) {
  final diff = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  return diff == 0
      ? 'Today'
      : diff == 1
      ? 'Tomorrow'
      : _day.format(day);
}
