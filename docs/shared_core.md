# Shared Core (`shared_core`)

`shared_core` is the foundational Dart package shared across client applications (Android TV, mobile, and CLI tools). It provides platform-agnostic data models, backend API clients, local persistence, an embedded QuickJS scraper orchestrator, and an intelligent multi-stage stream ranker.

---

## 1. Package Overview & Architecture

`shared_core` centralizes all core business logic, preventing code duplication between different frontend form factors.

```text
shared_core/
├── lib/
│   ├── api/                  # Backend HTTP & Server-Sent Events (SSE) Client
│   │   └── api_client.dart
│   ├── models/               # Strongly-typed immutable data models
│   │   ├── actor_profile.dart
│   │   ├── cast_member.dart
│   │   ├── continue_watching_entry.dart
│   │   ├── dashboard.dart
│   │   ├── dashboard_lane.dart
│   │   ├── genre.dart
│   │   ├── movie_details.dart
│   │   ├── movie_summary.dart
│   │   ├── paginated_response.dart
│   │   ├── stream_progress_event.dart
│   │   ├── stream_source.dart
│   │   ├── subtitle_track.dart
│   │   ├── trakt_list_summary.dart
│   │   ├── tv_episode.dart
│   │   └── tv_season.dart
│   ├── services/             # Core engines: scraping, ranking, sorting, settings
│   │   ├── list_sorter.dart
│   │   ├── settings_service.dart
│   │   ├── source_orchestrator.dart
│   │   ├── stream_priority.dart
│   │   └── stream_ranker.dart
│   ├── storage/              # Local device storage & preferences
│   │   └── storage_service.dart
│   └── shared_core.dart      # Barrel export
└── pubspec.yaml
```

---

## 2. Core Functional Modules

### 2.1 Data Models (`lib/models/`)
All models feature `fromJson` / `toJson` serialization, immutability, and hardware-conscious getters:

- **`MovieSummary`**: Compact media representation for grids and carousels. Provides `posterUrl` downsampled to TMDb `w185` (down from `w500`) to save bandwidth and GPU texture memory, and `backdropUrl` (`w1280`).
- **`MovieDetails`**: Comprehensive metadata model containing synopsis, certification, IMDb/TMDb ratings, runtime, genre tags, cast members (`CastMember`), and seasons (`SeasonSummary`).
- **`TvSeason` & `TvEpisode`**: Full episodic metadata. `TvEpisode` calculates release status (`isReleased`, `isUpcoming`), formatted runtimes, and downsampled still URLs (`w185`).
- **`ContinueWatchingEntry`**: State snapshot of in-progress media containing playback position, duration, last updated timestamp, progress ratio (`positionMs / durationMs`), and a 92% completion threshold (`isCompleted`). Directly converts to `MovieSummary`.
- **`StreamSource` & `StreamProgressEvent`**: Scraped media link contracts including quality (4K, 1080p, 720p), provider ID, request headers (Referer/User-Agent), priority weight, audio languages, file size, and direct stream flags. Progress events track live discovery stages.
- **`ActorProfile` & `CastMember`**: Filmography models containing popular/recent titles, biographies, and TMDb `w185` profile URLs.
- **`Dashboard` & `DashboardLane`**: Multi-tab layout configuration supporting various visual styles (`portrait`, `landscape`, `banner`, `actor_circle`) and server-driven pagination.
- **`TraktListSummary`**: Trakt curation model supporting list slug, item counts, likes, and sorting descriptors.

---

### 2.2 Backend API Client (`lib/api/api_client.dart`)
A high-resilience HTTP client communicating with the backend API:

- **ID Resolution (`resolveMovies`)**: Automatically resolves IMDb IDs (`tt...`) to numeric TMDb IDs before invoking endpoints that require numeric parameters, preventing 400 Bad Request errors.
- **Dashboard & Catalog**:
  - `getDashboard(id)`: Fetches categorized dashboard tabs with offline fallback handling.
  - `getLaneContent(dashboardId, laneId, {page})`: Paginated lane contents.
  - `getMovieDetails(id, {mediaType})`: Resolves metadata, cast, and related titles.
  - `getTvSeasonEpisodes(id, season)`: Retrieves full season episode lists.
- **Search & Discovery**:
  - `search(query, {mediaType, genre, year, page})`: Full-text search across titles and upstream catalogs.
  - `getTraktLists(...)` & `getTraktListItems(...)`: Fetches community and curated Trakt collections.
- **Real-Time Progressive Streaming (`getStreamsProgressive`)**:
  - Connects to backend Server-Sent Events (SSE) `/api/v1/streams/...` endpoint to stream discovered links progressively as scrapers finish upstream.

---

### 2.3 Scraper Orchestration & QuickJS Runtime (`lib/services/source_orchestrator.dart`)
A hybrid client-side scraping engine executing community Stremio addons and custom JavaScript extractors:

- **Embedded QuickJS Engine**: Executes JavaScript scrapers in isolated native C runtimes via `flutter_js`.
- **Zero-Poll Event-Driven Completion**:
  - Rather than relying on `flutter_js`'s buggy 20ms polling loop (`Timer.periodic`), scrapers communicate via native channel events (`sendMessage('ezmv_complete', ...)`).
  - Eliminates native C heap memory leaks ("Zombie Runtimes") and ensures instant completion resolution.
- **In-Memory Router Caching (`_planCache`)**:
  - Caches `BatchPlan` routes in memory by media type and language, avoiding the overhead of spinning up and tearing down a QuickJS instance on every plan query.
- **Generous Safety Watchdogs**:
  - **15s HTTP Request Timeout**: `_httpClient.send(req).timeout(const Duration(seconds: 15))` prevents hanging TCP sockets on slow/dead upstream servers.
  - **25s Scraper Watchdog**: Caps script execution at 25 seconds before safely cleaning up.
- **Cancellation Token Architecture**:
  - Exposes `cancel()` and `_isCancelled` flags. When a user cancels or exits mid-scrape, all active batch loops break immediately, in-flight HTTP requests drop, and QuickJS engines dispose cleanly.

---

### 2.4 Multi-Stage Stream Ranker (`lib/services/stream_ranker.dart` & `stream_priority.dart`)
Transforms a raw pool of candidate stream links into a verified, prioritized playback list:

- **Stream Priority Calculation (`StreamPriorityCalculator`)**:
  - Assigns dynamic weights based on resolution (4K, 1080p, 720p), audio language matching (preferred vs original language), provider reliability, and file size targets.
- **Two-Stage Health & Speed Verification**:
  1. **Stage 1: Health Gate**: Executes lightweight HTTP `HEAD` / byte-range requests to prune dead, expired, or 404 links.
  2. **Stage 2: Speed Probing**: Downloads timed byte chunks across candidate streams to calculate actual throughput in MB/s, filtering out buffering-prone hosts.

---

### 2.5 Local Storage Service (`lib/storage/storage_service.dart`)
Encapsulates `shared_preferences` persistence with synchronous in-memory caching:

- **Continue Watching**: Saves, retrieves, and updates watch progress milestones (`positionMs`, `durationMs`).
- **Completed Media Sync**: Caches completed status synchronously (`isCompletedSync`) to instantly show completion badges without UI flicker.
- **User Preferences**: Persists default audio languages, subtitle tracks, subtitle appearance (font size, color, background), and preferred streaming resolution.

---

### 2.6 In-Memory List Sorter (`lib/services/list_sorter.dart`)
A deterministic sorting utility used across search results and Trakt lists:
- Supports multi-attribute ordering: `rank`, `added`, `title`, `released`, `popularity`, `runtime`, and `votes` (ascending / descending).
- Handles null-safety and missing fields gracefully without mutating the original list.

---

## 3. How to Use `shared_core`

Add to `pubspec.yaml` in consumer packages:

```yaml
dependencies:
  shared_core:
    path: ../shared_core
```

Initialize preferences during app boot:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.instance.init();
  runApp(const MyApp());
}
```
