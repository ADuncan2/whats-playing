import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/listings.dart';
import '../../engine/journey_router.dart';
import '../../engine/search.dart';
import '../../state/app_state.dart';

/// A film at one cinema: every screening of it there that can be made, best first under the sort.
class AtCinema {
  AtCinema(this.venue, this.rows);

  final Venue venue;
  final List<ResultRow> rows;

  ResultRow get best => rows.first;
}

/// One film, wherever it is on: what a results row shows. The [front] screening is the one on the
/// row itself; the rest are behind it, grouped by cinema, and come out when the row is opened.
class FilmCard {
  FilmCard(this.key, this.front, this.cinemas);

  /// The listings film id, so "Beta" and "Beta (35mm)" are one film even at one cinema.
  final String key;

  /// Fixed while the search runs, however good the screenings that turn up behind it, so the row
  /// never changes under the user. [ResultsController.sort] puts the best one here.
  final ResultRow front;

  /// Every cinema showing it, the front's first. Best first once sorted; while searching, new
  /// cinemas join the end.
  final List<AtCinema> cinemas;

  Candidate get c => front.c;

  /// The cinema on the front, with every time that works there.
  AtCinema get here => cinemas.first;
  Iterable<ResultRow> get rows => cinemas.expand((a) => a.rows);
  int get screenings => cinemas.fold(0, (n, a) => n + a.rows.length);

  /// Cinemas other than the one on the front.
  int get otherCinemas => cinemas.length - 1;
}

/// Narrows what the results list shows without touching what was found: only these films (by
/// listings id), cinemas at these chains, films with any of these genres. Empty sets = no limit.
class ResultsFilter {
  const ResultsFilter({this.films = const {}, this.chains = const {}, this.genres = const {}});

  final Set<String> films, chains, genres;

  bool get isEmpty => films.isEmpty && chains.isEmpty && genres.isEmpty;
  int get count => films.length + chains.length + genres.length;

  ResultsFilter copyWith({Set<String>? films, Set<String>? chains, Set<String>? genres}) =>
      ResultsFilter(films: films ?? this.films, chains: chains ?? this.chains, genres: genres ?? this.genres);

  /// The card as it shows under this filter: as it is, with fewer cinemas, or not at all (null).
  /// When the cinema on the front is dropped, the best of the rest under [by] takes its place.
  FilmCard? apply(FilmCard card, SortBy by) {
    if (films.isNotEmpty && !films.contains(card.key)) return null;
    if (genres.isNotEmpty && !card.c.genres.any(genres.contains)) return null;
    if (chains.isEmpty) return card;
    final cinemas = [
      for (final a in card.cinemas)
        if (chains.contains(a.venue.chainOrOther)) a,
    ];
    if (cinemas.isEmpty) return null;
    if (cinemas.length == card.cinemas.length) return card;
    final front = cinemas.first.venue.id == card.here.venue.id
        ? card.front
        : cinemas.map((a) => a.best).reduce((x, y) => by.compare(x, y) <= 0 ? x : y);
    return FilmCard(card.key, front, cinemas);
  }
}

class ResultsState {
  ResultsState({
    required this.generation,
    required this.plan,
    required this.cards,
    required this.checked,
    required this.failed,
    required this.sortBy,
    required this.sorted,
    this.filter = const ResultsFilter(),
    this.liveErrors = const [],
  });

  final int generation;
  final SearchPlan plan;

  /// One per film. Append-only while the search runs, so cards never move under the user; a cinema
  /// answering with a film already shown only joins that film's card. Reordered only by [sort].
  final List<FilmCard> cards;

  /// Cinemas looked up so far, and how many of those lookups failed.
  final int checked, failed;

  /// The key new cards are laid out by, and whether the whole list is currently in that order.
  final SortBy sortBy;
  final bool sorted;

  /// What the user has narrowed the list to. Applied on the way out: [cards] is everything found.
  final ResultsFilter filter;
  final List<String> liveErrors;

  int get total => plan.order.length;
  bool get finished => checked >= total;

  /// Nothing found at all (as opposed to nothing left after filtering: [nothingShown]).
  bool get isEmpty => cards.isEmpty;
  List<FunnelStep> get funnel => plan.funnel;

  /// The cards the list shows: [cards] narrowed by [filter], in the same order.
  late final List<FilmCard> shown = filter.isEmpty ? cards : [for (final c in cards) ?filter.apply(c, sortBy)];
  bool get nothingShown => cards.isNotEmpty && shown.isEmpty;

  /// What the filter can be set to: everything found, whatever it is currently narrowed to.
  /// Films as (listings id, title), alphabetical; chains in the usual order; genres alphabetical.
  late final List<(String, String)> filmChoices = [for (final c in cards) (c.key, c.c.film)]
    ..sort((a, b) => a.$2.compareTo(b.$2));
  late final List<String> chainChoices = () {
    final found = {
      for (final c in cards)
        for (final a in c.cinemas) a.venue.chainOrOther,
    };
    return [
      for (final chain in [...chains, otherChain])
        if (found.contains(chain)) chain,
    ];
  }();
  late final List<String> genreChoices = {for (final c in cards) ...c.c.genres}.toList()..sort();
}

/// Runs a search against TfL cinema by cinema, most promising first, and adds each cinema's films as
/// its answer comes in. Only screenings TfL says can be made are ever shown.
class ResultsController extends Notifier<ResultsState?> {
  static const _inFlight = 4; // concurrent cinema lookups; the router spaces the requests themselves

  int _generation = 0;
  SearchPlan? _plan;
  List<FilmCard> _cards = [];
  int _checked = 0, _failed = 0;
  SortBy _sortBy = SortBy.leave;
  bool _sorted = false;
  ResultsFilter _filter = const ResultsFilter();

  @override
  ResultsState? build() => null;

  JourneyRouter get _router => ref.read(tflRouterProvider);

  void clear() {
    _generation++;
    _plan = null;
    state = null;
  }

  /// Plans the search and shows the (empty) results at once; the cinemas are then checked in the
  /// background, so this returns before any TfL answer is in.
  void start(Listings data, List<Person> people, SearchOptions options) {
    final gen = ++_generation;
    final sp = plan(data, people, options);
    _plan = sp;
    _cards = [];
    _checked = _failed = 0;
    _sortBy = ref.read(settingsProvider).sortBy;
    _sorted = false;
    _filter = const ResultsFilter();
    _publish();

    var next = 0;
    Future<void> worker() async {
      while (gen == _generation && next < sp.order.length) {
        final vid = sp.order[next++];
        VenueOutcome outcome;
        try {
          outcome = await routeVenue(sp, vid, _router);
        } catch (_) {
          outcome = const VenueOutcome([], failed: true);
        }
        if (gen != _generation) return;
        _add(sp, vid, outcome);
      }
    }

    for (var i = 0; i < _inFlight; i++) {
      unawaited(worker());
    }
  }

  void _add(SearchPlan sp, String vid, VenueOutcome outcome) {
    _checked++;
    if (outcome.failed) _failed++;
    final byFilm = <String, List<ResultRow>>{};
    for (final r in outcome.rows) {
      byFilm.putIfAbsent(r.c.filmId, () => []).add(r);
    }
    final venue = sp.data.venues[vid]!;
    final cards = List.of(_cards);
    final fresh = <FilmCard>[];
    for (final MapEntry(key: film, value: rows) in byFilm.entries) {
      final at = AtCinema(venue, rows..sort(_sortBy.compare));
      final i = cards.indexWhere((c) => c.key == film);
      if (i < 0) {
        fresh.add(FilmCard(film, at.best, [at]));
      } else {
        // Already showing: this cinema goes behind the card. The front stays put until a sort.
        final card = cards[i];
        cards[i] = FilmCard(film, card.front, [...card.cinemas, at]);
      }
    }
    fresh.sort((a, b) => _sortBy.compare(a.front, b.front));
    _cards = [...cards, ...fresh];
    _publish();
  }

  /// Once every cinema is in: order the screenings at each cinema, the cinemas within each film,
  /// and the films by their best screening, all by [by]. The choice is kept for the next search.
  void sort(SortBy by) {
    final s = state;
    if (s == null || !s.finished) return;
    _sortBy = by;
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(sortBy: by));
    _cards = [for (final card in _cards) _resorted(card, by)]..sort((a, b) => by.compare(a.front, b.front));
    _sorted = true;
    _publish();
  }

  /// Narrow (or widen) what the list shows. Fine while the search is still running: it is only a
  /// view over the cards, so cinemas still to answer join in as usual.
  void filter(ResultsFilter f) {
    if (state == null) return;
    _filter = f;
    _publish();
  }

  static FilmCard _resorted(FilmCard card, SortBy by) {
    final cinemas = [for (final a in card.cinemas) AtCinema(a.venue, List.of(a.rows)..sort(by.compare))]
      ..sort((a, b) => by.compare(a.best, b.best));
    return FilmCard(card.key, cinemas.first.best, cinemas);
  }

  void _publish() {
    final sp = _plan;
    if (sp == null) return;
    state = ResultsState(
      generation: _generation,
      plan: sp,
      cards: _cards,
      checked: _checked,
      failed: _failed,
      sortBy: _sortBy,
      sorted: _sorted,
      filter: _filter,
      liveErrors: List.of(_router.errors.reversed.take(5)),
    );
  }
}

final resultsProvider = NotifierProvider<ResultsController, ResultsState?>(ResultsController.new);
