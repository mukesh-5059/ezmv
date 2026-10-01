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
