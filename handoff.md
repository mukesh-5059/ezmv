# Stream URL Resolution, Scrapers & Subtitles Pipeline — Handoff

## Summary & Current Architecture

The stream resolution, scraping, and subtitle subsystem is modularly separated between orchestrators, core services, and provider implementations:

```text
backend/
├── routes/
│   ├── movies.py             # Universal Search, Discover, Popular, and Details (with cast)
│   ├── streams.py            # Stream resolution and SSE progress broadcasting
│   └── subtitles.py          # Multi-language subtitle lookup (English prioritized)
├── services/
│   ├── catalog.py            # SQLite WAL catalog queries & fallback search
│   ├── subtitles.py          # SubtitlesService (OpenSubtitles v3, TTLCache, language sorting)
│   └── tmdb.py               # TMDBClient (with TTLCache, credits, external_ids)
├── scrappers/
│   ├── base.py               # MediaItem, StreamSource models
│   ├── manager.py            # ScraperManager (Dynamic min() TTL cache & SSE StreamBroadcaster)
│   └── providers/
│       ├── isaimini/         # Isaimini provider (Language Guard + Token Matcher + Resolver)
│       └── vidsrc/           # VidSrc provider (Playwright Firefox HLS extractor + fast-path info check)
└── data/                     # Ignored runtime databases & domain configs
    ├── catalog.db            # SQLite database with IMDb curated lanes
    ├── isaimini.db           # SQLite database for Isaimini path indexing
    ├── isaimini.json         # Active Isaimini mirror configuration
    └── vidsrc.json           # Primary VidSrc domain & mirrors reference
```

---

## 1. Dual-Provider Scraper Pipeline

1. **VidSrc (`backend/scrappers/providers/vidsrc/`)**:
   - Headless Playwright Firefox extractor (`HLSExtractorService`) with custom Gecko preferences.
   - Neutralizes `disable-devtool.js` with HTTP 200 empty stubs.
   - Fast pre-flight check via `/info/movie/{id}.json` to extract quality tags (`1080p`, `720p`, `CAM`) before launching browser.
   - Configured strictly via `backend/data/vidsrc.json`.

2. **Isaimini (`backend/scrappers/providers/isaimini/`)**:
   - Language Guard: Immediately exits non-Indian titles (`INDIAN_LANGUAGES = {"ta", "te", "hi", "ml", "kn"}`).
   - Multi-pattern tokenizer and `.php` gatekeeper URL resolver (`mv1.uptomkv.ch`).
   - Dynamic mirror resolution stored in `backend/data/isaimini.json`.

3. **Orchestrator (`backend/scrappers/manager.py`)**:
   - Concurrently executes scrapers via `asyncio.gather(..., return_exceptions=True)`.
   - Deduplicates stream URLs and sorts by stream priority.
   - Computes dynamic TTL: `min(s.ttl for s in streams if s.ttl)` (60s for empty, 7200s for VidSrc, 10 days for resolved direct links).
   - Emits real-time SSE progress events for client UI via `GET /api/v1/streams/?format=sse`.

---

## 2. Subtitles Integration

1. **Subtitles Endpoint**: `GET /api/v1/subtitles/?tmdb_id=...&media_type=...`
2. **Features**:
   - Resolves IMDb identifier and queries OpenSubtitles v3 API.
   - Normalizes ISO language codes and ranks **English subtitles first**.
   - Supports optional language filtering (`language=en`, `language=ta`).
   - 24-hour in-memory TTL caching.

---

## 3. Metadata & Cast Enrichment

- `GET /api/v1/movies/{media_type}/{tmdb_id}` requests `append_to_response=external_ids,credits`.
- Populates `cast: list[CastMember]` with `id`, `name`, `character`, and `profile_path`.
- Universal search on `/api/v1/movies/search` supports all global languages without restrictions.

---

## 4. Verified Working Stream Providers (Free HTTP / No Debrid)

| Provider | Base Manifest / Endpoint | Content Coverage | Empirical Status |
| :--- | :--- | :--- | :--- |
| **PenguPlay** | `https://pengu.uk/{auth_token}/manifest.json` (configured via `PENGUPLAY_MANIFEST_URL` in `.env`) | Multi-host (HubCloud, MovieBox, CineFreak, VidFast, VAPlayer). Tamil, Indian regional, Hollywood. | **Active** (30–48 streams/title). Signed tokens valid for ~8 hours (`psig`). |
| **HdHub (thevolecitor)** | `https://hdhub.thevolecitor.qzz.io/.../manifest.json` | Direct 4KHDHub & HDHub4u links. High fidelity for Tamil (*Leo*, *Jailer*, *Vikram*), KDrama (*Squid Game*), Hollywood. | **Active** (16–48 streams/title). Direct HTTP 206 Matroska video playback without bot challenges. |

---

## 5. Unified Stremio Provider & Final Stream Schema

- **Unified Stremio Provider (`backend/scrappers/providers/stremio.py`)**: Replaced separate provider folders (`penguplay/` and `hdhub/`) with a single generic `StremioScraper` class.
- **Title & Year Guard**: Filters out upstream WordPress keyword leaks (e.g. discarding "Leo Grande" and "Leo Da Vinci" when querying "Leo (2023)").
- **Rich Stream Metadata**:
  - `languages`: Detected audio tracks (`["Tamil"]`, `["Tamil", "Hindi"]`).
  - `size_mb` & `formatted_size`: Exact file sizes (e.g. `3.03 GB`).
  - `bitrate_kbps` & `bitrate_str`: Extracted or computed from `size_mb` / `runtime_minutes` for client-side speed & buffering calculations.
  - `source` & `host`: Upstream source (e.g. `MovieBox`, `HDHub4u`) and storage CDN (e.g. `PixelDrain`, `Sacdn`).
- **Client-Side Probing**: Server-side video segment probing removed; streams are returned instantly (< 3s) for client-side live probing.

---

## 6. Dashboard Lanes & Standardized Pagination Envelope

- **Tamil Homepage Lane Split**:
  - `new` ("New Releases"): Dynamic TMDb discover query (`language=ta`, `sort_by=primary_release_date.desc`, up to today's date).
  - `trending` ("Trending Tamil"): Preserves curated SQLite MOVIEmeter catalog data.
- **Harmonized Pagination Envelope**:
  - Implemented across `/dashboard/lane`, `/movies/discover`, `/movies/search`, and `/lists/{id}/items`.
  - Schema: `{ "items": [...], "results": [...], "page": 1, "has_more": true, "next_page": 2, "total_pages": ... }`. Dual `items` and `results` keys provide backwards compatibility with legacy Flutter methods and new list widgets.
  - `/movies/dashboard/lane` accepts optional `genre` and `year` query parameters.

---

## 7. IMDb ID Gate & Rating Enrichment

- **IMDb ID Requirement**:
  - Enforced across TMDb discover and search via `filter_and_enrich_imdb` in [`backend/services/tmdb.py`](file:///home/mukes/dev/movies/backend/services/tmdb.py).
  - Any title lacking a linked IMDb ID (e.g. amateur/unverified user submissions) is discarded.
  - Official upcoming titles (*Avengers: Doomsday*, *Avatar 3*, *Coolie*) have verified IMDb IDs and remain fully discoverable and searchable.
- **Local Rating Enrichment**:
  - Automatically queries the local SQLite `imdb_ratings` table in [`backend/data/catalog.db`](file:///home/mukes/dev/movies/backend/data/catalog.db) (1.7M+ entries).
  - Replaces TMDb's often missing/zero ratings with the true IMDb `vote_average` and `vote_count` in both movie summaries and [`get_details`](file:///home/mukes/dev/movies/backend/routes/movies.py#L478).

---

## 8. Non-Fiction Genre Exclusion & Two-Tier IMDb Vote Floor

- **Non-Fiction Genre Exclusion**:
  - Excluded TMDb TV genres `{10764, 10767, 10763}` (*Reality*, *Talk Show*, *News*) across discover, search, and actor filmographies (`get_person_filmography`).
  - Completely eliminates unscripted specials (e.g. *Into the Wild*, *MasterChef*, *Koffee with Karan*, game shows) from polluting actors' filmographies and catalog feeds.
- **Two-Tier IMDb Vote Floor**:
  - Titles released > 7 days ago require **`votes >= 50`** in [`catalog.db`](file:///home/mukes/dev/movies/backend/data/catalog.db), eliminating stale zero-audience submissions.
  - Titles released within the last 7 days receive an opening-week grace period (`votes >= 5` if present, or allowed if pending DB sync).
  - Future / upcoming releases (e.g. *Avengers: Doomsday*) are preserved.



