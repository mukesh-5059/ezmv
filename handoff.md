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

---

## 2. Infrastructure Bindings

- **D1 Database**: `movies-catalog` (`ce5096c4-ec8a-463d-890e-493c92d5f580`)
- **KV Namespace**: `CONFIG_KV` (`4d8a8b30e668412596ca7b9cabfecdb4`)
- **Worker Configuration**: [wrangler.toml](file:///home/mukes/dev/movies/backend_revised/wrangler.toml)

---

## 3. Active Next Steps

1. **Deploy Production Worker**:
   - Push environment secrets: `cd backend_revised && npx wrangler secret bulk .dev.vars`
   - Publish Worker: `npx wrangler deploy`
2. **Client Integration**:
   - Integrated `original_language`, `default_language`, and `refresh` parameters into `shared_core` (`ApiClient`, models) and `tv_app` (`StreamSelector`, `PlayerScreen`, `HomeScreen`, `DetailsScreen`).
   - Retrying stream scraping automatically sends `refresh=true` to bust edge cache and scrape live sources.
   - Release split APKs built (`tv_app/build/app/outputs/flutter-apk/`).
