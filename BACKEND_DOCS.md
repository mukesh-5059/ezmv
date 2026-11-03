# Backend Documentation (`backend_revised`)

Cloudflare Workers edge API built with [Hono](https://hono.dev/), Cloudflare D1 (SQLite), and Cloudflare KV.

---

## 1. Directory Structure

```text
backend_revised/
├── src/
│   ├── config/                # Bundled fallback configurations
│   │   ├── actors.json        # Curated regional actors
│   │   ├── dashboardlist.json # Available dashboard definitions
│   │   ├── dashboards/        # Dashboard configurations (e.g. tamil.json)
│   │   ├── rating_rules.json  # Bayesian rating rules, weights & era curve
│   │   └── sync_lanes.json    # Upstream MDBList lane sync definitions
│   ├── routes/                # HTTP API endpoints
│   │   ├── actors.ts          # /api/v1/actors (Curated actors & filmography)
│   │   ├── dashboard.ts       # /api/v1/dashboard (Multi-dashboard & paginated lanes)
│   │   ├── lists.ts           # /api/v1/lists (Curated lists)
│   │   ├── movies.ts          # /api/v1/movies (Movie details & recommendations)
│   │   ├── search.ts          # /api/v1/search (Catalog & Trakt upstream search)
│   │   └── subtitles.ts       # /api/v1/subtitles (Subtitle resolution)
│   ├── services/              # Core business services
│   │   ├── actors.ts          # Actor resolution & TMDB filmography
│   │   ├── cache.ts           # Edge Cache API wrapper (`caches.default`)
│   │   ├── catalog.ts         # D1 database queries & multi-filter search
│   │   ├── config.ts          # Dynamic ConfigService (KV -> Cache -> Bundled JSON)
│   │   └── mdblist.ts         # Bayesian composite rating calculator
│   ├── types/                 # TypeScript interfaces & API response definitions
│   └── index.ts               # Hono app entry point, routing & trace middleware
├── scripts/
│   ├── sync/                  # Modular Python sync package
│   │   ├── client.py          # MDBList HTTP client & batching
│   │   ├── config.py          # Dynamic KV & environment config resolver
│   │   ├── lanes.py           # Velocity & lane filtering logic
│   │   ├── rating.py          # Multi-source composite rating engine
│   │   └── sql.py             # D1 SQL upsert generator
│   └── sync_catalog_to_d1.py  # Standalone CLI for generating sync SQL
└── wrangler.toml              # Cloudflare Worker deployment & binding configuration
```

---

## 2. Dynamic KV Configuration & Caching

Configs are stored in Cloudflare KV namespace `CONFIG_KV` and fetched through [`ConfigService`](file:///home/mukes/dev/movies/backend_revised/src/services/config.ts):
1. **Edge Cache**: Checked via Cloudflare Cache API (`caches.default`) under `https://cache.internal/config/${key}` (1-hour TTL).
2. **KV Namespace**: Fetched from `CONFIG_KV` on cache miss.
3. **Bundled Fallback**: Falls back to local JSON in `src/config/` if KV is unavailable.

### KV Keys:
- `rating_rules`: Bayesian prior, source weights, min votes, and era decay parameters.
- `dashboards`: List of active dashboard summaries (`[{ id: "tamil", title: "Tamil Cinema" }]`).
- `dashboard:<id>`: Full dashboard configuration and lane layouts (e.g. `dashboard:tamil`).
- `curated_actors`: Array of featured actors.
- `sync_lanes`: Lane definitions for the MDBList catalog ingestion pipeline.

---

## 3. Database Schema (Cloudflare D1)

- `movies`: Core movie metadata (`imdb_id`, `tmdb_id`, `media_type`, `title`, `year`, `release_date`, `poster_path`, `backdrop_path`, `overview`, `runtime`, `genres`, `updated_at`).
- `ratings`: Cleaned source ratings JSON, Bayesian composite `rating_score`, total `votes`, `updated_at`.
- `lane_entries`: Many-to-many lane mappings (`lane_id`, `imdb_id`, `rank`, `updated_at`).
- `v_catalog`: High-performance SQL view joining `movies` and `ratings`.

---

## 4. API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/` | Service health status |
| `GET` | `/api/v1/genres` | Canonical genre slugs and names |
| `GET` | `/api/v1/dashboard` | List of available dashboards |
| `GET` | `/api/v1/dashboard/:dashboard_id` | Full homepage lanes with movie summaries |
| `GET` | `/api/v1/dashboard/:dashboard_id/lanes/:lane_id` | Paginated lane entries (100 items/page) with 4-filter & 4-sort |
| `GET` | `/api/v1/movies/:id` | Detailed movie info with ratings, cast, and recommendations |
| `GET` | `/api/v1/actors` | Curated actors list |
| `GET` | `/api/v1/actors/:id` | Actor profile & categorized filmography |
| `GET` | `/api/v1/search` | Fast catalog search with fallback to upstream Trakt |
| `GET` | `/api/v1/subtitles/:id` | Subtitles resolution |
