# Project Handoff — Cloudflare Backend & Catalog Architecture

## 1. Current State & Recent Changes

- **Backend Migration**: Fully migrated from Python FastAPI to Cloudflare Workers (`backend_revised`) using Hono, Cloudflare D1 (`movies-catalog`), and Cloudflare KV (`CONFIG_KV`).
- **Dynamic KV Configuration**:
  - `rating_rules`, `dashboards`, `dashboard:tamil`, and `sync_lanes` live in Cloudflare KV.
  - Managed by [`ConfigService`](file:///home/mukes/dev/movies/backend_revised/src/services/config.ts) using the Cloudflare Cache API (`caches.default`, 1-hour TTL) with bundled JSON fallbacks in `backend_revised/src/config/`.
- **Sync Pipeline**:
  - Modularized into `backend_revised/scripts/sync/` (`client.py`, `config.py`, `lanes.py`, `rating.py`, `sql.py`).
  - Automated via scheduled GitHub Actions workflow [`.github/workflows/sync_catalog.yml`](file:///.github/workflows/sync_catalog.yml) running daily at midnight UTC.
- **Git History & Secrets**:
  - Purged hardcoded Cloudflare account identifiers from git history.
  - Secrets (`MDBLIST_API_KEY`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_KV_NAMESPACE_ID`) configured via environment variables and GitHub Secrets.
- **Streaming Pipeline & Language Priority**:
  - Updated `HDHUB_MANIFEST_URL` secret to live working instance with direct PixelDrain/HubCloud links.
  - Implemented language-aware stream ranking in [`stream_parser.ts`](file:///home/mukes/dev/movies/backend_revised/src/services/stream_parser.ts) and [`streams.ts`](file:///home/mukes/dev/movies/backend_revised/src/services/streams.ts).
  - Added query parameter `original_language` (`orig_lang`) to `/api/v1/streams/:media_type/:imdb_id` with zero D1 querying overhead.
  - Priority rule: Indian regional media (`hi`, `ta`, `te`, `ml`, `kn`, etc.) forces **Tamil** to top priority, then original language. Non-Indian media (anime `ja`, `ko`, `en`, etc.) prioritizes the title's **original language**.
  - Tiered scraping: Tier 1 (**HDHub** & **PlavioHD**); Tier 2 fallback (**PenguPlay** & **NoTorrent** if Tier 1 yields < 15 streams). Provider evaluation concluded Kurage (missing pre-2000s anime back-catalog) and YukiStreams (direct HTTP down without Debrid) removed.
- **Profanity & Spam Filtering**:
  - Integrated [`ProfanityService`](file:///home/mukes/dev/movies/backend_revised/src/services/profanity.ts) using `leo-profanity` in `backend_revised`.
  - Filters out explicit user spam lists, slugs, and profane search queries in [`ListsService`](file:///home/mukes/dev/movies/backend_revised/src/services/lists.ts) and [`TraktSearchService`](file:///home/mukes/dev/movies/backend_revised/src/services/traktsearch.ts).
  - Whitelists legitimate cinema terms (`snatch`, `bastard`, `hell`, `damn`) and relies on TMDB's `adult: true` flag to prevent false-positive blocking of mature titles (*Deadpool*, *The Boys*).
- **TV App Focus & RAM Optimization**:
  - Refactored [`HomeScreen`](file:///home/mukes/dev/movies/tv_app/lib/screens/home_screen.dart) and lane widgets ([`TvMovieLane`](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_movie_lane.dart), [`TvContinueWatchingLane`](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_continue_watching_lane.dart), [`TvActorsLane`](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_actors_lane.dart)).
  - Configured [`TvUnifiedHeaderStrip`](file:///home/mukes/dev/movies/tv_app/lib/widgets/tv_unified_header_strip.dart) with self-centering `autoEnsureVisible: true`, `scrollAlignment: 0.20`, and 200ms `Curves.easeOutCubic` curve on the strip's own context, eliminating the UP/DOWN centering asymmetry and ensuring both header and cards are centered in the viewport.
  - Implemented `AutomaticKeepAliveClientMixin` (`wantKeepAlive = true`) on [`TvMovieLane`](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_movie_lane.dart) to preserve focus trees and scroll offsets across vertical scrolls and tab changes.
  - Fixed D-pad title lock & viewport targeting: Stored `_lastFocusedIndex` in `PageStorage`, verified `node.parent != null` (active in focus tree), and added dynamic viewport-aware fallback `(_scrollController.offset / itemWidth).round()` to ensure Down from a header immediately focuses the visible on-screen card.
  - Set `clipBehavior: Clip.none` on horizontal `ListView.builder` carousels across [`TvMovieLane`](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_movie_lane.dart), [`TvContinueWatchingLane`](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_continue_watching_lane.dart), and [`TvActorsLane`](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_actors_lane.dart) so the 1.08x scale pop-up and top highlight border/halo are never clipped by the scroll viewport.
  - Added 140ms repeat throttling to card navigation in [`TvMovieLane`](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_movie_lane.dart), [`TvContinueWatchingLane`](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_continue_watching_lane.dart), and [`TvActorsLane`](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_actors_lane.dart).
  - Debounced poster loading by 140ms in [`TvFocusCard`](file:///home/mukes/dev/movies/tv_app/lib/widgets/tv_focus_card.dart) for unfocused cards so holding D-pad right does not flood Flutter's FIFO image connection/decode queue.
  - Replaced root `setState()` in scroll listener with `ValueNotifier<bool>` on Billboard.
  - Refactored [`TvBillboard`](file:///home/mukes/dev/movies/tv_app/lib/widgets/home/tv_billboard.dart): Removed separate "Play Now" and "Details" buttons, making the entire billboard a focusable card button with animated dimming (unfocused) / brightening (focused) and D-pad Left/Right cycling through featured candidates.
  - Purged untracked desktop `tv_app/linux/` embedder files.

---

## 2. Infrastructure Bindings

- **Live Worker URL**: `https://backend-revised.mkdummy2025.workers.dev` (Version `6e693c2e-fd5b-44bc-be5d-7552d7bd89b8`)
- **D1 Database**: `movies-catalog` (`ce5096c4-ec8a-463d-890e-493c92d5f580`)
- **KV Namespace**: `CONFIG_KV` (`4d8a8b30e668412596ca7b9cabfecdb4`)
- **Worker Configuration**: [wrangler.toml](file:///home/mukes/dev/movies/backend_revised/wrangler.toml)

---

## 3. Active Next Steps

1. **Unified Filterable Grid (`TvFilterableGrid`)**:
   - Construct reusable 70/30 filterable grid widget replacing duplicated sliver and filter drawer logic across [`LaneGridScreen`](file:///home/mukes/dev/movies/tv_app/lib/screens/lane_grid_screen.dart) and [`SearchScreen`](file:///home/mukes/dev/movies/tv_app/lib/screens/search_screen.dart).
2. **Modal Search Trigger**:
   - Replace embedded `TextField` on TV with search dialog modal to eliminate remote caret-trapping and empty-backspace bugs.
