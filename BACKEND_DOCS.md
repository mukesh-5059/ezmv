# Backend Documentation (`backend_revised`)

Cloudflare Workers edge API built with [Hono](https://hono.dev/), Cloudflare D1 (SQLite), and Cloudflare KV.

---

## 1. Directory Structure

```text
backend_revised/
├── src/
│   ├── config/                # Bundled fallback & static configurations
│   │   ├── actors.json        # Curated regional actors fallback
│   │   ├── dashboards.ts      # Active dashboards & lane definitions
│   │   ├── genres.ts          # Canonical genres list & alias resolver
│   │   └── rating_rules.json  # Bayesian rating rules, weights & era curve
│   ├── routes/                # HTTP API route handlers
│   │   ├── actors.ts          # /api/v1/actors (Curated actors & filmography)
│   │   ├── dashboard.ts       # /api/v1/dashboard (Multi-dashboard & paginated lanes)
│   │   ├── lists.ts           # /api/v1/lists (Trakt curated lists)
│   │   ├── movies.ts          # /api/v1/movies (Movie details & TV season episodes)
│   │   ├── search.ts          # /api/v1/search (Catalog & Trakt upstream search)
│   │   ├── streams.ts         # /api/v1/streams (PenguPlay & HDHub Stremio streams)
│   │   └── subtitles.ts       # /api/v1/subtitles (OpenSubtitles resolution)
│   ├── services/              # Core business services
│   │   ├── actors.ts          # Actor resolution & TMDb combined filmography
│   │   ├── cache.ts           # Edge Cache API wrapper (`caches.default`)
│   │   ├── catalog.ts         # D1 database queries & multi-item resolution
│   │   ├── config.ts          # Dynamic ConfigService (KV -> Cache -> Bundled JSON)
│   │   ├── lanes.ts           # Lane queries, multi-filter & sorting
│   │   ├── lists.ts           # Trakt lists client & pagination
│   │   ├── mdblist.ts         # MDBList batch client & Bayesian rating calculator
│   │   ├── streams.ts         # Multi-provider Stremio stream scraper & parser
│   │   └── traktsearch.ts     # Trakt catalog search service
│   ├── types/                 # TypeScript interfaces & API response definitions
│   │   ├── api.ts             # API request/response contracts & filters
│   │   ├── config.ts          # Config schemas (rating rules, dashboards)
│   │   ├── index.ts           # Barrel export
│   │   └── upstream.ts        # Upstream MDBList & Trakt raw payload types
│   └── index.ts               # Hono app entry point, routing & trace middleware
├── scripts/
│   └── sync_catalog_to_d1.py  # Standalone CLI for generating sync SQL
├── schema.sql                 # D1 database SQLite schema and views
└── wrangler.toml              # Cloudflare Worker deployment & binding configuration
```

---

## 2. Dynamic KV Configuration & Caching

Configuration values are stored in Cloudflare KV namespace `CONFIG_KV` and fetched through [`ConfigService`](file:///home/mukes/dev/movies/backend_revised/src/services/config.ts):
1. **Edge Cache**: Checked via Cloudflare Cache API (`caches.default`) under `https://cache.internal/config/${key}` (1-hour TTL).
2. **KV Namespace**: Fetched from `CONFIG_KV` on edge cache miss.
3. **Bundled Fallback**: Falls back to local JSON in `src/config/` if KV is unavailable.

### KV Keys:
- `rating_rules`: Bayesian prior, source weights (IMDb, TMDb, Trakt, Letterboxd, Metacritic, Rotten Tomatoes), minimum votes, and era decay parameters.
- `curated_actors`: Array of featured regional actors with TMDb IDs and biographies.

---

## 3. Database Schema (Cloudflare D1)

- **`movies`**: Core movie and TV metadata (`imdb_id`, `tmdb_id`, `media_type`, `title`, `year`, `release_date`, `poster_path`, `backdrop_path`, `overview`, `runtime`, `genres`, `updated_at`).
  - *Note on `tmdb_id`*: Stored with media type prefix (e.g. `movie:278` or `tv:1399`) to prevent ID collisions between movies and TV shows sharing identical TMDb IDs.
- **`ratings`**: Source ratings JSON, computed Bayesian composite `rating_score` (0.0–10.0), total `votes`, and `updated_at`.
- **`lane_entries`**: Many-to-many lane mappings (`lane_id`, `imdb_id`, `rank`, `updated_at`).
- **`v_movies`**: Unified view joining `movies` and `ratings` for single-query reads.

---

## 4. Global Models & Pagination Envelope

### Standard Pagination Response (`PaginatedResponse<T>`)
Used by lane pagination, search, and list endpoints:
```json
{
  "items": [],
  "page": 1,
  "total_pages": 5,
  "total_items": 450,
  "has_more": true,
  "next_page": 2
}
```

### Movie Summary Object (`MovieSummary`)
Core payload returned across catalog lanes, search, and list items:
```json
{
  "imdb_id": "tt0111161",
  "tmdb_id": 278,
  "title": "The Shawshank Redemption",
  "overview": "Imprisoned in the 1940s for a double murder he didn't commit...",
  "release_date": "1994-09-23",
  "poster_path": "https://image.tmdb.org/t/p/w500/9cqNxx0GxF0bflZmeSMuL5tnGzr.jpg",
  "backdrop_path": "https://image.tmdb.org/t/p/w1280/kXfqcdQKsToO0OUXHcrrNCHDBzO.jpg",
  "rating_score": 9.3,
  "vote_count": 2800000,
  "media_type": "movie",
  "genres": [
    { "slug": "drama", "name": "Drama" },
    { "slug": "crime", "name": "Crime" }
  ]
}
```

---

## 5. API Endpoints Reference

### 5.1. System & Canonical Metadata

---

#### `GET /`
Service health check and status confirmation.

- **Method**: `GET`
- **Path**: `/`
- **Query Parameters**: None
- **Headers**: None
- **Response** (`200 OK`):
  ```json
  {
    "status": "online",
    "message": "Movie Streaming Backend API is running."
  }
  ```

---

#### `GET /api/v1/genres`
Returns the canonical list of genre slugs and display names for client-side filter pills/chips.

- **Method**: `GET`
- **Path**: `/api/v1/genres`
- **Query Parameters**: None
- **Cache-Control**: `public, max-age=2592000, stale-while-revalidate=86400` (30 days)
- **Response** (`200 OK`):
  ```json
  [
    { "slug": "action", "name": "Action" },
    { "slug": "adventure", "name": "Adventure" },
    { "slug": "animation", "name": "Animation" },
    { "slug": "anime", "name": "Anime" },
    { "slug": "biography", "name": "Biography" },
    { "slug": "comedy", "name": "Comedy" },
    { "slug": "crime", "name": "Crime" },
    { "slug": "documentary", "name": "Documentary" },
    { "slug": "drama", "name": "Drama" },
    { "slug": "family", "name": "Family" },
    { "slug": "fantasy", "name": "Fantasy" },
    { "slug": "history", "name": "History" },
    { "slug": "horror", "name": "Horror" },
    { "slug": "music", "name": "Music" },
    { "slug": "mystery", "name": "Mystery" },
    { "slug": "romance", "name": "Romance" },
    { "slug": "sci-fi", "name": "Sci-Fi" },
    { "slug": "sport", "name": "Sports" },
    { "slug": "thriller", "name": "Thriller" },
    { "slug": "war", "name": "War" }
  ]
  ```

---

### 5.2. Dashboards & Homepage Lanes

---

#### `GET /api/v1/dashboard`
Lists all available dashboard categories.

- **Method**: `GET`
- **Path**: `/api/v1/dashboard`
- **Query Parameters**: None
- **Cache-Control**: `public, max-age=604800, stale-while-revalidate=86400` (7 days)
- **Response** (`200 OK`):
  ```json
  [
    { "id": "tamil", "title": "Tamil Cinema" },
    { "id": "english", "title": "Hollywood & English" },
    { "id": "anime", "title": "Anime" }
  ]
  ```

---

#### `GET /api/v1/dashboard/:dashboard_id`
Fetches all homepage lanes for a dashboard, pre-populated with up to 100 items per lane.

- **Method**: `GET`
- **Path**: `/api/v1/dashboard/:dashboard_id`
- **Path Parameters**:
  | Parameter | Type | Required | Description |
  |---|---|---|---|
  | `dashboard_id` | `string` | Yes | Target dashboard slug: `tamil`, `english`, or `anime` |

- **Query Parameters**:
  | Parameter | Type | Required | Default | Description |
  |---|---|---|---|---|
  | `refresh` | `string` / `boolean` | No | `false` | Pass `true` to bypass edge cache and fetch fresh data |

- **Cache-Control**: `public, max-age=43200, stale-while-revalidate=86400` (12 hours)
- **Status Codes**:
  - `200 OK`: Successful response
  - `404 Not Found`: Unknown dashboard ID
- **Response** (`200 OK`):
  ```json
  {
    "id": "tamil",
    "title": "Tamil Cinema",
    "lanes": [
      {
        "id": "ta_trending",
        "title": "Trending Now",
        "items": [ /* MovieSummary[] */ ],
        "page": 1,
        "total_pages": 3,
        "total_items": 250,
        "has_more": true,
        "next_page": 2
      }
    ]
  }
  ```

---

#### `GET /api/v1/dashboard/:dashboard_id/lanes/:lane_id`
Paginated view of an individual lane (100 items per page) with server-side multi-filtering and sorting.

- **Method**: `GET`
- **Path**: `/api/v1/dashboard/:dashboard_id/lanes/:lane_id`
- **Path Parameters**:
  | Parameter | Type | Required | Description |
  |---|---|---|---|
  | `dashboard_id` | `string` | Yes | Dashboard slug: `tamil`, `english`, `anime` |
  | `lane_id` | `string` | Yes | Target lane ID (e.g. `ta_trending`, `ta_new_releases`, `en_trending`) |

- **Query Parameters**:
  | Parameter | Type | Required | Default | Description |
  |---|---|---|---|---|
  | `page` | `number` | No | `1` | 1-indexed page number |
  | `type` / `media_type` | `string` | No | `'all'` | Filter media type: `'all'`, `'movie'`, or `'tv'` |
  | `genre` | `string` | No | `undefined` | Canonical genre slug (e.g. `action`, `thriller`) |
  | `year` | `number` | No | `undefined` | Release year filter (e.g. `2024`) |
  | `min_rating` | `number` | No | `undefined` | Minimum composite rating score (e.g. `7.5`) |
  | `sort_by` | `string` | No | `'popular'` | Sort order: `'popular'` (rank), `'top_rated'`, `'newest'`, `'oldest'`, or `'title'` |
  | `refresh` | `string` / `boolean` | No | `false` | Pass `true` to bypass edge cache |

- **Cache-Control**: `public, max-age=43200, stale-while-revalidate=86400` (12 hours)
- **Status Codes**:
  - `200 OK`: Successful response
  - `404 Not Found`: Unknown dashboard ID or lane ID
- **Response** (`200 OK`):
  ```json
  {
    "id": "ta_trending",
    "title": "Trending Now",
    "items": [ /* MovieSummary[] */ ],
    "page": 1,
    "total_pages": 3,
    "total_items": 240,
    "has_more": true,
    "next_page": 2
  }
  ```

---

### 5.3. Movies & TV Series

---

#### `GET /api/v1/movies/:media_type/:imdb_id`
Retrieves detailed metadata for a single movie or TV show, including composite rating, cast list (top 20), seasons breakdown, and ongoing status.

- **Method**: `GET`
- **Path**: `/api/v1/movies/:media_type/:imdb_id`
- **Path Parameters**:
  | Parameter | Type | Required | Description |
  |---|---|---|---|
  | `media_type` | `string` | Yes | Media type: strictly `'movie'` or `'tv'` |
  | `imdb_id` | `string` | Yes | IMDb ID: strictly required to start with `'tt'` (e.g. `tt0944947`) |

- **Query Parameters**: None
- **Cache-Control**: `public, max-age=86400, stale-while-revalidate=43200` (24 hours)
- **Status Codes**:
  - `200 OK`: Movie or show details found
  - `400 Bad Request`: Invalid `media_type` or `id` does not begin with `tt`
  - `404 Not Found`: Item not found in catalog or upstream providers
- **Response** (`200 OK`):
  ```json
  {
    "imdb_id": "tt0944947",
    "tmdb_id": 1399,
    "title": "Game of Thrones",
    "overview": "Seven noble families fight for control of the mythical land of Westeros.",
    "release_date": "2011-04-17",
    "poster_path": "https://image.tmdb.org/t/p/w500/...",
    "backdrop_path": "https://image.tmdb.org/t/p/w1280/...",
    "rating_score": 9.2,
    "vote_count": 2200000,
    "media_type": "tv",
    "genres": [
      { "slug": "drama", "name": "Drama" },
      { "slug": "fantasy", "name": "Fantasy" }
    ],
    "runtime": 60,
    "cast": [
      {
        "tmdb_id": 239019,
        "name": "Emilia Clarke",
        "character": "Daenerys Targaryen",
        "profile_path": "https://image.tmdb.org/t/p/w185/92B9m...",
        "order": 0
      }
    ],
    "seasons": [
      {
        "season_number": 1,
        "name": "Season 1",
        "episode_count": 10
      }
    ],
    "status": "Ended",
    "is_ongoing": false,
    "original_language": "en"
  }
  ```

---

#### `GET /api/v1/movies/tv/:tmdb_id/season/:season_number`
Retrieves episode-level details for a specific season of a TV series.

- **Method**: `GET`
- **Path**: `/api/v1/movies/tv/:tmdb_id/season/:season_number`
- **Path Parameters**:
  | Parameter | Type | Required | Description |
  |---|---|---|---|
  | `tmdb_id` | `number` | Yes | Numeric TMDb TV Series ID (`> 0`) |
  | `season_number` | `number` | Yes | Numeric season number (`>= 0`) |

- **Query Parameters**: None
- **Cache-Control**: `public, max-age=86400, stale-while-revalidate=43200` (24 hours)
- **Status Codes**:
  - `200 OK`: Season found
  - `400 Bad Request`: Non-numeric TMDb ID or season number
  - `404 Not Found`: Season not found on TMDb
- **Response** (`200 OK`):
  ```json
  {
    "season_number": 1,
    "name": "Season 1",
    "episode_count": 10,
    "episodes": [
      {
        "episode_number": 1,
        "name": "Winter Is Coming",
        "overview": "Ned Stark is torn between his family and an old friend...",
        "still_path": "https://image.tmdb.org/t/p/w500/...",
        "air_date": "2011-04-17",
        "runtime": 62,
        "is_released": true
      }
    ]
  }
  ```

---

### 5.4. Search

---

#### `GET /api/v1/search`
Searches catalog and upstream Trakt API with full Bayesian composite ratings and filtering (100 items per page).

- **Method**: `GET`
- **Path**: `/api/v1/search`
- **Query Parameters**:
  | Parameter | Type | Required | Default | Description |
  |---|---|---|---|---|
  | `query` / `q` | `string` | No (Recommended) | `""` | Search text. If omitted or empty, returns empty items page immediately |
  | `page` | `number` | No | `1` | 1-indexed page number |
  | `type` / `media_type` | `string` | No | `'all'` | Filter media type: `'all'`, `'movie'`, or `'tv'` |
  | `genre` | `string` | No | `undefined` | Genre slug filter |
  | `year` | `number` | No | `undefined` | Release year filter |
  | `min_rating` | `number` | No | `undefined` | Minimum composite score filter (0.0 to 10.0) |

- **Cache-Control**: `public, max-age=43200, stale-while-revalidate=86400` (12 hours)
- **Response** (`200 OK`):
  ```json
  {
    "items": [ /* MovieSummary[] */ ],
    "page": 1,
    "total_pages": 4,
    "total_items": 380,
    "has_more": true,
    "next_page": 2
  }
  ```

---

### 5.5. Curated Lists (Trakt)

---

#### `GET /api/v1/lists/popular`
Fetches paginated popular curated lists from Trakt (100 lists per page).

- **Method**: `GET`
- **Path**: `/api/v1/lists/popular`
- **Query Parameters**:
  | Parameter | Type | Required | Default | Description |
  |---|---|---|---|---|
  | `page` | `number` | No | `1` | 1-indexed page number |

- **Cache-Control**: `public, max-age=43200, stale-while-revalidate=86400` (12 hours)
- **Response** (`200 OK`):
  ```json
  {
    "items": [
      {
        "id": 1234567,
        "name": "IMDb Top 250 Movies",
        "item_count": 250,
        "likes": 1420
      }
    ],
    "page": 1,
    "total_pages": 10,
    "total_items": 1000,
    "has_more": true,
    "next_page": 2
  }
  ```

---

#### `GET /api/v1/lists/search`
Searches curated Trakt lists by query (50 lists per page).

- **Method**: `GET`
- **Path**: `/api/v1/lists/search`
- **Query Parameters**:
  | Parameter | Type | Required | Default | Description |
  |---|---|---|---|---|
  | `query` / `q` | `string` | No | `""` | Search query. If blank, redirects (`302`) to `/api/v1/lists/popular?page=${page}` |
  | `page` | `number` | No | `1` | 1-indexed page number |

- **Cache-Control**: `public, max-age=43200, stale-while-revalidate=86400` (12 hours)
- **Response** (`200 OK`):
  Returns `PaginatedListsResponse` matching the structure of `/api/v1/lists/popular`.

---

#### `GET /api/v1/lists/:list_id/items`
Fetches movies and shows inside a specific curated list with filtering and sorting (100 items per page).

- **Method**: `GET`
- **Path**: `/api/v1/lists/:list_id/items`
- **Path Parameters**:
  | Parameter | Type | Required | Description |
  |---|---|---|---|
  | `list_id` | `number` | Yes | Numeric Trakt list ID (e.g. `1248149`). Slugs are not supported by Trakt's global lists API. |

- **Query Parameters**:
  | Parameter | Type | Required | Default | Description |
  |---|---|---|---|---|
  | `page` | `number` | No | `1` | 1-indexed page number |
  | `type` / `media_type` | `string` | No | `'all'` | Media type: `'all'`, `'movie'`, or `'tv'` |
  | `genre` | `string` | No | `undefined` | Canonical genre slug filter |
  | `year` | `number` | No | `undefined` | Release year filter |
  | `min_rating` | `number` | No | `undefined` | Minimum composite score filter (0.0 to 10.0) |
  | `sort_by` | `string` | No | `undefined` | Sort property: `'rank'`, `'added'`, `'title'`, `'released'`, `'popularity'`, `'votes'` |
  | `sort_order` | `string` | No | `undefined` | Direction: `'asc'` or `'desc'` |

- **Cache-Control**: `public, max-age=43200, stale-while-revalidate=86400` (12 hours)
- **Status Codes**:
  - `200 OK`: Successful response
  - `400 Bad Request`: Missing or invalid numeric `list_id` parameter
- **Response** (`200 OK`):
  ```json
  {
    "items": [ /* MovieSummary[] */ ],
    "page": 1,
    "total_pages": 3,
    "total_items": 250,
    "has_more": true,
    "next_page": 2
  }
  ```

---

### 5.6. Featured Actors & Filmography

---

#### `GET /api/v1/actors`
Returns a list of curated featured regional actors.

- **Method**: `GET`
- **Path**: `/api/v1/actors`
- **Query Parameters**: None
- **Cache-Control**: `public, max-age=604800, stale-while-revalidate=86400` (7 days)
- **Response** (`200 OK`):
  ```json
  [
    {
      "tmdb_id": 146939,
      "name": "Kamal Haasan",
      "biography": "Kamal Haasan is an Indian actor, director, screenwriter...",
      "profile_path": "https://image.tmdb.org/t/p/w500/..."
    }
  ]
  ```

---

#### `GET /api/v1/actors/:id`
Returns actor biography and filmography categorized into up to 30 popular works and up to 30 recent releases.

- **Method**: `GET`
- **Path**: `/api/v1/actors/:id`
- **Path Parameters**:
  | Parameter | Type | Required | Description |
  |---|---|---|---|
  | `id` | `number` | Yes | Numeric TMDb Person ID (`> 0`) |

- **Query Parameters**: None
- **Cache-Control**: `public, max-age=604800, stale-while-revalidate=86400` (7 days)
- **Status Codes**:
  - `200 OK`: Person found
  - `400 Bad Request`: Invalid or non-numeric person ID
  - `404 Not Found`: Person not found on TMDb
- **Response** (`200 OK`):
  ```json
  {
    "tmdb_id": 146939,
    "name": "Kamal Haasan",
    "biography": "Kamal Haasan is an Indian actor...",
    "profile_path": "https://image.tmdb.org/t/p/w500/...",
    "popular": [ /* MovieSummary[] up to 30 items sorted by rating_score & vote_count */ ],
    "recent": [ /* MovieSummary[] up to 30 items sorted by release_date */ ]
  }
  ```

---

### 5.7. Streams

---

#### `GET /api/v1/streams/:media_type/:imdb_id`
Resolves streaming links for movies or TV episodes by querying high-speed direct CDN providers (**PlavioHD** & **HDHub**) in parallel, with automatic fallback to secondary scrapers (**PenguPlay** & **NoTorrent**). Deduplicates streams by canonical URL and filename/size, ranks by host speed and language priority, and returns a clean top-20 stratified slice.

- **Method**: `GET`
- **Path**: `/api/v1/streams/:media_type/:imdb_id`
- **Path Parameters**:
  | Parameter | Type | Required | Description |
  |---|---|---|---|
  | `media_type` | `string` | Yes | Media type: strictly `'movie'` or `'tv'` |
  | `imdb_id` | `string` | Yes | IMDb ID strictly starting with `'tt'` (e.g. `tt0816692`) |

- **Query Parameters**:
  | Parameter | Type | Required | Default | Description |
  |---|---|---|---|---|
  | `season` | `number` | Yes (if `tv`) | `undefined` | Season number (required when `media_type === 'tv'`) |
  | `episode` | `number` | Yes (if `tv`) | `undefined` | Episode number (required when `media_type === 'tv'`) |
  | `default_language` | `string` | No | `undefined` | Fallback language or ISO code (e.g. `'Tamil'`, `'ta'`) used when release has no explicit language tags |

- **Response** (`200 OK`):
  ```json
  {
    "imdb_id": "tt0816692",
    "media_type": "movie",
    "streams": [
      {
        "url": "https://pengu.uk/direct/external/...",
        "quality": "1080p",
        "filename": "Interstellar (2014) IMAX 1080p BluRay REMUX AVC...",
        "size_bytes": 36582383944,
        "formatted_size": "34.07 GB",
        "priority": 30,
        "provider": "penguplay",
        "host": "pengu.uk",
        "languages": ["Hindi", "English"],
        "headers": {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)..."
        }
      }
    ]
  }
  ```

---

### 5.8. Subtitles

---

#### `GET /api/v1/subtitles/:media_type/:imdb_id`
Resolves available subtitle tracks for movies or TV episodes via OpenSubtitles (Stremio v3 Addon).

- **Method**: `GET`
- **Path**: `/api/v1/subtitles/:media_type/:imdb_id` *(also supports legacy `GET /api/v1/subtitles?imdb_id=...&media_type=...`)*
- **Path Parameters**:
  | Parameter | Type | Required | Description |
  |---|---|---|---|
  | `media_type` | `string` | Yes | Media type: `'movie'` or `'tv'` |
  | `imdb_id` | `string` | Yes | IMDb ID strictly starting with `'tt'` (e.g. `tt0111161`) |

- **Query Parameters**:
  | Parameter | Type | Required | Default | Description |
  |---|---|---|---|---|
  | `season` | `number` | Yes (if `tv`) | `undefined` | Season number (required when `media_type === 'tv'`) |
  | `episode` | `number` | Yes (if `tv`) | `undefined` | Episode number (required when `media_type === 'tv'`) |
  | `language` | `string` | No | `undefined` | Case-insensitive language name or ISO code filter (e.g. `English`, `eng`, `Tamil`) |

- **Status Codes**:
  - `200 OK`: Subtitle tracks returned (may be empty array if none found)
  - `400 Bad Request`:
    - Missing or invalid `imdb_id`
    - Invalid `media_type`
    - Missing `season` or `episode` when `media_type === 'tv'`
- **Response** (`200 OK`):
  ```json
  [
    {
      "name": "Movie.Title.2024.1080p.WEB-DL",
      "language": "English",
      "url": "https://opensubtitles.org/...",
      "popularity": 420
    }
  ]
  ```

---

## 6. Endpoints Summary Table

| Method | Endpoint | Primary Query / Path Params | Purpose |
|---|---|---|---|
| `GET` | `/` | — | API status and health check |
| `GET` | `/api/v1/genres` | — | Canonical list of genres for filter pills |
| `GET` | `/api/v1/dashboard` | — | List available dashboard categories |
| `GET` | `/api/v1/dashboard/:dashboard_id` | `:dashboard_id`, `?refresh` | Homepage lanes with first 100 items each |
| `GET` | `/api/v1/dashboard/:dashboard_id/lanes/:lane_id` | `:dashboard_id`, `:lane_id`, `?page`, `?type`, `?genre`, `?year`, `?min_rating`, `?sort_by`, `?refresh` | Paginated lane items (100/page) with 4 filters & 5 sorts |
| `GET` | `/api/v1/movies/:media_type/:imdb_id` | `:media_type`, `:imdb_id` (`tt...`) | Movie/show details, Bayesian rating, cast (top 20), seasons |
| `GET` | `/api/v1/movies/tv/:tmdb_id/season/:season_number` | `:tmdb_id` (TMDb), `:season_number` | TV Season episode list with `is_released` flags |
| `GET` | `/api/v1/search` | `?q`, `?page`, `?type`, `?genre`, `?year`, `?min_rating` | Search catalog & Trakt upstream with Bayesian ratings |
| `GET` | `/api/v1/lists/popular` | `?page` | Curated popular Trakt lists (100/page) |
| `GET` | `/api/v1/lists/search` | `?q`, `?page` | Search Trakt lists (50/page) |
| `GET` | `/api/v1/lists/:list_id/items` | `:list_id`, `?page`, `?type`, `?genre`, `?year`, `?min_rating`, `?sort_by`, `?sort_order` | Paginated items inside a curated list (100/page) |
| `GET` | `/api/v1/actors` | — | Curated regional featured actors |
| `GET` | `/api/v1/actors/:id` | `:id` (TMDb) | Actor profile, top 30 popular and top 30 recent filmography |
| `GET` | `/api/v1/streams/:media_type/:imdb_id` | `:media_type`, `:imdb_id`, `?season`, `?episode`, `?default_language` | Deduplicated, host-ranked streaming links (PlavioHD, HDHub, PenguPlay, NoTorrent) |
| `GET` | `/api/v1/subtitles/:media_type/:imdb_id` | `:media_type`, `:imdb_id`, `?season`, `?episode`, `?language` | OpenSubtitles tracks sorted by popularity |
