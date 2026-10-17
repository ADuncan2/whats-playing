import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/format.dart';
import '../../core/london_time.dart';
import '../../data/listings.dart';
import '../../engine/film_match.dart';
import '../../state/app_state.dart';
import '../../ui/links.dart';
import '../settings/letterboxd_screen.dart';

/// The main page from the wireframe: pick a mode. Solo is the app; Group is on its way. With
/// Letterboxd linked, the watchlist films playing this week sit above the modes.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.onSolo});

  /// Called when the user picks Solo.
  final VoidCallback onSolo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          children: [
            Text(
              'WhatsPlaying',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Which London screenings can you get to, watch, and still be back in time?',
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const _WatchlistStrip(),
            const SizedBox(height: 32),
            Text('How are you going?', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _ModeCard(
              icon: Icons.person,
              title: 'Solo',
              description:
                  'Just you. Say where you are and where you need to be afterwards, and see every film you can make tonight.',
              onTap: onSolo,
            ),
            const SizedBox(height: 12),
            const _ModeCard(
              icon: Icons.group,
              title: 'Group',
              description:
                  'Friends setting off from different places. Find the cinema and screening everyone can get to.',
              note: 'Still in development',
            ),
          ],
        ),
      ),
    );
  }
}

/// "On your watchlist this week": the Letterboxd watchlist films with a screening still to come,
/// soonest first. Greyed out, with a nudge to link, until Letterboxd is linked. Nudges when the
/// export is old.
class _WatchlistStrip extends ConsumerWidget {
  const _WatchlistStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lbState = ref.watch(letterboxdProvider);
    final lb = lbState.value;
    final listings = ref.watch(listingsProvider).value;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void openLetterboxd() =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LetterboxdScreen()));
    if (lb == null) {
      if (lbState.isLoading) return const SizedBox.shrink(); // still reading the stored data
      return Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bookmark_outline, size: 20, color: theme.disabledColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'On your watchlist this week',
                    style: theme.textTheme.titleMedium?.copyWith(color: theme.disabledColor),
                  ),
                ),
              ],
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: openLetterboxd,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Link Letterboxd in Settings to see which of your watchlist films are showing.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (listings == null) return const SizedBox.shrink();
    final now = londonNow();
    final today = dayOf(now);
    final shows = watchlistShowings(listings, ref.watch(filmMatchesProvider).onWatchlist, now);
    final age = DateTime.now().difference(lb.importedAt);
    final stale = age > letterboxdExportStale;

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bookmark, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('On your watchlist this week', style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          if (shows.isEmpty)
            Text(
              'None of your ${lb.watchlist.length} watchlist films are showing in the next ${listings.days} days.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: scheme.surfaceContainerLow,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, s) in shows.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    _WatchlistTile(
                      key: ValueKey('watchlist-${s.film.id}'),
                      show: s,
                      listings: listings,
                      now: now,
                      today: today,
                    ),
                  ],
                ],
              ),
            ),
          if (stale)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: openLetterboxd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.update, size: 18, color: scheme.tertiary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Refresh your Letterboxd watchlist: your export is ${age.inDays} days old',
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.tertiary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One watchlist film. The collapsed row summarises its week; tapping expands it in place to
/// every cinema showing it, times grouped by day, each time a chip that opens the booking page.
class _WatchlistTile extends StatefulWidget {
  const _WatchlistTile({super.key, required this.show, required this.listings, required this.now, required this.today});

  final WatchlistShowing show;
  final Listings listings;
  final tz.TZDateTime now;
  final DateTime today;

  @override
  State<_WatchlistTile> createState() => _WatchlistTileState();
}

class _WatchlistTileState extends State<_WatchlistTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = widget.show;
    return Column(
      children: [
        ListTile(
          title: Text(s.film.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${dayLabel(dayOf(s.next), widget.today)} ${hm(s.next)}'
            ' · ${s.cinemas} ${s.cinemas == 1 ? 'cinema' : 'cinemas'}'
            ' · ${s.screenings} ${s.screenings == 1 ? 'screening' : 'screenings'}',
          ),
          trailing: Icon(_open ? Icons.expand_less : Icons.expand_more, color: scheme.primary),
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open) ...[
          const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The whole card grows and the page scrolls: no cap, no inner scrolling.
                for (final (i, v) in filmScreenings(widget.listings, s.film.id, widget.now).indexed) ...[
                  if (i > 0) const SizedBox(height: 12),
                  Text(v.venue.name, style: theme.textTheme.titleSmall),
                  for (final d in v.days) ...[
                    const SizedBox(height: 4),
                    Text(dayLabel(d.day, widget.today),
                        style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final sc in d.screenings)
                          ActionChip(
                            label: Text(hm(sc.start) +
                                (sc.label != null ? ' ${sc.label}' : '') +
                                (sc.soldOut ? ' sold out' : '')),
                            onPressed: sc.soldOut || sc.bookingUrl == null
                                ? null
                                : () => openUrl(context, sc.bookingUrl),
                          ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One big tappable card per mode. Without [onTap] it is greyed out, with [note] saying why.
class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.icon, required this.title, required this.description, this.note, this.onTap});

  final IconData icon;
  final String title, description;
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    final textColor = enabled ? scheme.onSurface : scheme.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: enabled ? 1 : 0,
      color: enabled ? scheme.primaryContainer.withValues(alpha: 0.45) : scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: enabled ? scheme.primary : scheme.outlineVariant,
                foregroundColor: enabled ? scheme.onPrimary : scheme.onSurfaceVariant,
                child: Icon(icon, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: textColor),
                    ),
                    const SizedBox(height: 4),
                    Text(description, style: theme.textTheme.bodyMedium?.copyWith(color: textColor)),
                    if (note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            Icon(Icons.construction, size: 16, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                note!,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (enabled)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 14),
                  child: Icon(Icons.chevron_right, color: scheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
