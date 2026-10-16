# Project TODO

## 1. Response Schema & Compatibility Cleanup
- [ ] **Remove Backward Compatibility in Paginated Responses**:
  - Deprecate and remove redundant `results` field from [`PaginatedMovieResponse`](file:///home/mukes/dev/movies/backend/models.py) and [`LaneMoviesResponse`](file:///home/mukes/dev/movies/backend/models.py).
  - Standardize all backend responses on `items`.
  - Remove `sync_items_and_results` `@model_validator`.
  - Update frontend parsers across mobile and TV apps to read `items` uniformly.

## 2. Playback & Streaming Architecture
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

## 3. Route & API Architecture
- [ ] **Unify `/search` and `/discover` Endpoints**:
  - Merge the dual route aliases (`@router.get("/search")` and `@router.get("/discover")`) into a single consolidated browsing/search endpoint (e.g. `/api/v1/movies/catalog` or unified `/search`).
  - Standardize request query schema across text query, genre IDs, year filters, and sort orders.

## 4. Ratings, Cloud DB & Metadata Enrichment
- [ ] **Move IMDb Rating Enrichment to GitHub Workflow**:
  - Create a recurring GitHub Actions workflow (`.github/workflows/sync_imdb_ratings.yml`) to download `title.ratings.tsv.gz` from IMDb datasets on schedule.
  - Automate ingestion and deployment without consuming local host resources or manual execution.
- [ ] **Store IMDb Ratings in Cloud DB**:
  - Migrate ratings from local disk SQLite (`catalog.db`) to a managed/serverless cloud database (e.g. Turso / libSQL, Supabase Postgres, Neon, or Cloudflare D1).
  - Enable cloud-deployed backend instances to read ratings fast via connection pool or read-replica without bundling a 1.7M-row local database file.
- [ ] **IMDb Rating Fetch for All Movies**:
  - Uniformly enrich ratings and vote counts across:
    - Trakt lists and collections.
    - Curated catalog lanes and recommendations.
    - Person/actor filmographies.
    - Direct and fallback TMDb searches.
- [ ] **Vote Count Display in Frontend & Return from Backend**:
  - Add `vote_count: int = 0` to [`MovieSummary`](file:///home/mukes/dev/movies/backend/models.py).
  - Populate `vote_count` across all summary constructors (`from_tmdb`, `from_catalog`).
  - Update frontend movie models and card widgets to render formatted vote counts (e.g. `★ 8.2 (1.2k)`).

## 5. Pagination & Result Boundaries
- [ ] **Add End of Results Marker & Upstream Page Awareness**:
  - Replace brittle `len(items) >= safe_limit` heuristic with upstream `page >= total_pages` checks from TMDb and Trakt headers.
  - Implement an explicit end-of-results indicator in API response payloads (`is_last_page` or terminal `has_more: false`) so clients render end markers reliably without premature termination.

## 6. List Features & Chronological Order
- [ ] **Filtering in Lists**:
  - Add filtering parameters (`genre`, `year`, `language`, `sort_by`) to list endpoints (`GET /api/v1/movies/lists/{list_id}/items`).
  - Enable local/upstream filtering inside Trakt user lists and custom curated collections.
- [ ] **Preserve Chronological Order & Per-Season/Episode Entries in Lists**:
  - Eliminate aggressive `seen_keys` deduplication in [`backend/services/trakt.py`](file:///home/mukes/dev/movies/backend/services/trakt.py) that currently strips repeated TV shows.
  - Support franchise lists (e.g. Marvel Cinematic Universe chronological order) where distinct seasons or episodes of the same show appear interspersed between movies.

## 7. Frontend UI / UX Components
- [ ] **Move "To Top of Page" Button into Grid Widget**:
  - Refactor [`MovieGrid`](file:///home/mukes/dev/movies/mobile_app/lib/widgets/movie_grid.dart) to encapsulate the scroll-to-top floating button and scroll listeners internally.
  - Remove duplicate floating action button implementations from [`search_screen.dart`](file:///home/mukes/dev/movies/mobile_app/lib/screens/search_screen.dart) and [`list_movies_screen.dart`](file:///home/mukes/dev/movies/mobile_app/lib/screens/list_movies_screen.dart).
- [ ] **Anime-Specific Homepage Dashboard**:
  - Add dedicated Anime dashboard view / lanes (e.g. "Trending Anime", "Top Airing Series", "All-Time Classic Movies", "Shonen & Action").
  - Filter using TMDb animation genre (`genre_id: 16`) + Japanese language (`ja`), or dedicated Trakt anime collections.
- [ ] **Multi-Audio Track Selection & Support**:
  - Audio track switcher in the video player for streams containing multiple embedded audio channels (e.g. Tamil, English, Hindi dubs).
  - Accurate language tagging and stream track enumeration from demuxer metadata.

## 8. Client-Side Cache Management
- [ ] **Cache Management of Backend Returned Items on Client Side**:
  - Implement a persistent local cache layer (e.g. Hive, SQLite, or SharedPreferences in `shared_core`) for:
    - Dashboard lane feeds (instant cold start).
    - Movie details and season listings.
    - Search queries and Trakt lists.
  - Add configurable TTL and cache invalidation policies (e.g. background stale-while-revalidate).

## 9. Watch State & Continuity
- [ ] **Cross-Device Watch State Management (Auth-Backed)**:
  - User account system (Username/User ID & Password authentication + token issuance) for profile synchronization.
  - Cloud-synced playback resume timestamps, completed watch states, favorites, and "Continue Watching" lane shared seamlessly between mobile and TV apps.

## 10. Infrastructure & Hosting
- [ ] **Explore Free Hosting Services for Backend**:
  - Benchmark and test deployment options for FastAPI backend on free/low-cost tiers:
    - Koyeb (Docker / Python service).
    - Render (Web service free tier).
    - Fly.io (Micro VM).
    - Hugging Face Spaces (Docker / FastAPI free CPU tier).
    - Oracle Cloud Always Free (ARM Ampere VM).

## 11. Authoritative Data Integrity & Fallback Elimination
- [ ] **Remove All Fallbacks & Rely Strictly on Authoritative Data**:
  - Eliminate all fallback chains and synthetic/placeholder data across backend and frontend:
    - **Search Fallbacks**: Stop cascading from Trakt search to TMDb search; query the authoritative index directly.
    - **Media Type Fallbacks**: Remove cross-media guessing in `get_details` (e.g. falling back to Movie when TV fails, or vice versa); require explicit `media_type` and return clean 404 if not found.
    - **Client-Side Metadata Fallbacks**: Remove `fallbackMovie` injections and mock metadata generation in `shared_core` (`MediaService`).
    - **Catalog & Stream Fallbacks**: Eliminate mock/static fallback catalogs; return verified real-time data or explicit empty states instead of masked fallback responses.

## 12. Backend Production Hardening
- [ ] **Remove Debug & Diagnostic Headers**:
  - Strip custom diagnostic headers (`X-Cache-Status`, `X-Cache-TTL`) across all routes in `backend_revised` before production release.