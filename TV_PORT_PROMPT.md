# Port full mobile-app feature set into the Android TV variant

## Context

This is a Flutter Android-TV streaming app. It already has:

- Home, Search, Details screens (with D-pad focus on cards)
- A native video player page
- Basic webview-based playback

It's missing **everything else** from the mobile sibling. This prompt lists,
in implementation order, every store / page / endpoint / model to port,
plus two TV-specific cross-cutting fixes (responsive scaling + full remote
control of the player).

Stack to keep: **MobX** (state), **Dio** (HTTP), **freezed +
json_serializable** (models), **shared_preferences** (token + avatar
persistence), **flutter_inappwebview**, **video_player**, **wakelock_plus**,
**permission_handler**.

---

## 0. Switch the embed provider (one-line change)

The TV app currently embeds `vidlink.pro`. The mobile sibling switched to
`player.videasy.net` and all the URL patterns below assume that. Update
`lib/services/config.dart`:

```dart
const String serverurl   = 'https://player.videasy.net/movie/';
const String tvServerurl = 'https://player.videasy.net/tv/';
```

TV episode URLs gain query params (more on this in §6):
`https://player.videasy.net/tv/{tvId}/{seasonNumber}/{episodeNumber}?episodeSelector=true&nextEpisode=true&autoplayNextEpisode=true[&progress={seconds}]`.

---

## 1. Endpoint constants (`lib/services/config.dart`)

Add these constants (the existing ones from the mobile app):

```dart
// TMDB catalog (proxied via videasy)
const String searchUrl    = 'https://db.videasy.net/3/search/multi?language=en&page=1&query=';
const String homeUrl      = 'https://db.videasy.net/3/trending/all/day?region=US&language=en';
const String topMoviesUrl = 'https://db.videasy.net/3/discover/movie?sort_by=popularity.desc&language=en&page=1';
const String topSeriesUrl = 'https://db.videasy.net/3/discover/tv?sort_by=popularity.desc&language=en&page=1';
const String topAnimeUrl  = 'https://db.videasy.net/3/discover/tv?with_genres=16&with_origin_country=JP|CN&sort_by=popularity.desc&language=en&page=1';

const String movieDetailUrl    = 'https://db.videasy.net/3/movie';
const String movieDetailParams = '?append_to_response=credits,external_ids,videos&language=en';

const String tvDetailUrl       = 'https://db.videasy.net/3/tv';
const String tvDetailParams    = '?append_to_response=credits,external_ids,videos&language=en';
const String tvSeasonUrl       = 'https://db.videasy.net/3/tv';            // append /{tvId}/season/{n}
const String tvSeasonParams    = '?language=en';

// Avatar picker (popular people, pages 1 & 2)
const String popularPeopleUrl  = 'https://db.videasy.net/3/person/popular?language=en&page=';

// Reelix backend (auth, watchlist, history)
const String apiBaseUrl = 'https://cineby-main.vercel.app/api/v1';
```

---

## 2. ApiClient (`lib/services/api_client.dart`)

Single Dio-backed client used by every Reelix store. Responsibilities:

- Attach `Authorization: Bearer <accessToken>` on every request except
  `/auth/*`.
- On `401` (and not on an `/auth/*` call), call `POST /auth/refresh` with
  the stored `refreshToken`, save the new `accessToken`, retry the failed
  request once. If refresh fails, clear tokens and notify `AuthStore` to
  log out.
- Persist tokens to `SharedPreferences` under `reelix.accessToken` and
  `reelix.refreshToken`.

Public surface (rough):

```dart
class ApiClient {
  Future<void> loadTokens();
  Future<void> saveTokens({String access, String refresh});
  Future<void> clearTokens();
  String? get accessToken;
  Future<Response> get(String path, {Map<String, dynamic>? query});
  Future<Response> post(String path, {Object? body});
  Future<Response> delete(String path, {Map<String, dynamic>? query});
}
```

Expose a singleton: `final apiClient = ApiClient();` initialised in `main`.

---

## 3. Auth — store + login/register page

### `lib/stores/auth_store.dart` (MobX)

```dart
class AuthUser { final String id, name, email; }

@observable AuthUser? user;
@observable String?  avatarPath;
@observable bool     isLoading = false;
@observable String?  errorMessage;
@computed  bool      isAuthenticated => user != null;

Future<void> bootstrap();   // load tokens, GET /me if present
Future<void> login({required String email, required String password});
Future<void> register({required String name, required String email, required String password});
Future<void> logout();      // clear tokens + user + avatar
Future<void> setAvatarPath(String path);    // persist per-user
```

Reelix endpoints used:

| Method | Path             | Body                                  | Response                              |
|--------|------------------|---------------------------------------|---------------------------------------|
| POST   | `/auth/register` | `{name, email, password}`             | `{accessToken, refreshToken, user}`   |
| POST   | `/auth/login`    | `{email, password}`                   | `{accessToken, refreshToken, user}`   |
| POST   | `/auth/refresh`  | `{refreshToken}`                      | `{accessToken}`                       |
| GET    | `/me`            | —                                     | `{id, name, email}`                   |

SharedPreferences keys:
- `reelix.accessToken`
- `reelix.refreshToken`
- `reelix.avatar.{userId}` (per-user avatar selection)

### `lib/services/pages/login_page.dart`

Two-mode UI (Login / Register toggle). Inputs: email, password, name (register
only). On submit calls `authStore.login(...)` / `authStore.register(...)`.

**TV-specific**: form fields and submit button must all be focusable, focus
order top-to-bottom, ENTER submits, BACK exits. Use `Autofocus(true)` on the
email field and `FocusTraversalGroup(policy: OrderedTraversalPolicy())` to
enforce predictable D-pad order.

### Routing gate (`lib/main.dart`)

```dart
await authStore.bootstrap();
runApp(MyApp());

// In MyApp.build:
return Observer(builder: (_) =>
  authStore.isAuthenticated ? const RootShell() : const LoginPage()
);
```

---

## 4. Watchlist

### `lib/stores/watchlist_store.dart` (MobX)

```dart
class WatchlistItem {
  final String id;
  final int tmdbId;
  final String mediaType;   // 'movie' | 'tv'
  final String? title;
  final String? posterPath;
  final DateTime addedAt;
}

@observable ObservableList<WatchlistItem> items;
@observable ObservableMap<String, bool>   _containsCache;   // key: "$tmdbId:$mediaType"
@observable bool   isLoading;
@observable String? errorMessage;

Future<void> fetch();
Future<bool> checkContains(int tmdbId, String mediaType);
Future<void> add({required int tmdbId, required String mediaType, String? title, String? posterPath});
Future<void> remove({required int tmdbId, required String mediaType});
Future<void> toggle({required int tmdbId, required String mediaType, String? title, String? posterPath});
```

Endpoints:

| Method | Path                                      | Query / Body                                    | Returns           |
|--------|-------------------------------------------|-------------------------------------------------|-------------------|
| GET    | `/watchlist`                              | —                                               | `{items: [...]}`  |
| POST   | `/watchlist`                              | `{tmdbId, mediaType, title?, posterPath?}`      | —                 |
| GET    | `/watchlist/contains/{tmdbId}`            | `?mediaType=movie\|tv`                          | `{inWatchlist}`   |
| DELETE | `/watchlist/{tmdbId}`                     | `?mediaType=movie\|tv`                          | —                 |

UI integration:

- **Movie/TV detail pages**: focusable bookmark icon next to Play. Calls
  `watchlistStore.toggle(...)`. Icon state from `_containsCache`.
- **Library page** (new — see §7): Watchlist tab grids `watchlistStore.items`.

---

## 5. History + Continue Watching

### `lib/stores/history_store.dart` (MobX)

```dart
class HistoryItem {
  final String id;
  final int tmdbId;
  final String mediaType;        // 'movie' | 'tv'
  final int? seasonNumber;
  final int? episodeNumber;
  final int progressSeconds;
  final int? durationSeconds;
  final bool completed;          // server marks true at ≥ 90%
  final String? title, posterPath, backdropPath;
  final DateTime watchedAt, updatedAt;
}

@observable ObservableList<HistoryItem> items;
@observable ObservableList<HistoryItem> continueWatching;
@observable bool   isLoading;
@observable String? errorMessage;

Future<void> fetch();
Future<void> fetchContinueWatching();
Future<HistoryItem?> latestForMovie(int tmdbId);
Future<HistoryItem?> latestForShow (int tmdbId);
Future<void> record({
  required int tmdbId,
  required String mediaType,
  int? seasonNumber, int? episodeNumber,
  required int progressSeconds,
  int? durationSeconds,
  String? title, String? posterPath, String? backdropPath,
});
Future<void> remove(String id);
Future<void> clearAll();
```

Endpoints:

| Method | Path                              | Body / Query                                 | Returns                                  |
|--------|-----------------------------------|----------------------------------------------|------------------------------------------|
| GET    | `/history`                        | —                                            | `{items: [...]}`                         |
| GET    | `/history/continue-watching`      | —                                            | `{items: [...]}` (incomplete only)       |
| GET    | `/history/{tmdbId}`               | `?mediaType=movie\|tv`                       | `{item: HistoryItem \| null}`            |
| POST   | `/history`                        | (see `record()` signature above)             | —                                        |
| DELETE | `/history/{id}`                   | —                                            | —                                        |
| DELETE | `/history`                        | —                                            | —                                        |

Call sites:

- **Native/Webview player**: `record(...)` every 10–15 s of playback + once on
  dispose. Always include `durationSeconds` once known.
- **Detail pages**: on mount, call `latestForMovie/Show` to populate the "Resume
  from X:XX" button next to Play.
- **Home page**: top row "Continue Watching" → `historyStore.continueWatching`
  (fetched on app start).
- **Library page** (new): History tab → `historyStore.items`, with
  dismiss-to-delete on each row.

---

## 6. TV episode selection

### `lib/stores/tv_detail_store.dart` (MobX)

```dart
@observable TvDetail?      tvDetail;
@observable SeasonDetail?  selectedSeason;
@observable int?           selectedSeasonNumber;
@observable bool           isLoading;
@observable bool           isSeasonLoading;
@observable String?        errorMessage;

Future<void> fetchTvDetail(int tvId);
// internally calls fetchSeason(tvId, tvDetail.seasons.first.seasonNumber)

Future<void> fetchSeason(int tvId, int seasonNumber);
```

Endpoints:

- `GET {tvDetailUrl}/{tvId}{tvDetailParams}` → `TvDetail` (includes
  `seasons: List<SeasonSummary>` — metadata only, no episode bodies).
- `GET {tvSeasonUrl}/{tvId}/season/{seasonNumber}{tvSeasonParams}` →
  `SeasonDetail` (full `episodes: List<Episode>`).

### Episode-picker UI (TV-specific)

The mobile version is a dropdown + linear list. **For TV**, use a two-column
focus pattern:

- **Left column** (narrow): vertical focusable list of seasons
  (`tvDetail.seasons`). On focus change (D-pad up/down) call
  `_store.fetchSeason(tvId, n)`.
- **Right column** (wide): horizontal carousel of `selectedSeason.episodes`
  showing episode still + title + runtime. ENTER plays it.

Implement with a `FocusTraversalGroup` so D-pad right from the season list
crosses into the episode rail, and D-pad left returns.

### Playing an episode

```dart
historyStore.record(
  tmdbId: tvId, mediaType: 'tv',
  seasonNumber: s, episodeNumber: e,
  progressSeconds: resumeProgress,
  durationSeconds: (episode.runtime ?? 0) * 60,
  title: tvDetail.name, posterPath: tvDetail.posterPath,
  backdropPath: tvDetail.backdropPath,
);
Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => MyWidget(
  url: '$tvServerurl$tvId/$s/$e?episodeSelector=true&nextEpisode=true'
       '&autoplayNextEpisode=true${resumeProgress > 0 ? "&progress=$resumeProgress" : ""}',
  tmdbId: tvId, mediaType: 'tv',
  seasonNumber: s, episodeNumber: e,
  initialProgressSeconds: resumeProgress,
  durationSeconds: (episode.runtime ?? 0) * 60,
  title: tvDetail.name, posterPath: tvDetail.posterPath,
  backdropPath: tvDetail.backdropPath,
)));
```

---

## 7. Profile, Library, Avatar picker

### `lib/services/pages/library_page.dart`

Two tabs (TabBar at the top, both tabs focusable):

1. **Watchlist** — responsive grid of `watchlistStore.items`. Each card
   focusable; ENTER opens the matching detail page; long-press / OPTION key
   removes via `watchlistStore.remove(...)`.
2. **History** — vertical list of `historyStore.items`. Each row focusable;
   ENTER resumes playback (use stored `seasonNumber/episodeNumber` for TV);
   OPTION key (or a focusable trash icon) calls `historyStore.remove(id)`.

### `lib/services/pages/profile_page.dart`

Sections, top-to-bottom:

- Avatar + display name + email
- **Continue Watching** rail → `historyStore.continueWatching`
- **My Watchlist** preview → first 8 items of `watchlistStore.items`, with a
  "See all" pill that opens LibraryPage on Watchlist tab
- **Recent History** preview → first 8 items of `historyStore.items`, "See
  all" → LibraryPage History tab
- Account menu (focusable rows): Change avatar → opens AvatarPicker;
  Log out → `authStore.logout()`

### `lib/services/pages/avatar_picker.dart`

Modal or dedicated page. Fetches popular people from TMDB pages 1 and 2 in
parallel:

```dart
final r = await Future.wait([
  Dio().get('$popularPeopleUrl' '1'),
  Dio().get('$popularPeopleUrl' '2'),
]);
```

Grid of focusable `CircleAvatar`s using `profile_path` (TMDB image base:
`https://image.tmdb.org/t/p/w185`). ENTER on one calls
`authStore.setAvatarPath(profilePath)` and pops.

### `lib/services/pages/root_shell.dart`

`IndexedStack` of [Home, Library, Profile] with a focusable left rail (or
top tab bar) for navigation. Standard Android-TV leanback pattern: large
focused icon + text, dimmed unfocused.

---

## 8. Data models (`lib/models/`)

Use `freezed` + `json_serializable`. Shapes required (match mobile):

```dart
class SearchResult {
  int id;
  String? title, name, originalTitle, originalName, overview;
  String? posterPath, backdropPath;
  String mediaType;       // 'movie' | 'tv' | 'person'
  String? releaseDate;
  double? voteAverage;
  int? voteCount;
}

class MovieDetail {
  int id;
  String? title, overview, tagline, posterPath, backdropPath;
  int? runtime;
  String? releaseDate, status;
  double? voteAverage;
  int? voteCount;
  List<Genre> genres;
  List<CastMember> cast;
  String? directorName;   // extracted from credits.crew where job == 'Director'
}

class TvDetail {
  int id;
  String? name, overview, tagline, posterPath, backdropPath, firstAirDate, status;
  double? voteAverage;
  int? voteCount;
  int? numberOfSeasons, numberOfEpisodes;
  List<Genre> genres;
  List<CastMember> cast;
  String? creatorName;    // first of created_by[]
  List<SeasonSummary> seasons;
}

class SeasonSummary { int id, seasonNumber; String? name; int? episodeCount; String? posterPath, airDate; }
class SeasonDetail  { int seasonNumber; List<Episode> episodes; }
class Episode {
  int seasonNumber, episodeNumber;
  String? name, overview, airDate, stillPath;
  int? runtime;
}

class Genre      { int id; String name; }
class CastMember { String name; String? character; String? profilePath; }
```

Plus the `WatchlistItem` / `HistoryItem` / `AuthUser` shapes from §3–5.

---

## 9. Stream extraction (if not already in TV native player)

If your TV native player today just plays a fixed URL, port the *extraction*
layer from the mobile webview so it can hand off captured m3u8/mp4 + headers
to the native player.

### In `lib/services/pages/webview.dart`

- `InAppWebViewSettings(useShouldInterceptRequest: true, ...)`.
- `shouldInterceptRequest` (Android only — `Platform.isAndroid` guard).
- Capture:
  - `_streamUrl`: first URL containing `.m3u8` / `.mp4` / `.mpd` /
    `/manifest` / `/playlist` AND NOT a segment (`.ts?`, ends `.ts`,
    contains `.m4s`).
  - `_subtitleUrl`: first URL containing `.vtt` / `.srt` / `/subtitle` /
    `/caption`.
  - `_streamHeaders`: keep only `Referer`, `Origin`, `User-Agent`,
    `Cookie`, and any `Sec-*` headers. Default `Referer` to
    `{scheme}://{host}/` if missing.
- 1.2 s after capture, `Navigator.pushReplacement(...)` to
  `NativePlayerPage(videoUrl, httpHeaders, subtitleUrl, ...history props)`.
- While waiting, show a slim top banner: *"Press OK on the play button —
  we'll switch to the native player automatically."*

### In `lib/services/pages/native_player.dart`

```dart
VideoPlayerController.networkUrl(Uri.parse(videoUrl), httpHeaders: httpHeaders)
```

Without `Referer` most CDNs return 403. For subtitles, fetch the VTT body
(reusing the same headers) and feed
`controller.setClosedCaptionFile(Future.value(WebVTTCaptionFile(body)))`.

---

## 10. Remote-control playback (TV-specific)

The mobile native player uses touch + double-tap-to-seek. **Strip that for
TV.** Wrap the player Scaffold in `FocusableActionDetector` (or
`Focus` + `KeyboardListener`) and bind these `LogicalKeyboardKey`s:

| Key                                       | Action                            |
|-------------------------------------------|-----------------------------------|
| `arrowLeft`                               | seek `-10 s`                      |
| `arrowRight`                              | seek `+10 s`                      |
| `arrowUp` / `arrowDown`                   | show controls (no other effect)   |
| `select` / `enter` / `space`              | toggle play/pause                 |
| `mediaPlayPause`                          | toggle play/pause                 |
| `mediaPlay`                               | play                              |
| `mediaPause`                              | pause                             |
| `mediaFastForward`                        | seek `+30 s`                      |
| `mediaRewind`                             | seek `-30 s`                      |
| `mediaTrackNext` / `mediaTrackPrevious`   | seek `+/-60 s`                    |
| `escape` / `goBack`                       | pop the route                     |
| `keyC` (and `mediaStop`)                  | toggle subtitles                  |

Any key press makes the controls overlay visible and resets a 4 s
inactivity timer that re-hides it. Auto-`requestFocus()` on init.

**Controls UI** (when visible): centred play/pause icon, non-interactive
seek bar showing position (no focusable `Slider` — seeking is via keys),
current/total time, subtitle toggle hint, back hint. Brief animated
"+10s" / "-10s" indicator on each seek.

Disable rotation entirely (`SystemChrome.setPreferredOrientations([landscapeLeft,
landscapeRight])` — TVs don't rotate but the lock prevents accidental
portrait on dev boxes). Keep wakelock on.

---

## 11. Resolution-agnostic scaling (1080p / 2K / 4K)

The current symptom — correct on the emulator, off on a 4K TV — is
hard-coded logical pixel values (`width: 220`, `fontSize: 24`,
`EdgeInsets.all(16)`) tuned at one resolution.

**Step A — global scale.** In `lib/main.dart`:

```dart
builder: (context, child) {
  final m = MediaQuery.of(context);
  final scale = (m.size.width / 1920).clamp(0.75, 2.5);
  return MediaQuery(
    data: m.copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  );
},
```

Plus an extension for widget dimensions:

```dart
extension TvScale on num {
  double s(BuildContext ctx) => this * (MediaQuery.of(ctx).size.width / 1920);
}
```

**Step B — sweep.** Replace every hard-coded `width:`, `height:`,
`fontSize:`, `EdgeInsets.*`, and `BorderRadius.circular(N)` in
`home.dart`, `search.dart`, `details.dart`, `library_page.dart`,
`profile_page.dart`, and any shared card widgets with `N.s(context)`.

**Step C — verify.** Run on three Android-TV targets at 1920×1080,
2560×1440, and a real 4K device. Hero, grid, paddings, fonts must keep the
same visual ratio.

(Optional alternative: `flutter_screenutil` with
`ScreenUtilInit(designSize: Size(1920, 1080))` and `.sw` / `.sh` / `.sp`.
Don't half-adopt it — all or nothing.)

---

## 12. SharedPreferences keys (full list)

| Key                       | Value  | Set by                          |
|---------------------------|--------|---------------------------------|
| `reelix.accessToken`      | String | `ApiClient.saveTokens()`        |
| `reelix.refreshToken`     | String | `ApiClient.saveTokens()`        |
| `reelix.avatar.{userId}`  | String | `authStore.setAvatarPath()`     |

`authStore.bootstrap()` runs before `runApp` and rehydrates from these.

---

## 13. Build order

Implement in this order — each step unlocks the next:

1. `config.dart` constants + endpoint switch from vidlink.pro to videasy
2. `ApiClient` (Dio + token refresh interceptor)
3. `AuthStore` + `LoginPage` + routing gate in `main.dart`
4. `HistoryStore` + wire `record(...)` into existing webview + native player
5. `WatchlistStore` + bookmark button on detail pages
6. `TvDetailStore` + episode-picker UI in TV detail page
7. `ProfilePage` + `LibraryPage` + `AvatarPicker` + `RootShell`
8. Stream extraction in webview → native player handoff (§9) if missing
9. Remote-control key bindings on native player (§10)
10. Responsive scaling sweep (§11)

---

## 14. Acceptance criteria

- Login persists across app restart; bootstrap calls `/me` on launch.
- Bookmark button on movie / TV detail toggles watchlist server-side and
  reflects immediately in Library and Profile previews.
- Continue Watching row appears on Profile and matches what was actually
  played (progress > 30 s, not completed).
- TV detail page lets you pick season then episode entirely with D-pad;
  selecting an episode launches playback at the right `s/e` URL.
- History records every 10–15 s during playback and once on player exit.
- Native player is fully remote-controllable: arrows seek, OK plays/pauses,
  BACK exits, media keys work.
- Home, Library, Profile look proportionally identical at 1080p, 2K, and 4K.
- All Reelix calls survive a 401 (auto-refresh + retry once, then logout if
  refresh fails).

---

## 15. Caveats

- `shouldInterceptRequest` is Android-only. tvOS would need a different
  capture path — out of scope here.
- Embeds may need a source pick + Play tap before they fire any manifest
  request; the webview must remain visible & D-pad-navigable until capture.
- Some streams sign URLs with short TTL; if native player errors >30 s
  after extraction, re-trigger the webview extraction step rather than
  retrying the stale URL.
- WebVTT subtitles must be fetched with the same headers as the stream;
  CDN otherwise 403s.

Implement, run `flutter analyze`, and verify the acceptance criteria above
before reporting done.
