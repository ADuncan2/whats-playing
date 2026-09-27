import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/geo.dart';
import '../engine/search.dart';

/// Where a solo search sets off from.
enum StartFrom { gps, postcode }

/// Where a solo search has to get back to: where it started, the saved Home, or a postcode.
enum EndAt { start, home, postcode }

/// A time of day, as stored.
typedef HourMinute = ({int hour, int minute});

/// A saved place: what the user typed (or "Current location") and where it is.
class SavedPlace {
  const SavedPlace(this.label, this.at);
  final String label;
  final LatLon at;
}

/// Everything the app remembers between runs. The search form never writes here: every new search
/// starts from the defaults below (cinemas, films and genres always start as any).
class Settings {
  const Settings({
    this.home,
    this.work,
    this.sortBy = SortBy.leave,
    this.arriveMin = 0,
    this.runtimeFrom = RuntimeSource.cinema,
    this.homeBy = (hour: 23, minute: 30),
    this.setOff = (hour: 18, minute: 0),
    this.setOffNowToday = true,
    this.tflKey = '',
    this.hideSeen = false,
  });

  final SavedPlace? home, work;

  /// How the results were last sorted; new results are laid out this way too.
  final SortBy sortBy;

  /// Default for a new search: when to arrive, in minutes after the listed time (negative = before).
  final int arriveMin;
  final RuntimeSource runtimeFrom;

  /// Default for a new search: when you need to be back by.
  final HourMinute homeBy;

  /// Default for a new search: when you're free from. Today, [setOffNowToday] can make it "now"
  /// instead; a time that has already gone by today is "now" too.
  final HourMinute setOff;
  final bool setOffNowToday;

  /// A TfL app key the user pasted into Settings. Empty = use the built-in one (or none).
  final String tflKey;

  /// Default for a new search: "Hide films I've seen", leaving out films on the Letterboxd watched
  /// list. Only has an effect while Letterboxd is linked.
  final bool hideSeen;

  Settings copyWith({
    SavedPlace? home,
    SavedPlace? work,
    bool clearHome = false,
    bool clearWork = false,
    SortBy? sortBy,
    int? arriveMin,
    RuntimeSource? runtimeFrom,
    HourMinute? homeBy,
    HourMinute? setOff,
    bool? setOffNowToday,
    String? tflKey,
    bool? hideSeen,
  }) => Settings(
    home: clearHome ? null : home ?? this.home,
    work: clearWork ? null : work ?? this.work,
    sortBy: sortBy ?? this.sortBy,
    arriveMin: arriveMin ?? this.arriveMin,
    runtimeFrom: runtimeFrom ?? this.runtimeFrom,
    homeBy: homeBy ?? this.homeBy,
    setOff: setOff ?? this.setOff,
    setOffNowToday: setOffNowToday ?? this.setOffNowToday,
    tflKey: tflKey ?? this.tflKey,
    hideSeen: hideSeen ?? this.hideSeen,
  );
}

class SettingsStore {
  SettingsStore(this._prefs);
  final SharedPreferences _prefs;

  static Future<SettingsStore> open() async => SettingsStore(await SharedPreferences.getInstance());

  /// Left over from earlier versions (the form remembering the last search; "arrive for" and the
  /// ads minutes, now one arrival offset). Removed on the next save.
  static const _retired = ['startFrom', 'lastPostcode', 'endAt', 'lastEndPostcode', 'chains', 'arriveFor', 'adsMin'];

  Settings load() {
    final p = _prefs;
    T pick<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((v) => v.name == p.getString(key)).firstOrNull ?? fallback;
    SavedPlace? place(String key) {
      final label = p.getString('$key.label'), lat = p.getDouble('$key.lat'), lon = p.getDouble('$key.lon');
      return label == null || lat == null || lon == null ? null : SavedPlace(label, (lat: lat, lon: lon));
    }

    HourMinute time(String key, HourMinute fallback) {
      final hm = p.getString(key)?.split(':').map(int.tryParse).toList();
      return hm != null && hm.length == 2 && hm.every((x) => x != null) ? (hour: hm[0]!, minute: hm[1]!) : fallback;
    }

    const d = Settings();
    return Settings(
      home: place('home'),
      work: place('work'),
      sortBy: pick(SortBy.values, 'sortBy', d.sortBy),
      arriveMin: (p.getInt('arriveMin') ?? d.arriveMin).clamp(-arriveRangeMin, arriveRangeMin),
      runtimeFrom: pick(RuntimeSource.values, 'runtimeFrom', d.runtimeFrom),
      homeBy: time('homeBy', d.homeBy),
      setOff: time('setOff', d.setOff),
      setOffNowToday: p.getBool('setOffNowToday') ?? d.setOffNowToday,
      tflKey: p.getString('tflKey') ?? '',
      hideSeen: p.getBool('hideSeen') ?? d.hideSeen,
    );
  }

  Future<void> save(Settings s) async {
    final p = _prefs;
    Future<void> place(String key, SavedPlace? v) async {
      if (v == null) {
        for (final k in ['label', 'lat', 'lon']) {
          await p.remove('$key.$k');
        }
      } else {
        await p.setString('$key.label', v.label);
        await p.setDouble('$key.lat', v.at.lat);
        await p.setDouble('$key.lon', v.at.lon);
      }
    }

    await place('home', s.home);
    await place('work', s.work);
    await p.setString('sortBy', s.sortBy.name);
    await p.setInt('arriveMin', s.arriveMin);
    await p.setString('runtimeFrom', s.runtimeFrom.name);
    await p.setString('homeBy', '${s.homeBy.hour}:${s.homeBy.minute}');
    await p.setString('setOff', '${s.setOff.hour}:${s.setOff.minute}');
    await p.setBool('setOffNowToday', s.setOffNowToday);
    await p.setString('tflKey', s.tflKey);
    await p.setBool('hideSeen', s.hideSeen);
    for (final k in _retired) {
      await p.remove(k);
    }
  }
}
