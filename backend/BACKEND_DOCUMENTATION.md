# Movie Streaming Backend - Architecture & Technical Reference

High-performance asynchronous FastAPI backend for movie & TV metadata discovery, multi-provider resilient streaming source extraction, and multi-language subtitle resolution. System integrates TMDb API v3, SQLite WAL catalog caching, DNS-over-HTTPS (DoH) browser-impersonating HTTP sessions (`curl_cffi`), Playwright headless Firefox HLS extraction, dual-scraper orchestration, and Server-Sent Events (SSE) progress broadcasting.

---

## 1. System Architecture

### High-Level Architecture Diagram

```mermaid
flowchart TD
    Client(["Client Applications<br/>(TV App / Web / Mobile)"])

    subgraph FastAPI_Backend ["FastAPI Backend (backend/)"]
        subgraph Routing_Layer ["API Routing (/api/v1)"]
            Main["backend/main.py<br/>Lifespan & CORS"]
            MoviesRouter["backend/routes/movies.py<br/>/movies/*"]
            StreamsRouter["backend/routes/streams.py<br/>/streams/ & SSE"]
            SubtitlesRouter["backend/routes/subtitles.py<br/>/subtitles/"]
        end

        subgraph Core_Services ["Core & Services"]
            Config["backend/config.py<br/>Settings (Pydantic)"]
            SessionManager["backend/session.py<br/>curl_cffi AsyncSession + DoH (1.1.1.1)"]
            TMDBService["backend/services/tmdb.py<br/>TMDBClient (TTLCache)"]
            CatalogService["backend/services/catalog.py<br/>CatalogService (SQLite WAL)"]
            SubtitlesService["backend/services/subtitles.py<br/>SubtitlesService (OpenSubtitles)"]
        end

        subgraph Scraper_Subsystem ["Scraping Subsystem (backend/scrappers/)"]
            ScraperMgr["backend/scrappers/manager.py<br/>ScraperManager (Dynamic TTL & SSE)"]
            BaseScraper["backend/scrappers/base.py<br/>BaseScraper (Abstract)"]
            VidSrcScraper["backend/scrappers/providers/vidsrc/<br/>VidSrc (Playwright Firefox HLS)"]
            IsaiminiScraper["backend/scrappers/providers/isaimini/<br/>Isaimini (Token Matcher & Resolver)"]
        end

        subgraph Persistence ["Persistence & Configs (backend/data/)"]
            CatalogDB[("catalog.db<br/>IMDb Curated Lanes")]
            IsaiminiDB[("isaimini.db<br/>Path & FileID Cache")]
            VidSrcJSON[("vidsrc.json<br/>Primary & Mirror Domains")]
            IsaiminiJSON[("isaimini.json<br/>Active Mirror Domain")]
        end
    end

    subgraph External_Services ["External Providers & Upstream CDNs"]
        TMDB_API[("TMDb API v3<br/>api.themoviedb.org")]
        VidSrcHost[("VidSrc Mirrors & HLS CDNs<br/>vidsrc.sh / vorpalverisimilitude / eclatandephemera")]
        IsaiminiHost[("Isaimini / Moviesda Mirrors<br/>moviezda.net / uptomkv")]
        SubtitlesHost[("OpenSubtitles v3 CDN<br/>opensubtitles-v3.strem.io")]
    end

    %% Client Interactions
    Client -->|Metadata & Details| MoviesRouter
    Client -->|Stream Extraction & SSE| StreamsRouter
    Client -->|Subtitles Lookup| SubtitlesRouter
    Client -->|Direct Playback (media_kit)| VidSrcHost
    Client -->|Direct Playback (media_kit)| IsaiminiHost

    %% Routing to Core / Scrapers
    MoviesRouter --> TMDBService
    MoviesRouter --> CatalogService
    StreamsRouter --> ScraperMgr
    SubtitlesRouter --> SubtitlesService

    %% Core Interactions
    TMDBService -->|DoH Impersonated GET| SessionManager
    SessionManager --> TMDB_API
    SubtitlesService -->|JSON API| SubtitlesHost

    %% Scraper Execution
    ScraperMgr --> VidSrcScraper
    ScraperMgr --> IsaiminiScraper
    VidSrcScraper -->|Headless Firefox Browser| VidSrcHost
    IsaiminiScraper -->|DoH HTTP Session| IsaiminiHost
    IsaiminiScraper --> IsaiminiDB
    VidSrcScraper --> VidSrcJSON
    IsaiminiScraper --> IsaiminiJSON
    CatalogService --> CatalogDB
```

---

## 2. Directory Structure & Component Layers

```text
backend/
├── config.py                      # Pydantic BaseSettings (.env loader)
├── main.py                        # FastAPI entry point, lifespan, CORS, and route mounting
├── models.py                      # Pydantic schemas (MovieSummary, MovieDetails, CastMember, StreamResponse, SubtitleResponse)
├── session.py                     # Centralized curl_cffi AsyncSession manager with DoH (1.1.1.1)
├── data/                          # Runtime data, SQLite databases, and provider domain configs (.gitignored)
│   ├── catalog.db                 # SQLite database storing IMDb GraphQL curated lanes
│   ├── isaimini.db                # SQLite database for Isaimini path indexing and file IDs
│   ├── isaimini.json              # Active domain configuration for Isaimini
│   └── vidsrc.json                # Primary domain and mirrors inventory for VidSrc
├── routes/                        # API endpoint handlers
│   ├── movies.py                  # Search, Discover, Popular, and Details endpoints
│   ├── streams.py                 # Stream resolution and SSE progress streaming endpoint
│   └── subtitles.py               # Subtitle lookup endpoint
├── scripts/
│   └── sync_catalog.py            # IMDb GraphQL lane sync script
├── services/                      # Core business logic services
│   ├── catalog.py                 # SQLite catalog queries and search fallback
│   ├── subtitles.py               # Multi-language subtitle lookup and sorting service
│   └── tmdb.py                    # TMDb API client with in-memory TTLCache
├── scrappers/                     # Scraper subsystem
│   ├── base.py                    # BaseScraper abstract class and data models (MediaItem, StreamSource)
│   ├── manager.py                 # ScraperManager, StreamBroadcaster (SSE), in-flight deduplication
│   └── providers/
│       ├── isaimini/              # Isaimini scraper module (crawler, matcher, resolver, storage)
│       └── vidsrc/                # VidSrc Playwright Firefox HLS extractor module
└── tests/
    └── test_subtitles.py          # Unit test suite for SubtitlesService
```

---

## 3. API Reference

### 3.1 Movies & Details

#### `GET /api/v1/movies/search`
Universal search across movies and TV shows. Combines local curated catalog with live TMDb search.

- **Query Parameters**:
  - `query` (*string, required*): Search query term.
  - `media_type` (*string, default: "movie"*): `"movie"` or `"tv"`.
  - `year` (*integer, optional*): Release year.
  - `page` (*integer, default: 1*): Page number.
- **Response**: `{"results": [MovieSummary]}`

#### `GET /api/v1/movies/{media_type}/{tmdb_id}`
Retrieves enriched details for a movie or TV show, including genres, runtime, external IDs, and full cast members.

- **Path Parameters**:
  - `media_type` (*string*): `"movie"` or `"tv"`.
  - `tmdb_id` (*integer*): TMDb identifier.
- **Response**: `MovieDetails` (includes `cast: list[CastMember]`, `external_ids`, `runtime`, `overview`).

#### `GET /api/v1/movies/popular`
Fetches popular movies. Queries local curated catalog for `ta` language requests; queries live TMDb for others.

- **Query Parameters**:
  - `language` (*string, default: "en-US"*): e.g., `"ta-IN"`, `"en-US"`.
  - `page` (*integer, default: 1*): Page number.

#### `GET /api/v1/movies/discover`
Discovers movies filtered by year, genre, or category (`latest`, `popular`, `box_office`, `comedy`).

---

### 3.2 Streams & Scraping

#### `GET /api/v1/streams/`
Resolves direct playable streaming URLs across all registered scrapers.

- **Query Parameters**:
  - `tmdb_id` (*integer, required*): TMDb identifier.
  - `media_type` (*string, default: "movie"*): `"movie"` or `"tv"`.
  - `season` (*integer, optional*): Required for TV shows.
  - `episode` (*integer, optional*): Required for TV shows.
  - `bypass_cache` (*boolean, default: false*): Forces re-scraping bypassing cache.
  - `format` (*string, optional*): Set to `"sse"` for Server-Sent Events progress streaming.
- **Standard Response**: `StreamResponse`
  ```json
  {
    "title": "Resident Evil",
    "year": 2026,
    "media_type": "movie",
    "tmdb_id": 1423191,
    "imdb_id": "tt35538033",
    "cache_expires_in": 7180,
    "streams": [
      {
        "quality": "1080p",
        "url": "https://eclatandephemera.site/pl/.../master.m3u8?token=...",
        "provider": "VidSrc (1080p)",
        "headers": {
          "Referer": "https://cloudorchestranova.com/",
          "Origin": "https://cloudorchestranova.com",
          "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:155.0) Gecko/20100101 Firefox/155.0"
        },
        "priority": 30
      }
    ]
  }
  ```
- **SSE Stream (`format=sse`)**: Emits progress events:
  ```text
  event: progress
  data: {"step": "init", "message": "Searching sources for Resident Evil (2026)"}

  event: progress
  data: {"step": "probe", "message": "Extracting from: https://vidsrc.sh/embed/movie/tt35538033"}

  event: complete
  data: {"result": { ...StreamResponse... }}
  ```

---

### 3.3 Subtitles

#### `GET /api/v1/subtitles/`
Fetches multi-language subtitles (VTT format) with English subtitles prioritized at the top of the list.

- **Query Parameters**:
  - `tmdb_id` (*integer, required*): TMDb identifier.
  - `media_type` (*string, default: "movie"*): `"movie"` or `"tv"`.
  - `season` (*integer, optional*): Required for TV shows.
  - `episode` (*integer, optional*): Required for TV shows.
  - `language` (*string, optional*): ISO language filter (e.g., `"en"`, `"ta"`).
- **Response**: `SubtitleResponse`
  ```json
  {
    "tmdb_id": 743563,
    "imdb_id": "tt9179430",
    "media_type": "movie",
    "subtitles": [
      {
        "id": "9162113",
        "language": "English",
        "code": "en",
        "url": "https://subs5.strem.io/en/download/subencoding-stremio-utf8/src-api/file/9162113",
        "format": "vtt",
        "release": "Vikram.2022.1080p.WEBRip"
      },
      {
        "id": "13341393",
        "language": "Arabic",
        "code": "ar",
        "url": "https://subs5.strem.io/en/download/subencoding-stremio-utf8/src-api/file/13341393",
        "format": "vtt"
      }
    ]
  }
  ```

---

## 4. Scraper Subsystem

### 4.1 VidSrc Provider (`backend/scrappers/providers/vidsrc/`)
- **Engine**: Headless Playwright Firefox (`HLSExtractorService`) with custom Gecko preferences.
- **Anti-Tamper Neutralization**: Intercepts and replaces `disable-devtool.js` with HTTP 200 empty stubs.
- **Dual-Layer Sniffing**: Captures `.m3u8` network requests and validates `#EXTM3U` manifest payloads.
- **Fast-Path Info Check**: Queries `https://vidsrc.sh/info/movie/{id}.json` before browser launch to verify hosting and extract quality tags (`1080p`, `720p`, `CAM`).
- **Domain Config**: Configured via [`backend/data/vidsrc.json`](file:///home/mukes/dev/movies/backend/data/vidsrc.json). Aborts cleanly if no domain is configured.

### 4.2 Isaimini Provider (`backend/scrappers/providers/isaimini/`)
- **Language Guard**: Immediately fast-exits non-Indian titles (`INDIAN_LANGUAGES = {"ta", "te", "hi", "ml", "kn"}`) in $0\text{ ms}$.
- **Token Matcher**: Multi-pattern tokenizer scoring release names, years, and clean alpha tokens.
- **Resolver**: Resolves `.php` gatekeeper download links into direct upstream CDN video URLs (`mv1.uptomkv.ch`) and computes cryptographic download expiry.
- **Domain Config**: Dynamic mirror discovery saved to [`backend/data/isaimini.json`](file:///home/mukes/dev/movies/backend/data/isaimini.json).

---

## 5. Caching & Persistence Strategy

| Cache Layer | Storage Mechanism | TTL / Eviction | Purpose |
| :--- | :--- | :--- | :--- |
| **`TMDBClient._search_cache`** | In-Memory `TTLCache` | 1 Hour (3,600s) | Caches TMDb search results |
| **`TMDBClient._details_cache`** | In-Memory `TTLCache` | 24 Hours (86,400s) | Caches enriched movie/show details and credits |
| **`ScraperManager._stream_cache`**| In-Memory `TTLCache` | Dynamic: `min(ttls)` (2 Hours for VidSrc, 60s for empty) | Caches extracted stream URLs |
| **`SubtitlesService._cache`** | In-Memory `TTLCache` | 24 Hours (86,400s) | Caches parsed subtitle tracks |
| **`catalog.db`** | SQLite WAL | Persistent | Curated lanes (`trending`, `comedy`, `top_rated`, `box_office`) |
| **`isaimini.db`** | SQLite WAL | Persistent | Isaimini directory paths and file ID index |
