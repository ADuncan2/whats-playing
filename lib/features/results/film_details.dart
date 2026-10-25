import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../engine/search.dart';
import '../../ui/links.dart';
import '../../ui/palette.dart';
import 'results_controller.dart';

/// Posters are TMDB content: kept on disk for at most 30 days, 300 files.
final posterCache = CacheManager(Config('posters', stalePeriod: const Duration(days: 30), maxNrOfCacheObjects: 300));

/// The poster, or a plain titled panel for the ~15% of films without one.
class Poster extends StatelessWidget {
  const Poster({super.key, required this.poster, this.size = 'w500'});

  /// TMDB's poster path (`Film.poster`), e.g. '/abc.jpg'.
  final String? poster;

  /// TMDB image width, e.g. 'w154', 'w500'.
  final String size;

  @override
  Widget build(BuildContext context) {
    final url = poster == null ? null : '$posterBaseUrl$size$poster';
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: size == 'w154'
          ? Icon(Icons.movie, color: scheme.onPrimaryContainer)
          : Icon(Icons.movie_outlined, size: 96, color: scheme.onPrimaryContainer.withValues(alpha: 0.4)),
    );
    if (url == null) return placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: posterCache,
      fit: BoxFit.cover,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

/// The opened part of a results row: description and runtime, then every cinema showing the film
/// with each start time that works, its own Book link, and the journey links for that cinema.
class FilmDetails extends StatelessWidget {
  const FilmDetails({super.key, required this.card});
  final FilmCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = card.c;
    final meta = [
      if (c.year != null) c.year!,
      if (c.certificate != null) c.certificate!,
      '${duration(c.runtime)}${c.runtimeKnown ? '' : ' (assumed)'}',
      if (c.genres.isNotEmpty) c.genres.join(', '),
    ].join('  ·  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(meta, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (c.summary.isNotEmpty) ...[const SizedBox(height: 12), Text(c.summary, style: theme.textTheme.bodyMedium)],
        if (c.tmdbUrl != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Image.asset('assets/tmdb_logo.png', height: 10),
              const SizedBox(width: 6),
              Text('Film details from TMDB', style: theme.textTheme.bodySmall),
            ],
          ),
        ],
        for (final at in card.cinemas) ...[const SizedBox(height: 16), _CinemaSection(at: at)],
      ],
    );
  }
}

class _CinemaSection extends StatelessWidget {
  const _CinemaSection({required this.at});
  final AtCinema at;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = at.best;
    final info = best.c.infoUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(at.venue.name, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final r in at.rows) _ScreeningRow(r: r),
        const SizedBox(height: 4),
        Text(
          'Journey there: ${duration(best.timeOut)} by ${best.modeOut}'
          '${best.timeHome != null ? ' · home: ${duration(best.timeHome!)} by ${best.modeHome}' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => openUrl(context, best.linkOut),
              icon: const Icon(Icons.directions),
              label: const Text('Route there'),
            ),
            if (best.linkHome != null)
              TextButton.icon(
                onPressed: () => openUrl(context, best.linkHome),
                icon: const Icon(Icons.home),
                label: const Text('Route home'),
              ),
            if (info != null)
              TextButton.icon(
                onPressed: () => openUrl(context, info),
                icon: const Icon(Icons.info_outline),
                label: const Text('Cinema page'),
              ),
          ],
        ),
      ],
    );
  }
}

class _ScreeningRow extends StatelessWidget {
  const _ScreeningRow({required this.r});
  final ResultRow r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const tab = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Palette.film.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(hm(r.start), style: tab.copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leave ${hm(r.setOff)}',
                  style: tab.copyWith(color: Palette.there, fontWeight: FontWeight.w600),
                ),
                if (r.homeAt != null)
                  Text(
                    'Home ${hm(r.homeAt!)}',
                    style: tab.copyWith(color: Palette.home, fontWeight: FontWeight.w600),
                  ),
                Text('Film ends ${hm(r.c.ends)}', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: r.c.bookingUrl == null ? null : () => openUrl(context, r.c.bookingUrl),
            child: const Text('Book'),
          ),
        ],
      ),
    );
  }
}
