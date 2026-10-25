# Project TODO

## Completed Tasks
- [x] **Multi-Dashboard Route Architecture**:
  - Implemented `/api/v1/dashboard/:dashboard_id` and `/api/v1/dashboard/:dashboard_id/lanes/:lane_id` in [`backend_revised`](file:///home/mukes/dev/movies/backend_revised/src/routes/dashboard.ts).
  - Parallel lane resolution with `Promise.all` and strict 404 handling.
- [x] **Move Catalog & IMDb Rating Enrichment to GitHub Workflow**:
  - Created recurring GitHub Actions workflow ([`.github/workflows/sync_catalog.yml`](file:///home/mukes/dev/movies/.github/workflows/sync_catalog.yml)) running [`sync_catalog_to_d1.py`](file:///home/mukes/dev/movies/backend_revised/scripts/sync_catalog_to_d1.py).
  - Populates Cloudflare D1 with authentic IMDb ratings and vote counts automatically.
- [x] **Store IMDb Ratings in Cloudflare D1 Database**:
  - Migrated ratings and titles to Cloudflare D1 (`movies-catalog`), replacing local disk SQLite.
  - Enabled Cloudflare Workers fast-path queries directly against `v_catalog` view.
- [x] **IMDb Rating Fetch for All Movies**:
  - Enriched ratings and vote counts across D1 catalog and live search via on-demand MDBList batching in `backend_revised`.
- [x] **Backend Vote Count Return**:
  - Populated `vote_count` across all summary responses in [`backend_revised`](file:///home/mukes/dev/movies/backend_revised/src/types.ts).
- [x] **Upstream Search Pagination & Lane Bounds**:
  - Implemented `has_more = page < traktResult.total_pages` using Trakt `x-pagination-page-count` in [`search.ts`](file:///home/mukes/dev/movies/backend_revised/src/routes/search.ts).
  - Implemented `has_more` and bounds checking on paginated lane routes (`/api/v1/dashboard/:dashboard_id/lanes/:lane_id`).
- [x] **Support TV Series in Cloudflare D1 Database**:
  - Added `media_type` (`'movie' | 'tv'`) column to `movies` and wired into `v_catalog` view.
  - Enabled fast-path lookups and async write-through for TV series concise summaries in `backend_revised`.

---

## Incomplete Tasks

### 1. Frontend Integration & UI Components
- [ ] **Wire New Dashboard Endpoints**:
  - Update `shared_core`, `mobile_app`, and `tv_app` to call `/api/v1/dashboard/:dashboard_id` and `/api/v1/dashboard/:dashboard_id/lanes/:lane_id`.
- [ ] **Vote Count Display in Frontend**:
  - Update frontend movie models and card widgets to render formatted vote counts (e.g. `★ 8.2 (1.2k)`).
- [ ] **Move "To Top of Page" Button into Grid Widget**:
  - Refactor [`MovieGrid`](file:///home/mukes/dev/movies/mobile_app/lib/widgets/movie_grid.dart) to encapsulate the scroll-to-top floating button and scroll listeners internally.
  - Remove duplicate floating action button implementations from [`search_screen.dart`](file:///home/mukes/dev/movies/mobile_app/lib/screens/search_screen.dart) and [`list_movies_screen.dart`](file:///home/mukes/dev/movies/mobile_app/lib/screens/list_movies_screen.dart).
- [ ] **Anime-Specific Homepage Dashboard**:
  - Add dedicated Anime dashboard view / lanes (e.g. "Trending Anime", "Top Airing Series", "All-Time Classic Movies", "Shonen & Action").
  - Filter using TMDb animation genre (`genre_id: 16`) + Japanese language (`ja`), or dedicated Trakt anime collections.
- [ ] **Multi-Audio Track Selection & Support**:
  - Audio track switcher in the video player for streams containing multiple embedded audio channels (e.g. Tamil, English, Hindi dubs).
  - Accurate language tagging and stream track enumeration from demuxer metadata.

### 2. Playback & Streaming Architecture
- [ ] **Client-Side Stream Link Probing**:
  - Offload live stream availability, latency, and segment probing from backend scrapers to client devices (mobile & TV).
  - Backend returns candidate streams immediately without blocking on network probes.
  - Client-side video player engine (`media_kit`) probes and selects optimal candidate streams asynchronously.
- [ ] **Stream Progress Feedback & Fallback Resilience**:
  - Maintain SSE stream progress broadcasting for live scraping feedback.
  - Implement automatic fallback between Stremio providers (PenguPlay, HdHub) and direct resolver sources.
- [ ] **Client-Side Stream Speed & Bandwidth Calculation**:
  - Measure real-time download throughput and chunk latency during initial candidate stream probing in `media_kit`.
  - Compare measured bandwidth against candidate stream `bitrate_kbps` / file size to evaluate buffer health and select optimal stream quality automatically.
  - Expose live playback speed indicators (e.g. `14.2 MB/s`, estimated buffer runway) in the player UI.
- [ ] **Embedded Subtitle Track Selection**:
  - Support discovery and selection of internal/embedded subtitle tracks (muxed inside MP4/MKV video containers) alongside external OpenSubtitles VTT/SRT tracks in the player HUD.

### 3. Route & API Architecture
- [ ] **English Dashboard & Additional Catalog Profiles**:
  - Add English dashboard configuration to `lanes.ts` and sync catalog to D1.
- [ ] **Curated & Trakt Lists Migration**:
  - Port `/lists/{list_id}/items` to `backend_revised` with upstream `page >= total_pages` checks from Trakt headers.
- [ ] **Unify `/search` and `/discover` Endpoints**:
  - Merge the dual route aliases (`@router.get("/search")` and `@router.get("/discover")`) into a single consolidated browsing/search endpoint (e.g. `/api/v1/movies/catalog` or unified `/search`).
  - Standardize request query schema across text query, genre IDs, year filters, and sort orders.

### 4. Response Schema & Compatibility Cleanup
- [ ] **Remove Backward Compatibility in Paginated Responses**:
  - Deprecate and remove redundant `results` field from [`PaginatedMovieResponse`](file:///home/mukes/dev/movies/backend/models.py) and [`LaneMoviesResponse`](file:///home/mukes/dev/movies/backend/models.py).
  - Standardize all backend responses on `items`.
  - Remove `sync_items_and_results` `@model_validator`.
  - Update frontend parsers across mobile and TV apps to read `items` uniformly.

### 5. List Features & Chronological Order
- [ ] **Filtering in Lists**:
  - Add filtering parameters (`genre`, `year`, `language`, `sort_by`) to list endpoints (`GET /api/v1/movies/lists/{list_id}/items`).
  - Enable local/upstream filtering inside Trakt user lists and custom curated collections.
- [ ] **Preserve Chronological Order & Per-Season/Episode Entries in Lists**:
  - Eliminate aggressive `seen_keys` deduplication in [`backend/services/trakt.py`](file:///home/mukes/dev/movies/backend/services/trakt.py) that currently strips repeated TV shows.
  - Support franchise lists (e.g. Marvel Cinematic Universe chronological order) where distinct seasons or episodes of the same show appear interspersed between movies.

### 6. Client-Side Cache Management
- [ ] **Cache Management of Backend Returned Items on Client Side**:
  - Implement a persistent local cache layer (e.g. Hive, SQLite, or SharedPreferences in `shared_core`) for:
    - Dashboard lane feeds (instant cold start).
    - Movie details and season listings.
    - Search queries and Trakt lists.
  - Add configurable TTL and cache invalidation policies (e.g. background stale-while-revalidate).

### 7. Watch State & Continuity
- [ ] **Cross-Device Watch State Management (Auth-Backed)**:
  - User account system (Username/User ID & Password authentication + token issuance) for profile synchronization.
  - Cloud-synced playback resume timestamps, completed watch states, favorites, and "Continue Watching" lane shared seamlessly between mobile and TV apps.

### 8. Authoritative Data Integrity & Fallback Elimination
- [ ] **Remove All Fallbacks & Rely Strictly on Authoritative Data**:
  - Eliminate all fallback chains and synthetic/placeholder data across backend and frontend:
    - **Search Fallbacks**: Stop cascading from Trakt search to TMDb search; query the authoritative index directly.
    - **Media Type Fallbacks**: Remove cross-media guessing in `get_details` (e.g. falling back to Movie when TV fails, or vice versa); require explicit `media_type` and return clean 404 if not found.
    - **Client-Side Metadata Fallbacks**: Remove `fallbackMovie` injections and mock metadata generation in `shared_core` (`MediaService`).
    - **Catalog & Stream Fallbacks**: Eliminate mock/static fallback catalogs; return verified real-time data or explicit empty states instead of masked fallback responses.

### 9. Infrastructure, Hosting & Hardening
- [ ] **Deploy `backend_revised` to Cloudflare**:
  - Run `npx wrangler deploy` once validated with frontend.
- [ ] **Remove Debug & Diagnostic Headers**:
  - Strip custom diagnostic headers (`X-Cache-Status`, `X-Cache-TTL`) across all routes in `backend_revised` before production release.
- [ ] **Explore Free Hosting Services for Legacy Backend**:
  - Benchmark options for remaining scraper services (Koyeb, Render, Fly.io, Hugging Face Spaces, Oracle Cloud Always Free).