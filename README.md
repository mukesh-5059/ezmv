# Movies & TV Streaming App

A self-hosted media scrapping / streaming project with a Python backend and Flutter client apps.

---

## Project Structure

- **`backend/`**: FastAPI service for metadata, scraping, and subtitles.
- **`tv_app/`**: Flutter client for Android TV with D-pad / remote navigation.
- **`mobile_app/`**: Flutter client for mobile devices(work in progress).
- **`shared_core/`**: Shared Dart models, API client, and local storage utilities.

---

## Backend

- **Metadata & Catalog**: Fetches trending lists, search, and movie/show details using **TMDB** and **Trakt**.
- **Stream Scrapers**: Scrapes streaming links from providers including **VidSrc** and **Isaimini**.
- **Subtitles**: Fetches and serves subtitles via OpenSubtitles.
- **Caching**: Caches stream links and metadata locally with SQLite.

---

## Frontend

- **Android TV App**: UI designed for TV remotes with media playback via `media_kit`.
- **Mobile App**: Work in progress.
- **Shared Core**: Reusable models, API logic, and watch progress tracking between both clients.

---

## Documentation

Comprehensive architecture, API contracts, and implementation guides are located in the [`docs/`](docs/) directory:

- [API Documentation](docs/api_docs.md): Cloudflare Workers Hono API endpoints and schemas.
- [TV App Architecture](docs/tv_app.md): 10-foot UI architecture, hardware optimizations, and screen guides.
- [Shared Core Guide](docs/shared_core.md): Reusable models, QuickJS scraper runtime, and storage services.
- [Rating Architecture Analysis](docs/rating-architecture-analysis.md): Rating calculation and Bayesian weighting analysis.
- [Todo](docs/todo.md): Active development task list.

Just use stremio with penguplay or hdhub addon