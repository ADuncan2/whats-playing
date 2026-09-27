/// Constants carried over from the Python prototype (`Movie search/filmfinder.py`).
library;

import 'package:flutter/foundation.dart';

/// True in the web build (GitHub Pages, the iPhone route): no app folder, no Custom Tabs, and
/// requests go through the browser's CORS rules.
const isWeb = kIsWeb;

const listingsUrl = 'https://aduncan2.github.io/london-film-data/listings.json';
const listingsSchema = 1; // the file format this code understands
const listingsMaxAge = Duration(hours: 3); // the file is rebuilt three times a day

/// A cached listings file is deleted once it is this old (or past its own expiresAt).
/// The data covers 7 days; TMDB's terms allow 6 months at most.
const listingsMaxKeep = Duration(days: 14);
const tflJourneyUrl = 'https://api.tfl.gov.uk/Journey/JourneyResults';
const tflModesUrl = 'https://api.tfl.gov.uk/Line/Meta/Modes'; // tiny: used to check an app key
const tflPortalUrl = 'https://api-portal.tfl.gov.uk/';
const postcodeUrl = 'https://api.postcodes.io/postcodes/';
const posterBaseUrl = 'https://image.tmdb.org/t/p/';
const tmdbMovieUrl = 'https://www.themoviedb.org/movie/';

/// Letterboxd's own data export (the user's watchlist and watched list as CSVs in a ZIP). Opened in
/// the browser, never the Letterboxd app: see docs/letterboxd-linking.md.
const letterboxdExportUrl = 'https://letterboxd.com/user/exportdata/';

/// Built-in TfL app key, compiled in with `--dart-define-from-file=env.json` for development.
/// A key pasted into Settings takes precedence (see `tflKeyProvider`). Empty = anonymous (slow).
const tflAppKey = String.fromEnvironment('TFL_APP_KEY');

const defaultRuntimeMin = 100; // only when a listing has no duration
const boundSpeedKmh = 35; // optimistic door-to-door speed: a travel-time LOWER bound only
const exitBufferMin = 5; // credits / getting out of the building
const bedBufferMin = 5; // front door to bed
const groupLookupBudget = 48; // group mode: cinemas checked = this ~/ number of people

/// Solo mode without a TfL key: only the nearest cinemas are checked. Anonymous TfL access allows
/// 50 requests a minute and each cinema costs up to two (there and back), so 25 keeps a search
/// around a minute. With a key (500 requests a minute) every candidate cinema is checked.
const anonymousVenueCap = 25;
const maxGroup = 4;

/// Minutes of ads and trailers assumed before a film, when working out when it ends.
const adsAllowanceMin = 20;

/// How far either side of the listed time the arrival slider goes, in minutes.
const arriveRangeMin = 25;

const chains = ['Odeon', 'Everyman', 'Vue', 'Cineworld', 'Curzon', 'Picturehouse', 'BFI'];
const otherChain = 'Independent / other';
