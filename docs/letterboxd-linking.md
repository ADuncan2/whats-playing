# Letterboxd linking — spec for the WhatsPlaying Flutter app

Updated 25 Sep 2026. Written for Claude Code to implement in this repo (`whats_playing`, Android).

Two features:

1. **Watchlist alert.** Show films from the user's Letterboxd watchlist that are playing in the listings window (next 7 days).
2. **"Watch something new" filter.** Hide films the user has already seen.

---

## 1. Background: why there is no "Log in with Letterboxd"

- The official Letterboxd API is invite-only. Its page (letterboxd.com/api-beta) says requests are refused for "private or personal projects" and for anything that "recreates current or planned features of our paid subscription tiers". Letterboxd runs its own UK showtimes and plans notifications, so this app would be refused. Do not build on the API.
- Scraping the public watchlist pages breaks Letterboxd's terms of use (6.11: no robots, spiders or scrapers). Do not do it.
- What is left, and what this spec uses:
  - **The data export ZIP.** This is the user's own data (terms 6.8 allow exporting your own content). It contains the full watchlist and the full watched list. There are no TMDB ids, only Name + Year + Letterboxd URI. It is manual and goes stale until re-exported.
  - **The profile RSS feed** (`https://letterboxd.com/<username>/rss/`). It is public, needs only the username, and holds the last 50 activity items. Diary items carry `tmdb:movieId`. Use it to top up "watched" between exports. There is no watchlist feed.

## 2. Linking flow (what the user does)

**Tested on Android:** tapping `https://letterboxd.com/user/exportdata/` on the phone opens the Letterboxd app, which then loops forever. Pasting the same link into a browser, signing in there, and loading it again downloads the ZIP. The flow must therefore keep the link **out of the Letterboxd app**.

### Screen: Settings → Letterboxd → "Link Letterboxd"

Show these steps (the in-app copy can be lightly edited, but keep the order):

> **Link your Letterboxd account**
> WhatsPlaying never sees your Letterboxd password. You download a copy of your data from Letterboxd, then give that file to the app.
>
> **1. Download your data from Letterboxd**
> Tap **Open in browser**. If Letterboxd asks you to sign in, do so. Your download (a `.zip` file) should start straight away. If it doesn't, open the link again after signing in.
> `[Open in browser]`
>
> Opened the Letterboxd app instead, or it keeps loading? Tap **Copy link**, open Chrome (or any browser), paste the link into the address bar, and sign in there.
> `https://letterboxd.com/user/exportdata/` `[Copy link]`
>
> **2. Import the file**
> Tap **Choose file** and pick the file that starts `letterboxd-` in your Downloads folder.
> `[Choose file]`
>
> **3. (Optional) Keep "seen" films up to date automatically**
> Enter your Letterboxd username. The app checks your public diary feed for films you've logged since your last export.
> `[username field]`
>
> Your watchlist only updates when you import a new file. We'll remind you when it's more than 30 days old.

After a successful import, show a summary: "Imported 212 watchlist films and 1,048 watched films (exported 25 Sep 2026)". Also show buttons for **Re-import** and **Unlink** (Unlink deletes the stored data).

### Opening the link without landing in the Letterboxd app

The existing `openUrl()` in `lib/ui/links.dart` uses `LaunchMode.externalApplication`. On Android that fires an ACTION_VIEW intent, and Android hands letterboxd.com links (verified App Links) to the Letterboxd app. That is the loop seen in testing. **Do not use `openUrl()` for this link.**

Add `openInBrowser()` (in `links.dart`, or in the Letterboxd feature), which tries the following in order:

1. `launchUrl(uri, mode: LaunchMode.inAppBrowserView)`. On Android this opens a **Chrome Custom Tab**. The intent is addressed to the browser, so App Link resolution is not triggered. It shares Chrome's cookies, so a signed-in user stays signed in, and Chrome handles the ZIP download.
2. If that returns false or throws, copy the link to the clipboard (`Clipboard.setData`) and show a SnackBar: "Link copied — paste it into your browser".

**Verify on the device** (the test phone, Letterboxd app installed):
- (a) The Custom Tab opens the page rather than the Letterboxd app.
- (b) Signing in inside the Custom Tab works, and the ZIP lands in Downloads.
- (c) If step (a) fails and the Custom Tab still hands off to the app, the fallback is `LaunchMode.externalApplication` with an explicit browser. That isn't available through url_launcher, so it would need `android_intent_plus` with `package: 'com.android.chrome'`. Only add that dependency if (a) fails.
- Caveat: if the device has no Custom Tabs provider, url_launcher falls back to a WebView. A WebView has no Chrome sign-in and doesn't handle downloads, so in that case go straight to the copy-link fallback. You may need to add a `<queries>` entry for `android.support.customtabs.action.CustomTabsService` in `AndroidManifest.xml` so the Custom Tabs provider is visible on Android 11+. Check the url_launcher_android README.

The **Copy link** button is always visible, not just shown on failure. It is the path confirmed to work.

## 3. What is in the export ZIP

The filename looks like `letterboxd-<username>-<date/time>.zip`. Check a real download, and fall back to import time if no date can be parsed. It contains CSVs at the root, plus sub-folders (`lists/`, `likes/`, `deleted/` …) that we ignore.

| File | Columns | Use |
|---|---|---|
| `watchlist.csv` | Date, Name, Year, Letterboxd URI | Feature 1 |
| `watched.csv` | Date, Name, Year, Letterboxd URI | Feature 2. This is every film marked watched, including those never logged with a date. **Use this, not diary.csv.** |
| `diary.csv` | Date, Name, Year, Letterboxd URI, Rating, Rewatch, Tags, Watched Date | Not needed; watched.csv is a superset of its films |
| `profile.csv` | includes Username | If present, pre-fill the RSS username field |

Parse the CSVs with the `csv` package. Titles contain commas and quotes, so do not split on commas. Look columns up by header name, not position, and tolerate missing optional files. If `watchlist.csv` and `watched.csv` are both missing, reject the file with "That doesn't look like a Letterboxd export".

## 4. Implementation

### New dependencies
- `file_picker`: choose the ZIP (`FileType.custom, allowedExtensions: ['zip']`).
- `archive`: unzip in memory (exports are small, well under 5 MB).
- `csv`: parse the CSV files.
- `xml`: parse the RSS feed.
- Already present: `url_launcher`, `http`, `path_provider`, `shared_preferences`.

### New files (suggested)
- `lib/data/letterboxd/letterboxd_import.dart`: ZIP → `LetterboxdData`. This is a pure function over bytes, so it can be unit-tested.
- `lib/data/letterboxd/letterboxd_rss.dart`: fetch and parse `https://letterboxd.com/<user>/rss/` → a set of TMDB ids for watched films plus their watched dates. Keep items that have `tmdb:movieId`; skip list items.
- `lib/data/letterboxd/letterboxd_store.dart`: persist as a JSON file in the app documents directory (via path_provider). A watched list can be thousands of rows, which is too big for shared_preferences.
- `lib/engine/film_match.dart`: match Letterboxd entries to `Film`s in `Listings`. Keep it pure and tested.
- `lib/features/settings/letterboxd_screen.dart`: the linking screen from section 2.

### Stored data (`LetterboxdData`)
```
exportedAt   (from filename, else import time)
importedAt
username     (profile.csv or typed; may be empty)
watchlist:   [{name, year, uri}]
watched:     [{name, year, uri}]
rssWatchedTmdb: {tmdbId: watchedDate}   // refreshed from RSS; union with watched
rssFetchedAt
```

### Matching (`film_match.dart`)
The listings window has about 430 films, each with `title`, `year` (a String), `tmdb` (nullable) and `imdb`. Match locally; no TMDB API is needed.
- Normalise titles: lowercase; strip diacritics; `&` → `and`; drop punctuation; collapse whitespace; drop a leading "the ".
- **CSV entry ↔ Film**:
  1. Normalised title equal **and** year equal → match.
  2. Otherwise, normalised title equal and year within ±1 → match. This covers festival vs release years.
  3. Otherwise, normalised title equal, no year on either side, and the title unique in the window → match.
  4. Otherwise, no match.
- **RSS item ↔ Film**: `film.tmdb == tmdbId`.
- Build two sets of listing film ids once per listings load: `onWatchlist` and `seen`.
- Be conservative: a false "seen" hides a film the user wanted, which is worse than a missed match. Films with `tmdb == null` (events, double bills, "+ Q&A") only get matched by rule 1.

### Feature 1: watchlist in the UI
- Home screen: an **"On your watchlist this week"** strip or card listing the matched films with next date + cinema count. Tapping one opens the existing film details / starts a search filtered to that film.
- Results: a small watchlist badge on film rows that are in `onWatchlist`.
- Nudge: when `importedAt` is older than 30 days, show a "Refresh your Letterboxd watchlist" line linking to the linking screen.
- **Later (not now):** push notifications for newly appearing watchlist films, via `workmanager` (daily) + `flutter_local_notifications`. Keep a stored set of already-notified film ids so each film is notified once per run of screenings.

### Feature 2: "Watch something new"
- Add a toggle, **"Hide films I've seen"**, alongside the existing chain / genre / film filters. Persist it in `Settings` (settings_store.dart) like `chains`.
- Apply it in the local filtering stage (`plan()` in `lib/engine/search.dart`, where chains are filtered) **before** TfL routing, so seen films cost no journey lookups.
- `seen` = films matched from `watched.csv` ∪ films whose tmdb is in `rssWatchedTmdb`.
- Refresh RSS at most once every 6 hours, when the app opens and a username is set. On any RSS failure (network error, non-200, Cloudflare page), keep the last good data silently.
- The toggle only appears (or is only enabled) once Letterboxd is linked.

### Tests (`test/`)
- `letterboxd_import_test.dart`: build a small ZIP in the test with the `archive` package, including a title with a comma and quotes, a missing `diary.csv`, and a non-Letterboxd ZIP (expect it to be rejected).
- `letterboxd_rss_test.dart`: parse a saved sample feed with a diary item, a review item and a list item.
- `film_match_test.dart`: exact, ±1 year, diacritics ("Amélie"), leading "The", `&`/"and", same title with different years (e.g. two films called "Suspiria", 1977 vs 2018: only the right one matches), and a tmdb-null event title.
- `plan()` test: with "hide seen" on, seen films are excluded before routing.

### Acceptance
- On the test phone, **Open in browser** reaches the export in Chrome (not the Letterboxd app), or the **Copy link** route works. Either way, the ZIP imports and the summary counts match the CSV row counts.
- The watchlist strip shows the films the user expects for the week. Spot-check 5 by hand against Letterboxd.
- "Hide films I've seen" removes the films they have logged, including a film logged after the export (via RSS).
- Unlink removes all Letterboxd data from the device.

## 5. Open points
- Whether the Custom Tab avoids the App Link hand-off on the test phone (section 2). This decides whether `android_intent_plus` is needed.
- Whether Letterboxd's Cloudflare blocks the RSS fetch from the app's HTTP client. Test on the device, and set a plain `User-Agent` such as `WhatsPlaying/1.1`. If it is blocked, feature 2 still works from the export alone.
- Later: accept the ZIP via Android "Share → WhatsPlaying" / "Open with", which would save a step. That needs an intent filter plus `receive_sharing_intent`.

---

## 6. Implementation status (25 Sep 2026)

Built as specified, against a real export (`letterboxd-<username>-<date>-utc.zip`, with the username
in `profile.csv`) and a live diary feed (review, watch and list items; `tmdb:movieId` on every diary item).

| Piece | Where |
|---|---|
| ZIP -> `LetterboxdData` (csv package, header lookup, filename date/username, `profile.csv` username wins) | `lib/data/letterboxd/letterboxd_import.dart` |
| RSS -> `{tmdbId: watchedDate}` (skips list items, keeps the latest date for rewatches, plain `User-Agent: WhatsPlaying/1.1`) | `lib/data/letterboxd/letterboxd_rss.dart` |
| JSON file store (`letterboxd.json` in the app support dir), in-memory store for tests | `lib/data/letterboxd/letterboxd_store.dart` |
| Matching rules 1-3 + `watchlistShowings()` for the Home strip | `lib/engine/film_match.dart` |
| `SearchOptions.excludeFilms`, applied in `plan()` with a funnel step, before routing | `lib/engine/search.dart` |
| Providers: store, RSS fetcher, `LetterboxdNotifier` (import / setUsername / refreshRss / unlink; RSS at most every 6 h on open), `filmMatchesProvider` | `lib/state/app_state.dart` |
| Linking screen (steps as in section 2; Re-import / Unlink; username + "Check now") | `lib/features/settings/letterboxd_screen.dart` |
| `openInBrowser()` (Custom Tab via `LaunchMode.inAppBrowserView`, else copy link) and the `<queries>` entry | `lib/ui/links.dart`, `AndroidManifest.xml` |
| Home strip + stale nudge; results badge; "Hide films I've seen" toggle (`Settings.hideSeen`) | `home_screen.dart`, `results_screen.dart`, `search_form.dart` |
| Tests | `test/letterboxd_import_test.dart`, `letterboxd_rss_test.dart`, `film_match_test.dart` (incl. the `plan()` case), `letterboxd_link_test.dart` (widget flow) |

Against the live listings on 25 Sep the matcher put 3 watchlist films in the window (Little Miss
Sunshine, All That Jazz, Desert Hearts) and 58 seen; the three same-title near misses (Sense and
Sensibility 1995 vs 2026, The Witches 1990 vs Witches 2024, Moana 2016 vs 2026) were correctly not matched.

Still to verify on the device (section 2 / section 5): whether the Custom Tab avoids the App Link
hand-off (if not, add `android_intent_plus` with `package: com.android.chrome`), and whether
Cloudflare lets the RSS fetch through. Push notifications and "Share -> WhatsPlaying" remain later.
