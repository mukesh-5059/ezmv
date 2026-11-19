# Handoff: Xiaomi Mi TV 1GB RAM Optimization & Trakt Integration

## Context & Hardware Specs
- **Device**: Xiaomi Mi TV 4A/4C (MiTV-AXSO0 series).
- **SoC / CPU**: Amlogic `txlx` (4× ARM Cortex-A53 @ 1.2GHz).
- **GPU**: ARM Mali-450 MP (OpenGL ES 2.0 only, weak fill-rate, no Vulkan).
- **RAM**: 1GB (1,014,724 kB total, ~100–250MB usable headroom).
- **OS / Display**: Android 9.0 Pie (API 28), 1280×720 (720p @ 213 dpi).
- **Strict User Directives**:
  - NO git commits, NO git pushes.
  - NO commands targeting physical Mi TV (`192.168.29.93:5555`).
  - Zero focus amnesia across all D-pad interactions.

---

## Current Status & Completed Milestones

### Milestone 1 (`shared_core`) — COMPLETE & VERIFIED (174/174 Tests Passed)
- [trakt_list_summary.dart](file:///home/mukes/dev/movies/shared_core/lib/models/trakt_list_summary.dart): Full Trakt list serialization with `description`, `userName`, `slug`, `sortBy`, `sortHow`, `itemCount`, `likes`, and `copyWith`.
- [movie_summary.dart](file:///home/mukes/dev/movies/shared_core/lib/models/movie_summary.dart) & [movie_details.dart](file:///home/mukes/dev/movies/shared_core/lib/models/movie_details.dart): Enriched with `runtime`, `originalLanguage`, and `SeasonSummary`.
- [list_sorter.dart](file:///home/mukes/dev/movies/shared_core/lib/services/list_sorter.dart): Fast sorting engine supporting `rank`, `added`, `title`, `released`, `popularity`, `runtime`, and `votes` (asc/desc).
- [api_client.dart](file:///home/mukes/dev/movies/shared_core/lib/api/api_client.dart): Trakt list search, popular lists, item retrieval with sorting and pagination, plus route fallbacks. Cleaned unused element warnings.

### Milestone 2 (Memory & Focus Primitives) — COMPLETE ON DISK
- [tv_memory.dart](file:///home/mukes/dev/movies/tv_app/lib/utils/tv_memory.dart): Capped global image cache at 25MB (`maxCacheSizeBytes = 25 * 1024 * 1024`, `maxCacheCount = 35`).
- [theme.dart](file:///home/mukes/dev/movies/tv_app/lib/theme.dart): Removed Mali-450 GPU-killing Gaussian blur shadows (`blurRadius: 0`, crisp borders). Shortened `focusDuration` to 110ms (`Duration(milliseconds: 110)`) to finish before 140ms D-pad key repeat intervals.
- [movie_summary.dart](file:///home/mukes/dev/movies/shared_core/lib/models/movie_summary.dart), [continue_watching_entry.dart](file:///home/mukes/dev/movies/shared_core/lib/models/continue_watching_entry.dart), [actor_profile.dart](file:///home/mukes/dev/movies/shared_core/lib/models/actor_profile.dart), & [tv_episode.dart](file:///home/mukes/dev/movies/shared_core/lib/models/tv_episode.dart): Switched TMDb poster and actor profile URLs to `w185` and episode still URLs to `w185`, cutting payload size and texture footprint across all card shelves.
- [tv_focus_card.dart](file:///home/mukes/dev/movies/tv_app/lib/widgets/tv_focus_card.dart), [details_screen.dart](file:///home/mukes/dev/movies/tv_app/lib/screens/details_screen.dart), [tv_actors_lane.dart](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_actors_lane.dart), [actor_lane.dart](file:///home/mukes/dev/movies/tv_app/lib/widgets/actor_lane.dart), & [cast_carousel.dart](file:///home/mukes/dev/movies/tv_app/lib/widgets/cast_carousel.dart): Enforced 1:1 downsampling (`memCacheWidth`/`memCacheHeight` matching exact widget bounds: 80x80, 88x88, 96x96, 222x125), zeroed fade durations, and removed `imageBuilder` / `debugPrint` GC thrash.
- [source_orchestrator.dart](file:///home/mukes/dev/movies/shared_core/lib/services/source_orchestrator.dart), [tv_billboard.dart](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_billboard.dart), [details_screen.dart](file:///home/mukes/dev/movies/tv_app/lib/screens/details_screen.dart), [player_screen.dart](file:///home/mukes/dev/movies/tv_app/lib/screens/player_screen.dart), & [player_dialogs.dart](file:///home/mukes/dev/movies/tv_app/lib/widgets/player_dialogs.dart): Completely purged all stream scraper and image debug logs (`[IMG:...`, `[$extractorId]...`, `[SourceOrchestrator]...`) to eliminate console I/O stalls on Android TV.

### Milestone 3 (Home Screen Virtualization & Billboard) — COMPLETE ON DISK
- [home_screen.dart](file:///home/mukes/dev/movies/tv_app/lib/screens/home_screen.dart): Converted eager `ListView(children: [...])` to `ListView.builder` with `cacheExtent: 400` and `findChildIndexCallback`, reducing widget allocations by ~73%.
- [tv_movie_lane.dart](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_movie_lane.dart): Set `wantKeepAlive => false` to release offscreen lane memory while preserving horizontal scroll and focused card index in `PageStorageKey`.
- [tv_billboard.dart](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_billboard.dart): Shortened cross-fade from 700ms to 150ms to eliminate dual 720p texture blending stalls on Mali-450.
- [details_screen.dart](file:///home/mukes/dev/movies/tv_app/lib/screens/details_screen.dart): Added `PageStorageKey` for seasons and episodes shelves.

### Milestone 4 (Player Dialogs Normalization & Episode Selector Bugfix) — COMPLETE ON DISK
- [player_dialogs.dart](file:///home/mukes/dev/movies/tv_app/lib/widgets/player_dialogs.dart) & [subtitle_picker_dialog.dart](file:///home/mukes/dev/movies/tv_app/lib/widgets/subtitle_picker_dialog.dart):
  - Normalized focused item background to softened crimson with alpha (`TVTheme.primary.withValues(alpha: 0.25)`), paired with a crisp 2px white border and white typography across all player dialogs.
  - Zeroed out all `blurRadius` values (`blurRadius: 0, spreadRadius: 1`) across all dialog tiles and panels for pure 0-blur hardware rendering on Mali-450 GPU.
  - Removed season selector pills from `EpisodesPickerDialog`, displaying a dedicated `SEASON $X • $Y EPISODES` count header and focusing directly onto current season episodes.
  - Added bottom prompt (`Press Back to close`) across all dialogs.
- [api_client.dart](file:///home/mukes/dev/movies/shared_core/lib/api/api_client.dart) & [player_screen.dart](file:///home/mukes/dev/movies/tv_app/lib/screens/player_screen.dart):
  - Fixed infinite red loading spinner in `EpisodesPickerDialog`: `api_client.dart` now transparently resolves IMDb IDs (`tt...`) via `resolveMovies` before calling numeric TMDb endpoints, preventing 400 Bad Request errors.
  - Added `try-catch-finally` to `_EpisodesPickerDialogState._loadSeason` to ensure `_isLoadingSeason` is always cleared even on network timeouts.
  - Preloaded seasons/episodes in `_showEpisodesDialog()` if `_currentDrawerSeason` is null.

---

## Preserved Blueprints & Prompts (Ready for Resume)
All 3 technical audit reports and the explorer prompts are persisted in the repo under `blueprints/`:
1. [m4_details_player_blueprint.md](file:///home/mukes/dev/movies/blueprints/m4_details_player_blueprint.md): Player buffer 16MB, 2 decode threads, episode focus restoration.
2. [m4_search_blueprint.md](file:///home/mukes/dev/movies/blueprints/m4_search_blueprint.md): Search grid virtualization, safe focus handover between dialog and cards.
3. [m4_actor_blueprint.md](file:///home/mukes/dev/movies/blueprints/m4_actor_blueprint.md): 160x160 avatar downsampling, zero-blur halo on actor cards.
4. [explorer_prompts.md](file:///home/mukes/dev/movies/blueprints/explorer_prompts.md): Exact prompts used to instruct the explorer agents.

---

## Action Plan for Tomorrow
1. **Apply Milestone 4 Code Edits**:
   - `tv_app/lib/screens/player_screen.dart`: reduce buffer from 32MB to 16MB, set `vd-lavc-threads` to 2.
   - `tv_app/lib/screens/actor_screen.dart` & `tv_app/lib/widgets/actor_lane.dart`: update avatar image widgets to `CachedNetworkImage` downsampled to `160x160`.
   - `tv_app/lib/screens/search_screen.dart`: ensure grid virtualization and focus safety guards.
   - `tv_app/lib/widgets/cast_carousel.dart`: zero-blur focus shadows.
2. **Execute Milestone 5 Final Verification**:
   - Run `dart analyze` across `shared_core` and `tv_app` (ensure 0 errors).
   - Run `flutter test` across all unit/widget tests.
