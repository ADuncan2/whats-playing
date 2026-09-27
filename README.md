# WhatsPlaying

Flutter (Android) app for "which London screenings can I get to, watch, and still be home by X?".
A port of the Python prototype in `../Movie search`, laid out after `docs/wireframe.jpg`.

- **Data:** `https://aduncan2.github.io/london-film-data/listings.json` (built 3x a day by the
  `london-film-data` repo). Cached on the phone for 3 hours; the cached copy is used offline.
- **Journeys:** live TfL times only. Cinemas are checked nearest first and each one's films are added
  to the end of the results as its answer comes in. The results are one row per film, with the other
  cinemas showing it behind; they can be narrowed by cinema chain, genre or film at any point, and
  once the search has finished sorted by leave time, start time, home time or journey length. Postcodes via postcodes.io, maps via OpenStreetMap. No backend.

## Run

```sh
cp env.example.json env.json          # optional: put a free TfL app key in it (api-portal.tfl.gov.uk)
flutter run --dart-define-from-file=env.json
flutter test                          # engine tests mirror ../Movie search/test_filmfinder.py
```

Without a TfL key everything works, but only the nearest 25 cinemas are checked and results come in
more slowly (TfL allows anonymous use 50 requests a minute; a free key allows 500).

There are two ways to supply a key, and the app uses whichever it has, preferring the first:

- **Settings -> TfL app key.** Anyone using the app pastes their own free key; the dialog explains
  how to get one. Stored on the phone only. This is the route for builds that other people install.
- **`env.json` at build time.** Compiles the key into the APK, which is fine for your own device;
  don't publish a build containing it.

## Web version (iPhone)

The same app built for the web, published by `.github/workflows/web-pages.yml` to
`https://aduncan2.github.io/whats-playing/` on every push to master. On an iPhone: open it in Safari,
Share -> Add to Home Screen. Try it locally with `flutter run -d chrome`.

- One-off setup: repo Settings -> Pages -> Source: "GitHub Actions".
- No TfL key is compiled into the web build (anyone could read it from the site). Paste a key into
  Settings in the app; it is kept in the browser.
- Differences from Android: listings are cached in memory for the session (no app folder), the
  Letterboxd data lives in the browser's storage, and the Letterboxd diary RSS top-up won't work
  (letterboxd.com doesn't allow browser requests from other sites); the ZIP import does.
- Use it from the home-screen icon, not a Safari tab: Safari can wipe a site's storage (settings,
  Letterboxd link) after 7 days without a visit, and home-screen web apps are exempt.

## Letterboxd

Settings -> Link Letterboxd. There is no "log in with Letterboxd": the official API is invite-only
and refuses personal projects, and scraping breaks its terms. Instead the user downloads their own
data export (a ZIP of CSVs) and hands it to the app; see `docs/letterboxd-linking.md` for the why
and the flow. The export link is opened in a Chrome Custom Tab, not the Letterboxd app (which loops).

- **Watchlist:** Home shows "On your watchlist this week" (the watchlist films with a screening
  still to come, soonest first); tapping one opens the search preset to that film and day. Results
  rows for watchlist films carry a badge. A nudge appears when the export is over 30 days old.
- **Hide films I've seen:** a toggle on the search form (only once linked). Films on the watched
  list are dropped in `plan()`, before any TfL lookups. Optionally, the public diary RSS feed for a
  username tops up "seen" between exports, at most every 6 hours; failures keep the last good data.
- Matching is local, by normalised title + year (`lib/engine/film_match.dart`), and conservative: a
  false "seen" hides a film the user wanted. Data lives in `letterboxd.json` in the app folder;
  Unlink deletes it.

## Credits and licences

The code is MIT licensed (`LICENSE`). The data the app shows is not: screenings come from
Clusterflick (CC BY 4.0), film details and posters from TMDB, journeys from TfL Open Data, postcodes
from postcodes.io and maps from OpenStreetMap. The required credits for each are in the app, under
Settings -> Credits and licences (`lib/features/settings/credits_screen.dart`); `NOTICE` lists what
the MIT licence does not cover.

This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved
by TMDB. Not affiliated with or endorsed by Letterboxd.

## Layout

- `lib/engine/` - the search (port of `filmfinder.py`): `plan()` = local filtering,
  `routeVenue()` = journey lookups for one cinema, `search()` = both.
- `lib/features/results/results_controller.dart` - checks cinemas with TfL in the background, appending a row per film.
- `lib/data/` - listings cache, postcode/GPS lookups, settings; `letterboxd/` - export import, RSS, store.
- `lib/engine/film_match.dart` - Letterboxd rows <-> listings films.
