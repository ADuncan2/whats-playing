import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../data/place_services.dart';
import '../../data/settings_store.dart';
import '../../data/tfl_key_check.dart';
import '../../engine/search.dart';
import '../../state/app_state.dart';
import '../../ui/arrive_slider.dart';
import '../../ui/links.dart';
import 'credits_screen.dart';
import 'letterboxd_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final listings = ref.watch(listingsProvider).value;
    final letterboxd = ref.watch(letterboxdProvider).value;
    final update = ref.read(settingsProvider.notifier).update;
    final theme = Theme.of(context);
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
    Widget subheader(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
    String hm(HourMinute t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          header('Places'),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Set home'),
            subtitle: Text(s.home?.label ?? 'Not set - searches will bring you back to where you started'),
            onTap: () => _editPlace(
              context,
              ref,
              'Home',
              s.home,
              (p) => update((s) => p == null ? s.copyWith(clearHome: true) : s.copyWith(home: p)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.work),
            title: const Text('Set work'),
            subtitle: Text(s.work?.label ?? 'Not set'),
            onTap: () => _editPlace(
              context,
              ref,
              'Work',
              s.work,
              (p) => update((s) => p == null ? s.copyWith(clearWork: true) : s.copyWith(work: p)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(letterboxd == null ? 'Link Letterboxd' : 'Letterboxd'),
            subtitle: Text(
              letterboxd == null
                  ? 'Import your watchlist and watched films from a Letterboxd export'
                  : '${letterboxd.username.isEmpty ? 'Linked' : letterboxd.username} · '
                        '${letterboxd.watchlist.length} on watchlist · ${letterboxd.watched.length} watched',
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LetterboxdScreen())),
          ),
          header('Defaults for search'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Every new search starts from these. Cinemas, films and genres always start as any. '
              'Changes made in a search are for that search only.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          subheader('Timing'),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Set off at'),
            subtitle: Text(
              s.setOffNowToday ? 'For later days. Today, it is now' : 'Or now, if that time has gone by today',
            ),
            trailing: Text(hm(s.setOff), style: theme.textTheme.titleMedium),
            onTap: () async {
              final t = await _pickTime(context, s.setOff, 'Set off at');
              if (t != null) update((s) => s.copyWith(setOff: t));
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bolt_outlined),
            title: const Text('Today, set off now'),
            subtitle: const Text('Off = the time above, when it is still to come'),
            value: s.setOffNowToday,
            onChanged: (on) => update((s) => s.copyWith(setOffNowToday: on)),
          ),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Back by'),
            subtitle: const Text('When you need to be home, or wherever you end up'),
            trailing: Text(hm(s.homeBy), style: theme.textTheme.titleMedium),
            onTap: () async {
              final t = await _pickTime(context, s.homeBy, 'Back by');
              if (t != null) update((s) => s.copyWith(homeBy: t));
            },
          ),
          subheader('At the cinema'),
          ArriveSlider(
            value: s.arriveMin,
            onChanged: (v) => update((s) => s.copyWith(arriveMin: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.timelapse),
            title: const Text("Use the cinema's film length"),
            subtitle: const Text("Cinemas' lengths can include ads; off = TMDB's film-only length"),
            value: s.runtimeFrom == RuntimeSource.cinema,
            onChanged: (on) => update((s) => s.copyWith(runtimeFrom: on ? RuntimeSource.cinema : RuntimeSource.tmdb)),
          ),
          subheader('Films'),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text("Hide films I've seen"),
            subtitle: Text(
              letterboxd == null
                  ? 'Takes effect once Letterboxd is linked'
                  : 'From your Letterboxd watched list and diary',
            ),
            value: s.hideSeen,
            onChanged: (on) => update((s) => s.copyWith(hideSeen: on)),
          ),
          header('Data'),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Refresh listings'),
            subtitle: Text(
              listings?.generatedAt == null
                  ? 'Rebuilt three times a day'
                  : 'Built ${DateFormat('EEE d MMM, HH:mm').format(listings!.generatedAt!.toLocal())} · '
                        '${listings.venues.length} cinemas · ${listings.performances.length} screenings',
            ),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(const SnackBar(content: Text('Refreshing listings...')));
              final error = await ref.read(listingsProvider.notifier).refresh();
              messenger.showSnackBar(SnackBar(content: Text(error ?? 'Listings up to date')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.directions_transit),
            title: const Text('TfL app key'),
            subtitle: Text(switch (ref.watch(tflKeySourceProvider)) {
              TflKeySource.user => 'Your key - every cinema checked, fast',
              TflKeySource.builtIn => 'Built-in key - every cinema checked, fast',
              TflKeySource.none => 'No key - nearest $anonymousVenueCap cinemas, slowly. Tap to add one (free)',
            }),
            onTap: () => _editTflKey(context, ref, s.tflKey),
          ),
          header('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Credits and licences'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreditsScreen())),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<HourMinute?> _pickTime(BuildContext context, HourMinute initial, String help) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      helpText: help,
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    return t == null ? null : (hour: t.hour, minute: t.minute);
  }

  Future<void> _editPlace(
    BuildContext context,
    WidgetRef ref,
    String name,
    SavedPlace? current,
    void Function(SavedPlace? place) save,
  ) async {
    final result = await showDialog<(SavedPlace?,)>(
      context: context,
      builder: (_) => _PlaceDialog(name: name, current: current),
    );
    if (result != null) save(result.$1);
  }

  Future<void> _editTflKey(BuildContext context, WidgetRef ref, String current) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<({String key, bool checked})>(
      context: context,
      builder: (_) => _TflKeyDialog(current: current),
    );
    if (result == null) return;
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(tflKey: result.key));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.key.isEmpty
              ? 'TfL key removed'
              : result.checked
              ? 'TfL key saved'
              : "TfL key saved, but TfL couldn't be reached to check it",
        ),
      ),
    );
  }
}

/// Paste a TfL app key, with the steps for getting one. Pops `(key: ..., checked: ...)` to save
/// (an empty key clears it; `checked` = TfL confirmed the key), nothing to cancel.
class _TflKeyDialog extends ConsumerStatefulWidget {
  const _TflKeyDialog({required this.current});
  final String current;

  @override
  ConsumerState<_TflKeyDialog> createState() => _TflKeyDialogState();
}

class _TflKeyDialogState extends ConsumerState<_TflKeyDialog> {
  late final _text = TextEditingController(text: widget.current);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _text.text.replaceAll(RegExp(r'\s'), '');
    if (key.isEmpty) {
      Navigator.pop(context, (key: '', checked: true));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final check = await ref.read(tflKeyCheckerProvider)(key);
    if (!mounted) return;
    switch (check) {
      case KeyCheck.rejected:
        setState(() {
          _busy = false;
          _error = 'TfL rejected this key - check it was copied in full';
        });
      case KeyCheck.accepted:
        Navigator.pop(context, (key: key, checked: true));
      case KeyCheck.unknown:
        Navigator.pop(context, (key: key, checked: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    Widget step(int n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 20, child: Text('$n.', style: body)),
          Expanded(child: Text(text, style: body)),
        ],
      ),
    );

    return AlertDialog(
      title: const Text('TfL app key'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A key is free and only changes speed: with one, every cinema is checked at once; '
              'without, just the nearest $anonymousVenueCap, about one a second.',
              style: body,
            ),
            const SizedBox(height: 12),
            step(1, 'Register at api-portal.tfl.gov.uk (free) and sign in.'),
            step(2, 'Open Products and subscribe to "500 requests a minute". Any app name will do.'),
            step(3, 'On your Profile, copy the primary key from that subscription.'),
            step(4, 'Paste it below.'),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => openUrl(context, tflPortalUrl),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open the TfL API portal'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: 'App key', errorText: _error, border: const OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.current.isNotEmpty)
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, (key: '', checked: true)),
            child: const Text('Clear'),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Postcode or current location. Pops `(place,)` to save, `(null,)` to clear, nothing to cancel.
class _PlaceDialog extends ConsumerStatefulWidget {
  const _PlaceDialog({required this.name, this.current});
  final String name;
  final SavedPlace? current;

  @override
  ConsumerState<_PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends ConsumerState<_PlaceDialog> {
  late final _text = TextEditingController(
    text: widget.current?.label == 'Current location' ? '' : widget.current?.label ?? '',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _use(Future<SavedPlace> Function() find) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final place = await find();
      if (mounted) Navigator.pop(context, (place,));
    } on PlaceException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Set ${widget.name.toLowerCase()}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _text,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: 'Postcode', errorText: _error, border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () =>
                    _use(() async => SavedPlace('Current location', await ref.read(locationServiceProvider).current())),
          icon: const Icon(Icons.my_location),
          label: const Text('Use where I am now'),
        ),
      ],
    ),
    actions: [
      if (widget.current != null)
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, (null,)), child: const Text('Clear')),
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: _busy
            ? null
            : () => _use(() async {
                final label = _text.text.trim().toUpperCase();
                return SavedPlace(label, await ref.read(postcodeServiceProvider).locate(label));
              }),
        child: _busy
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Save'),
      ),
    ],
  );
}
