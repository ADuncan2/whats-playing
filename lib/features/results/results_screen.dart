import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../core/london_time.dart';
import '../../engine/search.dart';
import '../../state/app_state.dart';
import '../../ui/palette.dart';
import 'film_details.dart';
import 'results_controller.dart';

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(resultsProvider);
    if (results == null) return const SizedBox.shrink();
    final person = results.plan.people.first;
    final o = results.plan.options;
    final title =
        '${dayLabel(dayOf(person.freeFrom), dayOf(londonNow()))} · free ${hm(person.freeFrom)}'
        '${o.homeBy != null ? ' · home ${hm(o.homeBy!)}' : ''}';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Change search',
          onPressed: () => ref.read(resultsProvider.notifier).clear(),
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: !results.filter.isEmpty,
              label: Text('${results.filter.count}'),
              child: const Icon(Icons.filter_list),
            ),
            tooltip: results.filter.isEmpty ? 'Filter' : 'Filter (${results.filter.count} on)',
            onPressed: results.isEmpty ? null : () => _openFilter(context, ref),
          ),
          PopupMenuButton<SortBy>(
            icon: const Icon(Icons.sort),
            tooltip: !results.finished
                ? 'Sort when the search finishes'
                : results.sorted
                ? 'Sorted by ${results.sortBy.label.toLowerCase()}'
                : 'Sort',
            enabled: results.finished && !results.isEmpty,
            onSelected: ref.read(resultsProvider.notifier).sort,
            itemBuilder: (context) => [
              for (final by in SortBy.values)
                CheckedPopupMenuItem(
                  value: by,
                  checked: results.sorted && by == results.sortBy,
                  child: ListTile(contentPadding: EdgeInsets.zero, title: Text(by.label), subtitle: Text(by.hint)),
                ),
            ],
          ),
        ],
        // Cinemas come in one by one; the bar fills as they are checked.
        bottom: results.finished
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: results.total == 0 ? null : results.checked / results.total),
              ),
      ),
      body: results.isEmpty
          ? (results.finished ? _Funnel(results: results) : _Searching(results: results))
          : results.nothingShown
          ? _NoMatch(results: results)
          : _List(
              key: ValueKey('list-${results.generation}'),
              results: results,
              watchlist: ref.watch(filmMatchesProvider.select((m) => m.onWatchlist)),
            ),
    );
  }

  Future<void> _openFilter(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<ResultsFilter>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FilterSheet(results: ref.read(resultsProvider)!),
    );
    if (picked != null) ref.read(resultsProvider.notifier).filter(picked);
  }
}

/// Everything found was filtered out: say so, rather than the "nothing fits" funnel.
class _NoMatch extends ConsumerWidget {
  const _NoMatch({required this.results});
  final ResultsState results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final n = results.cards.length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Nothing matches your filters', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '$n ${n == 1 ? 'film was' : 'films were'} found${results.finished ? '' : ' so far'}, '
          'but none at these cinemas, genres and films together.',
        ),
        const SizedBox(height: 12),
        _ActiveFilters(results: results),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: () => ref.read(resultsProvider.notifier).filter(const ResultsFilter()),
            child: const Text('Clear filters'),
          ),
        ),
      ],
    );
  }
}

/// The filters in force, one chip each, each removable on its own.
class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.results});
  final ResultsState results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = results.filter;
    if (f.isEmpty) return const SizedBox.shrink();
    void set(ResultsFilter next) => ref.read(resultsProvider.notifier).filter(next);
    final titles = {for (final (key, title) in results.filmChoices) key: title};
    return Wrap(
      spacing: 6,
      runSpacing: -6,
      children: [
        for (final c in f.chains)
          InputChip(
            label: Text(c),
            avatar: const Icon(Icons.theaters, size: 16),
            onDeleted: () => set(f.copyWith(chains: {...f.chains}..remove(c))),
          ),
        for (final g in f.genres)
          InputChip(
            label: Text(g),
            avatar: const Icon(Icons.category_outlined, size: 16),
            onDeleted: () => set(f.copyWith(genres: {...f.genres}..remove(g))),
          ),
        for (final key in f.films)
          InputChip(
            label: Text(titles[key] ?? key),
            avatar: const Icon(Icons.movie_filter_outlined, size: 16),
            onDeleted: () => set(f.copyWith(films: {...f.films}..remove(key))),
          ),
        if (f.count > 1) ActionChip(label: const Text('Clear all'), onPressed: () => set(const ResultsFilter())),
      ],
    );
  }
}

/// Pick which cinemas (by chain), genres and films to show, out of what this search found. Edits a
/// copy; the button applies it, and says how many films that leaves.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.results});
  final ResultsState results;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ResultsFilter _f = widget.results.filter;

  int get _left => widget.results.cards.where((c) => _f.apply(c, widget.results.sortBy) != null).length;

  @override
  Widget build(BuildContext context) {
    final r = widget.results;
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    Widget chips(List<String> all, Set<String> picked, void Function(Set<String>) onChange) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final x in all)
            FilterChip(
              label: Text(x),
              selected: picked.contains(x),
              onSelected: (on) => setState(() => onChange(on ? {...picked, x} : ({...picked}..remove(x)))),
            ),
        ],
      ),
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text('Filter results', style: theme.textTheme.titleLarge),
                ),
                if (r.chainChoices.length > 1) ...[
                  heading('Cinemas'),
                  chips(r.chainChoices, _f.chains, (xs) => _f = _f.copyWith(chains: xs)),
                ],
                if (r.genreChoices.isNotEmpty) ...[
                  heading('Genres'),
                  chips(r.genreChoices, _f.genres, (xs) => _f = _f.copyWith(genres: xs)),
                ],
                heading('Films'),
                for (final (key, title) in r.filmChoices)
                  CheckboxListTile(
                    dense: true,
                    title: Text(title),
                    value: _f.films.contains(key),
                    onChanged: (on) => setState(
                      () => _f = _f.copyWith(films: on! ? {..._f.films, key} : ({..._f.films}..remove(key))),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _f.isEmpty ? null : () => setState(() => _f = const ResultsFilter()),
                    child: const Text('Clear all'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _f),
                    child: Text(_f.isEmpty ? 'Show all' : 'Show $_left ${_left == 1 ? 'film' : 'films'}'),
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

/// One row per film. Rows only ever join the end while the search runs; a cinema that answers with a
/// film already listed swells that film's row instead.
class _List extends StatelessWidget {
  const _List({super.key, required this.results, this.watchlist = const {}});
  final ResultsState results;

  /// Listings film ids on the user's Letterboxd watchlist: those rows get a badge.
  final Set<String> watchlist;

  @override
  Widget build(BuildContext context) {
    final cards = results.shown, filtered = !results.filter.isEmpty;
    final screenings = cards.fold(0, (n, c) => n + c.screenings);
    final cinemas = {
      for (final c in cards)
        for (final a in c.cinemas) a.venue.id,
    }.length;
    final summary =
        '${cards.length}${filtered ? ' of ${results.cards.length}' : ''} '
        '${cards.length == 1 && !filtered ? 'film' : 'films'} · '
        '$screenings ${screenings == 1 ? 'screening' : 'screenings'} at '
        '$cinemas ${cinemas == 1 ? 'cinema' : 'cinemas'}'
        '${results.finished ? '' : ' so far'}';
    final small = Theme.of(context).textTheme.bodySmall;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: cards.length + 1 + (results.finished ? 0 : 1),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary, style: small),
                if (filtered) _ActiveFilters(results: results),
              ],
            ),
          );
        }
        if (i <= cards.length) {
          final card = cards[i - 1];
          return _FilmRow(key: ValueKey(card.key), card: card, onWatchlist: watchlist.contains(card.key));
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_stillToCheck(results), textAlign: TextAlign.center, style: small),
        );
      },
    );
  }
}

/// A film: its front screening, with a badge for how many other cinemas are showing it. Tap to open
/// every cinema and time.
class _FilmRow extends StatefulWidget {
  const _FilmRow({super.key, required this.card, this.onWatchlist = false});
  final FilmCard card;
  final bool onWatchlist;

  @override
  State<_FilmRow> createState() => _FilmRowState();
}

class _FilmRowState extends State<_FilmRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final card = widget.card, r = card.front, c = card.c;
    final theme = Theme.of(context);
    const tab = TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w700);
    final moreHere = card.here.rows.length - 1, others = card.otherCinemas;
    final line = [
      'Starts ${hm(c.start)}',
      if (moreHere > 0) '+$moreHere more ${moreHere == 1 ? 'time' : 'times'}',
      if (others > 0) 'also at $others other ${others == 1 ? 'cinema' : 'cinemas'}',
    ].join('  ·  ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Badge(
                    isLabelVisible: others > 0,
                    label: Text('+$others'),
                    backgroundColor: Palette.film,
                    textColor: Colors.black,
                    offset: const Offset(6, -6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 54,
                        height: 81,
                        child: Poster(c: c, size: 'w154'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (widget.onWatchlist)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, bottom: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bookmark, size: 14, color: theme.colorScheme.primary),
                                const SizedBox(width: 3),
                                Text(
                                  'On your watchlist',
                                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                                ),
                              ],
                            ),
                          ),
                        Text(card.here.venue.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(line, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Leave', style: theme.textTheme.labelSmall),
                      Text(hm(r.setOff), style: tab.copyWith(color: Palette.there, fontSize: 16)),
                      if (r.homeAt != null) ...[
                        Text('Home', style: theme.textTheme.labelSmall),
                        Text(hm(r.homeAt!), style: tab.copyWith(color: Palette.home, fontSize: 16)),
                      ],
                    ],
                  ),
                ],
              ),
              if (_open) ...[const Divider(height: 20), FilmDetails(card: card)],
            ],
          ),
        ),
      ),
    );
  }
}

/// Nothing found: show how many screenings survived each filter, so it's clear which one to loosen.
class _Funnel extends StatelessWidget {
  const _Funnel({required this.results});
  final ResultsState results;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = [
      for (final s in results.funnel) (s.label, s.performances, s.venues),
      (results.plan.options.home != null ? 'Reachable, and home in time' : 'You can get there in time', 0, 0),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Nothing fits', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Try a later home-by time, an earlier free-from time, fewer filters or another day. '
          'This is where the screenings dropped out:',
        ),
        const SizedBox(height: 16),
        for (final (label, n, venues) in steps)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            trailing: Text(
              venues == null ? '$n' : '$n at $venues ${venues == 1 ? 'cinema' : 'cinemas'}',
              style: theme.textTheme.titleMedium,
            ),
          ),
        if (results.failed > 0) ...[
          const SizedBox(height: 8),
          Text(
            "Couldn't check ${results.failed} of ${results.total} cinemas with TfL"
            '${results.liveErrors.isEmpty ? '' : ': ${results.liveErrors.first}'}',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Film lengths without a listed runtime are taken as $defaultRuntimeMin min.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

String _stillToCheck(ResultsState r) {
  final left = r.total - r.checked;
  return 'checking $left more ${left == 1 ? 'cinema' : 'cinemas'} with TfL';
}

/// Nothing back yet: the first cinemas are being checked.
class _Searching extends StatelessWidget {
  const _Searching({required this.results});
  final ResultsState results;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Checking live journey times', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '${results.checked} of ${results.total} cinemas checked, nearest first.\n'
              'Films appear as soon as one works.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
