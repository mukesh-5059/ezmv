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
   - Verify `tv_app` and `mobile_app` against the updated `/api/v1/dashboard/:dashboard_id` and `/api/v1/actors/:id` endpoints.
