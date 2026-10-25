import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/london_time.dart';
import '../../data/listings.dart';
import '../../data/place_services.dart';
import '../../state/app_state.dart';
import '../../ui/links.dart';
import '../../ui/palette.dart';
import '../results/film_details.dart';
import '../results/results_controller.dart';
import 'venue_search.dart';

const _centralLondon = LatLng(51.5074, -0.1278);

LatLng _ll(LatLon p) => LatLng(p.lat, p.lon);

/// Your location, every cinema, and what's on at each. Cinemas with results in the current search
/// are highlighted.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, required this.active});

  /// Whether the tab is showing (the map is built lazily the first time it is).
  final bool active;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();
  final _search = SearchController();
  LatLon? _me;
  bool _built = false, _locating = false;

  Future<void> _locate() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    try {
      final me = await ref.read(locationServiceProvider).current();
      setState(() => _me = me);
      _map.move(_ll(me), 14);
    } on PlaceException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // The bar's clear button comes and goes with the text.
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Jump to a cinema picked from the search bar and open its listings.
  void _goTo(Venue v) {
    _search.closeView(v.name);
    FocusManager.instance.primaryFocus?.unfocus();
    _map.move(_ll(v.geo), 15);
    _showVenue(v);
  }

  @override
  Widget build(BuildContext context) {
    _built |= widget.active;
    if (!_built) return const SizedBox.shrink();

    final listings = ref.watch(listingsProvider).requireValue;
    final results = ref.watch(resultsProvider);
    // Films you can make at each cinema.
    final counts = <String, int>{};
    for (final c in results?.cards ?? const <FilmCard>[]) {
      for (final a in c.cinemas) {
        counts[a.venue.id] = (counts[a.venue.id] ?? 0) + 1;
      }
    }
    final origin = results?.plan.people.first.origin;
    final me = _me ?? origin;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: me == null ? _centralLondon : _ll(me),
              initialZoom: me == null ? 12 : 13,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'uk.aduncan.whats_playing',
              ),
              MarkerLayer(
                markers: [
                  // Plain cinemas first, so the highlighted ones draw on top.
                  for (final v in listings.venues.values.where((v) => !counts.containsKey(v.id)))
                    Marker(
                      point: _ll(v.geo),
                      width: 28,
                      height: 28,
                      child: _Pin(color: Palette.pin, onTap: () => _showVenue(v)),
                    ),
                  for (final v in listings.venues.values.where((v) => counts.containsKey(v.id)))
                    Marker(
                      point: _ll(v.geo),
                      width: 40,
                      height: 40,
                      child: _Pin(color: scheme.primary, count: counts[v.id], onTap: () => _showVenue(v)),
                    ),
                  if (me != null)
                    Marker(
                      point: _ll(me),
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Palette.there,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                        ),
                      ),
                    ),
                ],
              ),
              SimpleAttributionWidget(
                source: const Text('OpenStreetMap contributors'),
                onTap: () => openUrl(context, 'https://www.openstreetmap.org/copyright'),
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SearchAnchor.bar(
                searchController: _search,
                barHintText: 'Find a cinema',
                barLeading: const Icon(Icons.search),
                barTrailing: [
                  if (_search.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear',
                      onPressed: () => setState(_search.clear),
                    ),
                ],
                viewHintText: 'Find a cinema',
                suggestionsBuilder: (context, controller) {
                  final hits = searchVenues(listings.venues.values, controller.text);
                  if (controller.text.trim().isNotEmpty && hits.isEmpty) {
                    return const [ListTile(title: Text('No cinema by that name.'))];
                  }
                  return [
                    for (final v in hits)
                      ListTile(
                        leading: Icon(
                          Icons.location_on,
                          color: counts.containsKey(v.id) ? scheme.primary : Palette.pin,
                        ),
                        title: Text(v.name),
                        subtitle: v.address == null
                            ? null
                            : Text(v.address!, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _goTo(v),
                      ),
                  ];
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _locating ? null : _locate,
        tooltip: 'Show my location',
        child: _locating
            ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.my_location),
      ),
    );
  }

  void _showVenue(Venue v) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _VenueSheet(venue: v),
  );
}

class _Pin extends StatelessWidget {
  const _Pin({required this.color, required this.onTap, this.count});
  final Color color;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        _OutlinedIcon(Icons.location_on, color: color, size: count == null ? 28 : 40),
        if (count != null)
          Positioned(
            top: 0,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Palette.film, borderRadius: BorderRadius.circular(10)),
              child: Text(
                '$count',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black),
              ),
            ),
          ),
      ],
    ),
  );
}

/// An icon with a black outline, so a pin stands out on any part of the map. The glyph is drawn
/// twice: stroked in black, then filled on top, which leaves the outer half of the stroke showing.
class _OutlinedIcon extends StatelessWidget {
  const _OutlinedIcon(this.icon, {required this.color, required this.size});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    TextStyle style({Color? fill, Paint? paint}) => TextStyle(
      inherit: false,
      fontFamily: icon.fontFamily,
      package: icon.fontPackage,
      fontSize: size,
      height: 1,
      color: fill,
      foreground: paint,
    );
    final glyph = String.fromCharCode(icon.codePoint);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            glyph,
            style: style(
              paint: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3
                ..strokeJoin = StrokeJoin.round
                ..color = Colors.black,
            ),
          ),
          Text(glyph, style: style(fill: color)),
        ],
      ),
    );
  }
}

/// A cinema's listings: the films you can make in the current search, then everything else on
/// whichever day of the listings is picked (today to begin with).
class _VenueSheet extends ConsumerStatefulWidget {
  const _VenueSheet({required this.venue});
  final Venue venue;

  @override
  ConsumerState<_VenueSheet> createState() => _VenueSheetState();
}

class _VenueSheetState extends ConsumerState<_VenueSheet> {
  DateTime? _day;

  @override
  Widget build(BuildContext context) {
    final venue = widget.venue;
    final listings = ref.watch(listingsProvider).requireValue;
    final results = ref.watch(resultsProvider);
    final theme = Theme.of(context);
    // This cinema's best screening of each film you can make.
    final makeable = [
      for (final c in results?.cards ?? const <FilmCard>[])
        for (final a in c.cinemas)
          if (a.venue.id == venue.id) a.best,
    ];

    // Everything at this cinema on the chosen day, grouped by film. Today: only what's still to start.
    final now = londonNow();
    final today = dayOf(now);
    final days = listings.coveredDays(today);
    final day = _day != null && days.contains(_day) ? _day! : days.first;
    final isToday = day == today;
    final byTitle = <String, List<Performance>>{};
    for (final p in listings.performances) {
      final s = listings.showings[p.showing];
      if (s.venue != venue.id) continue;
      final start = fromUnix(p.start);
      if (dayOf(start) != day || (isToday && start.isBefore(now))) continue;
      final title = s.title ?? listings.films[s.film]?.title ?? '';
      byTitle.putIfAbsent(title, () => []).add(p);
    }
    final titles = byTitle.keys.toList()..sort();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(venue.name, style: theme.textTheme.titleLarge),
          if (venue.address != null) Text(venue.address!, style: theme.textTheme.bodySmall),
          if (venue.url != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openUrl(context, venue.url),
                icon: const Icon(Icons.open_in_new),
                label: const Text("Cinema's website"),
              ),
            ),
          if (makeable.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('You can make', style: theme.textTheme.titleMedium),
            for (final r in makeable)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 36,
                    height: 54,
                    child: Poster(poster: r.c.poster, size: 'w154'),
                  ),
                ),
                title: Text(r.c.title),
                subtitle: Text(
                  'Starts ${hm(r.c.start)} · leave ${hm(r.setOff)}'
                  '${r.homeAt != null ? ' · home ${hm(r.homeAt!)}' : ''}',
                ),
                trailing: FilledButton.tonal(
                  onPressed: () => openUrl(context, r.c.bookingUrl),
                  child: const Text('Book'),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(isToday ? 'Still to start today' : 'Showing ${_on(day, today)}', style: theme.textTheme.titleMedium),
          if (days.length > 1) ...[
            const SizedBox(height: 8),
            // The rest of the days in the listings, as a single scrolling row.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final d in days) ...[
                    ChoiceChip(
                      label: Text(dayLabel(d, today)),
                      selected: d == day,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _day = d),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ],
          if (titles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(isToday ? 'Nothing else today.' : 'Nothing listed ${_on(day, today)}.'),
            ),
          for (final t in titles)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in byTitle[t]!)
                        ActionChip(
                          label: Text(hm(fromUnix(p.start)) + (p.soldOut ? ' sold out' : '')),
                          onPressed: p.soldOut || p.bookingUrl == null ? null : () => openUrl(context, p.bookingUrl),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// "tomorrow" / "on Wed 30 Sep", for use mid-sentence.
  String _on(DateTime day, DateTime today) {
    final label = dayLabel(day, today);
    return label == 'Tomorrow' ? 'tomorrow' : 'on $label';
  }
}
