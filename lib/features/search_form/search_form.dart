import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/london_time.dart';
import '../../data/listings.dart';
import '../../data/place_services.dart';
import '../../data/settings_store.dart';
import '../../engine/journey_router.dart';
import '../../engine/search.dart';
import '../../state/app_state.dart';
import '../../ui/arrive_slider.dart';
import '../../ui/palette.dart';
import '../results/results_controller.dart';

/// The search just run, so "Change search" comes back to it. Only kept in memory: a new search
/// (from Home) clears it and starts again from the defaults in Settings.
class SearchDraft {
  const SearchDraft({
    required this.day,
    required this.free,
    required this.homeBy,
    required this.from,
    required this.end,
    required this.postcode,
    required this.endPostcode,
    required this.arrive,
    required this.hideSeen,
    required this.chains,
    required this.films,
    required this.genres,
  });

  final DateTime day;
  final TimeOfDay free, homeBy;
  final StartFrom from;
  final EndAt end;
  final String postcode, endPostcode;
  final int arrive;
  final bool hideSeen;
  final Set<String> chains, films, genres;
}

class SearchDraftNotifier extends Notifier<SearchDraft?> {
  @override
  SearchDraft? build() => null;

  void keep(SearchDraft draft) => state = draft;
  void clear() => state = null;
}

final searchDraftProvider = NotifierProvider<SearchDraftNotifier, SearchDraft?>(SearchDraftNotifier.new);

/// Solo search, laid out as a journey: where and when you're starting, where and when you're
/// ending up, joined by a line - then the filters below. Every field comes pre-filled (today, the
/// defaults from Settings, any cinema/film/genre), so the usual path is still: Solo -> Find films.
/// Nothing picked here is saved: the next new search starts from the defaults again.
class SearchForm extends ConsumerStatefulWidget {
  const SearchForm({super.key});

  @override
  ConsumerState<SearchForm> createState() => _SearchFormState();
}

class _SearchFormState extends ConsumerState<SearchForm> {
  late DateTime _day;
  late TimeOfDay _free;
  late TimeOfDay _homeBy;
  late StartFrom _from;
  late EndAt _end;
  late int _arrive;
  late bool _hideSeen;
  Set<String> _chains = {};
  late final TextEditingController _postcode;
  late final TextEditingController _endPostcode;
  final _postcodeFocus = FocusNode();
  final _endPostcodeFocus = FocusNode();
  Set<String> _films = {};
  Set<String> _genres = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    final draft = ref.read(searchDraftProvider);
    final days = _days();
    if (draft != null) {
      // Back from the results: the search just run.
      _day = days.contains(draft.day) ? draft.day : days.first;
      _free = _day == draft.day ? draft.free : _defaultFree(_day);
      _homeBy = draft.homeBy;
      _from = draft.from;
      _end = draft.end == EndAt.home && s.home == null ? EndAt.start : draft.end;
      _postcode = TextEditingController(text: draft.postcode);
      _endPostcode = TextEditingController(text: draft.endPostcode);
      _arrive = draft.arrive;
      _hideSeen = draft.hideSeen;
      _chains = {...draft.chains};
      _films = _day == draft.day ? {...draft.films} : {};
      _genres = {...draft.genres};
      return;
    }
    // A new search: the defaults from Settings, and any cinema, film and genre.
    _homeBy = TimeOfDay(hour: s.homeBy.hour, minute: s.homeBy.minute);
    _from = StartFrom.gps;
    _end = EndAt.start;
    _postcode = TextEditingController();
    _endPostcode = TextEditingController();
    _arrive = s.arriveMin;
    _hideSeen = s.hideSeen;
    _day = days.first;
    _free = _defaultFree(_day);
  }

  /// A default changed in Settings while this form was open: take the new value.
  void _onDefaultsChanged(Settings? before, Settings now) {
    if (before == null) return;
    setState(() {
      if (before.homeBy != now.homeBy) _homeBy = TimeOfDay(hour: now.homeBy.hour, minute: now.homeBy.minute);
      if (before.setOff != now.setOff || before.setOffNowToday != now.setOffNowToday) _free = _defaultFree(_day);
      if (before.arriveMin != now.arriveMin) _arrive = now.arriveMin;
      if (before.hideSeen != now.hideSeen) _hideSeen = now.hideSeen;
    });
  }

  @override
  void dispose() {
    _postcode.dispose();
    _endPostcode.dispose();
    _postcodeFocus.dispose();
    _endPostcodeFocus.dispose();
    super.dispose();
  }

  Listings get _listings => ref.read(listingsProvider).requireValue;

  /// Days the listings cover, from today on.
  List<DateTime> _days() => _listings.coveredDays(dayOf(londonNow()));

  /// The default set-off time from Settings. Today it is the next 5-minute mark instead when
  /// "set off now" is on, or when the default time has already gone by.
  TimeOfDay _defaultFree(DateTime day) {
    final s = ref.read(settingsProvider);
    final set = TimeOfDay(hour: s.setOff.hour, minute: s.setOff.minute);
    final now = londonNow();
    if (day != dayOf(now)) return set;
    final m = (now.hour * 60 + now.minute + 4) ~/ 5 * 5;
    if (!s.setOffNowToday && set.hour * 60 + set.minute >= m) return set;
    return m >= 24 * 60 ? const TimeOfDay(hour: 23, minute: 55) : TimeOfDay(hour: m ~/ 60, minute: m % 60);
  }

  String _t(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<LatLon> _start() async {
    switch (_from) {
      case StartFrom.gps:
        return ref.read(locationServiceProvider).current();
      case StartFrom.postcode:
        if (_postcode.text.trim().isEmpty) throw PlaceException('Type a postcode to start from');
        return ref.read(postcodeServiceProvider).locate(_postcode.text);
    }
  }

  Future<LatLon> _finish(Settings s, LatLon origin) async {
    switch (_end) {
      case EndAt.start:
        return origin;
      case EndAt.home:
        return s.home?.at ?? (throw PlaceException('Set your Home in Settings first'));
      case EndAt.postcode:
        if (_endPostcode.text.trim().isEmpty) throw PlaceException('Type a postcode to end up at');
        return ref.read(postcodeServiceProvider).locate(_endPostcode.text);
    }
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final s = ref.read(settingsProvider);
      final matches = ref.read(filmMatchesProvider);
      final origin = await _start();
      final finish = await _finish(s, origin);
      if (!nearLondon(origin)) {
        messenger.showSnackBar(const SnackBar(content: Text("That's a long way from London - results may be thin")));
      }
      final freeFrom = at(_day, _free.hour, _free.minute);
      final options = SearchOptions(
        home: finish,
        homeBy: later(_homeBy.hour, _homeBy.minute, freeFrom),
        arriveMin: _arrive,
        runtimeFrom: s.runtimeFrom,
        chains: _chains,
        films: _films,
        genres: _genres,
        excludeFilms: _hideSeen ? matches.seen : null,
        maxVenues: TflRouter.venueCapFor(ref.read(tflKeyProvider)),
      );
      ref
          .read(searchDraftProvider.notifier)
          .keep(
            SearchDraft(
              day: _day,
              free: _free,
              homeBy: _homeBy,
              from: _from,
              end: _end,
              postcode: _postcode.text.trim(),
              endPostcode: _endPostcode.text.trim(),
              arrive: _arrive,
              hideSeen: _hideSeen,
              chains: {..._chains},
              films: {..._films},
              genres: {..._genres},
            ),
          );
      ref.read(resultsProvider.notifier).start(_listings, [Person('You', origin, freeFrom)], options);
    } on PlaceException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't search: $e")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial, String help) => showTimePicker(
    context: context,
    initialTime: initial,
    helpText: help,
    builder: (context, child) =>
        MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
  );

  Future<void> _pickDay() async {
    final today = dayOf(londonNow());
    final day = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final d in _days())
              ListTile(
                title: Text(dayLabel(d, today)),
                trailing: d == _day ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, d),
              ),
          ],
        ),
      ),
    );
    if (day != null && day != _day) {
      setState(() {
        _day = day;
        _free = _defaultFree(day);
        _films = {};
      });
    }
  }

  Future<void> _pickChains() async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      builder: (context) => _ChainPicker(initial: _chains),
    );
    if (picked != null) setState(() => _chains = picked);
  }

  Future<void> _pickGenres() async {
    final genres = genresOn(_listings, _day, after: (hour: _free.hour, minute: _free.minute));
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _GenrePicker(genres: genres, initial: _genres),
    );
    if (picked != null) setState(() => _genres = picked);
  }

  Future<void> _pickFilms() async {
    final titles = filmsOn(_listings, _day, after: (hour: _free.hour, minute: _free.minute));
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FilmPicker(titles: titles, initial: _films),
    );
    if (picked != null) setState(() => _films = picked);
  }

  /// Picking "Postcode" reveals its field; put the cursor straight in it.
  void _choosePlace(VoidCallback set, {FocusNode? focus}) {
    setState(set);
    if (focus != null) WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider, _onDefaultsChanged);
    final settings = ref.watch(settingsProvider);
    final linked = ref.watch(letterboxdProvider.select((lb) => lb.value != null));
    final theme = Theme.of(context);
    final today = dayOf(londonNow());
    final backLabel = _end == EndAt.home ? 'Home by' : 'Back by';
    String summary(Set<String> xs, String none) => xs.isEmpty
        ? none
        : xs.length == 1
        ? xs.first
        : '${xs.length} picked';

    return Scaffold(
      // Find films stays pinned at the bottom: never more than one tap away.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            icon: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            label: Text(_busy ? 'Finding films...' : 'Find films', style: const TextStyle(fontSize: 18)),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'WhatsPlaying',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  TextSpan(
                    text: '  Solo',
                    style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // The journey: start dot ... line ... end dot.
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                child: Column(
                  children: [
                    _JourneyStop(
                      color: Palette.there,
                      title: 'Where and when are you starting?',
                      children: [
                        const _FieldLabel('Where'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Choice(
                              icon: Icons.my_location,
                              label: 'Where I am now',
                              selected: _from == StartFrom.gps,
                              onTap: () => _choosePlace(() => _from = StartFrom.gps),
                            ),
                            _Choice(
                              icon: Icons.place_outlined,
                              label: 'Postcode',
                              selected: _from == StartFrom.postcode,
                              onTap: () => _choosePlace(() => _from = StartFrom.postcode, focus: _postcodeFocus),
                            ),
                          ],
                        ),
                        if (_from == StartFrom.postcode)
                          _PostcodeField(
                            controller: _postcode,
                            focus: _postcodeFocus,
                            label: 'Start postcode',
                            onSubmitted: _submit,
                          ),
                        const _FieldLabel('When', top: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Pill(icon: Icons.today, label: dayLabel(_day, today), onTap: _pickDay),
                            _Pill(
                              icon: Icons.schedule,
                              label: 'from ${_t(_free)}',
                              onTap: () async {
                                final t = await _pickTime(_free, 'Free from');
                                if (t != null) setState(() => _free = t);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    _JourneyStop(
                      color: Palette.home,
                      title: 'Where and when are you ending up?',
                      last: true,
                      children: [
                        const _FieldLabel('Where'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Choice(
                              icon: Icons.replay,
                              label: 'Same as start',
                              selected: _end == EndAt.start,
                              onTap: () => _choosePlace(() => _end = EndAt.start),
                            ),
                            _Choice(
                              icon: Icons.home_outlined,
                              label: 'Home',
                              selected: _end == EndAt.home,
                              onTap: settings.home == null ? null : () => _choosePlace(() => _end = EndAt.home),
                            ),
                            _Choice(
                              icon: Icons.place_outlined,
                              label: 'Postcode',
                              selected: _end == EndAt.postcode,
                              onTap: () => _choosePlace(() => _end = EndAt.postcode, focus: _endPostcodeFocus),
                            ),
                          ],
                        ),
                        if (_end == EndAt.postcode)
                          _PostcodeField(
                            controller: _endPostcode,
                            focus: _endPostcodeFocus,
                            label: 'End postcode',
                            onSubmitted: _submit,
                          ),
                        if (settings.home == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Set Home in Settings to end up there.',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        _FieldLabel(backLabel, top: 16),
                        Wrap(
                          children: [
                            _Pill(
                              icon: Icons.bedtime_outlined,
                              label: _t(_homeBy),
                              onTap: () async {
                                final t = await _pickTime(_homeBy, backLabel);
                                if (t != null) setState(() => _homeBy = t);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // The rest, below the line.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Filters',
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
            ),
            _FilterRow(icon: Icons.theaters, label: 'Cinemas', value: summary(_chains, 'Any'), onTap: _pickChains),
            _FilterRow(
              icon: Icons.movie_filter_outlined,
              label: 'Films',
              value: summary(_films, 'Any'),
              onTap: _pickFilms,
            ),
            _FilterRow(
              icon: Icons.category_outlined,
              label: 'Genres',
              value: summary(_genres, 'Any'),
              onTap: _pickGenres,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                Icons.visibility_off_outlined,
                color: linked ? theme.colorScheme.primary : theme.disabledColor,
              ),
              title: const Text("Hide films I've seen"),
              subtitle: Text(
                linked ? 'From your Letterboxd watched list and diary' : 'Link Letterboxd in Settings to use this',
              ),
              value: linked && _hideSeen,
              onChanged: linked ? (on) => setState(() => _hideSeen = on) : null,
            ),
            ArriveSlider(value: _arrive, onChanged: (v) => setState(() => _arrive = v), padding: EdgeInsets.zero),
          ],
        ),
      ),
    );
  }
}

/// One stop on the journey: a coloured dot in the left rail, and a line down to the next stop.
class _JourneyStop extends StatelessWidget {
  const _JourneyStop({required this.color, required this.title, required this.children, this.last = false});

  final Color color;
  final String title;
  final List<Widget> children;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 3),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(color: color.withValues(alpha: 0.3), width: 4),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 3,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Palette.there, Palette.home],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ...children,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.top = 12});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 8),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

/// A place option: one of a few, so a chip.
class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    avatar: Icon(icon, size: 18),
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    onSelected: onTap == null ? null : (_) => onTap!(),
  );
}

/// A day or time: a value to pick, so a button that opens a picker.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    onPressed: onTap,
    icon: Icon(icon, size: 20),
    label: Text(label, style: Theme.of(context).textTheme.titleMedium),
    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
  );
}

class _PostcodeField extends StatelessWidget {
  const _PostcodeField({required this.controller, required this.focus, required this.label, required this.onSubmitted});

  final TextEditingController controller;
  final FocusNode focus;
  final String label;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      focusNode: focus,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'e.g. WC1E 6BT',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onSubmitted: (_) => onSubmitted(),
    ),
  );
}

/// A filter row: icon, name, current value, chevron.
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.icon, required this.label, required this.value, required this.onTap});

  final IconData icon;
  final String label, value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              value,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _ChainPicker extends StatefulWidget {
  const _ChainPicker({required this.initial});
  final Set<String> initial;

  @override
  State<_ChainPicker> createState() => _ChainPickerState();
}

class _ChainPickerState extends State<_ChainPicker> {
  late final _picked = {...widget.initial};

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cinemas', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('None picked = any cinema'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in [...chains, otherChain])
                FilterChip(
                  label: Text(c),
                  selected: _picked.contains(c),
                  onSelected: (on) => setState(() => on ? _picked.add(c) : _picked.remove(c)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(context, <String>{}), child: const Text('Any cinema')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(context, _picked), child: const Text('Done')),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Genres with a film showing that day; none picked = any. A film counts if it has any picked genre.
class _GenrePicker extends StatefulWidget {
  const _GenrePicker({required this.genres, required this.initial});
  final List<String> genres;
  final Set<String> initial;

  @override
  State<_GenrePicker> createState() => _GenrePickerState();
}

class _GenrePickerState extends State<_GenrePicker> {
  late final _picked = {...widget.initial};

  // Up to most of the screen tall; the chips scroll when there are more than fit, and the buttons
  // stay put below them.
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Genres', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              widget.genres.isEmpty
                  ? 'No genres are listed for the films showing then'
                  : 'None picked = any genre. Films without a listed genre are left out once one is picked.',
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in widget.genres)
                      FilterChip(
                        label: Text(g),
                        selected: _picked.contains(g),
                        onSelected: (on) => setState(() => on ? _picked.add(g) : _picked.remove(g)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context, <String>{}), child: const Text('Any genre')),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => Navigator.pop(context, _picked), child: const Text('Done')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _FilmPicker extends StatefulWidget {
  const _FilmPicker({required this.titles, required this.initial});
  final List<String> titles;
  final Set<String> initial;

  @override
  State<_FilmPicker> createState() => _FilmPickerState();
}

class _FilmPickerState extends State<_FilmPicker> {
  late final _picked = {...widget.initial};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final shown = widget.titles.where((t) => t.toLowerCase().contains(_query.toLowerCase())).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: false,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search ${widget.titles.length} films showing',
                border: const OutlineInputBorder(),
              ),
              onChanged: (q) => setState(() => _query = q),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: shown.length,
              itemBuilder: (context, i) => CheckboxListTile(
                dense: true,
                title: Text(shown[i]),
                value: _picked.contains(shown[i]),
                onChanged: (on) => setState(() => on! ? _picked.add(shown[i]) : _picked.remove(shown[i])),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context, <String>{}), child: const Text('Any film')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _picked),
                    child: Text(_picked.isEmpty ? 'Done' : 'Done (${_picked.length})'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
