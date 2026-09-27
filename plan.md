# Project Remake & Architecture Plan

## 1. Core Architecture Decisions

* **Backend Stack**: Python 3.11+ (FastAPI). Retain `curl_cffi` for browser TLS impersonation (Chrome JA3/JA4) and DNS-over-HTTPS (Cloudflare `1.1.1.1`).
* **LAN Discovery**: mDNS (Bonjour/Avahi) via Zeroconf. Server broadcasts `_streamtv._tcp.local`. TV app auto-connects on boot with zero manual IP input.
* **Playback Pipeline (media_kit Migration)**:
  * Direct client-side playback via **`media_kit`** (`libmpv` + FFmpeg core), replacing default ExoPlayer (`video_player`).
  * **Demuxer Resilience**: `libmpv` natively demuxes obfuscated streams, completely bypassing ExoPlayer's `HttpDataSource$InvalidContentTypeException` on `.html` / `text/html` chunks.
  * **PTS Clock Synthesis**: Automatically reconstructs missing video PTS timestamps from audio clocks without crashing.
  * **Hardware Acceleration**: Full Android `MediaCodec` hardware acceleration on TV chipsets.
  * No server-side video proxying. Saves LAN bandwidth and prevents server bottlenecks.
* **Backend `.php` Resolution & Direct CDN Delivery**:
  * Backend resolves initial 302 redirects (`download.php` / `.php` gatekeeper URLs) upfront during scraping/retrieval.
  * Delivers the resolved direct, presigned Cloudflare R2 CDN `.mp4` URL to client devices.
  * **48-Hour Validity**: Direct Cloudflare R2 presigned URLs (`X-Amz-Expires=172800`) are valid for 48 hours, eliminating the 6-minute gatekeeper expiration timeout.
  * **Unrestricted Multi-Device Playback**: The resolved CDN link works on any device and network without IP-locking.
  * **Multi-Tier Caching**: Cached in backend RAM (3 hours) and on-disk SQLite (24 hours TTL) for instant ~4ms responses on repeat views.
* **Link Token Expiry & Auto-Refresh**:
  * Endpoint `GET /api/v1/streams/refresh?file_id={file_id}` generates a fresh CDN link in <150ms from `play.onestream.today` using the permanent `file_id` without re-scraping directory pages.
  * Client resumes playback position seamlessly on token refresh.
* **Content Safety Filtering**:
  * Enforce `vote_count.gte=10` on raw TMDb discovery to block obscure B-grade/titillating titles (*Anaagarigam*) from leaking to living room TVs.

---

## 2. Curated UI/UX Lanes (Zero-Brain Couch Experience)

Five focused, high-engagement lanes tailored for couch viewers:

* **Lane 1: Continue Watching**
  * Instant 1-click resume with progress bar. Top spot for quick re-entry.
* **Lane 2: Recent Original Prints**
  * Auto-indexed from Isaimini Page 1 (HQ uploads only: `Original`, `HDRip`).
* **Lane 3: New & Trending Now (Current Buzz)**
  * **Metric**: IMDb MOVIEMETER (`sortBy: POPULARITY, sortOrder: ASC`).
  * Real-time Tamil buzz (*Mandaadi*, *Vishwanath and Sons*, *Modha Rathiri*, *DC*).
* **Lane 4: Most Watched of All Time (Crowd Favorites)**
  * **Metric**: IMDb Rating Count (`sortBy: USER_RATING_COUNT, sortOrder: DESC`).
  * High-engagement proven classics (*Jai Bhim*, *Soorarai Pottru*, *Master*, *Vikram*).
* **Lane 5: Record-Breaking Mega Hits (US Box Office)**
  * **Metric**: Box Office Domestic Gross (`sortBy: BOX_OFFICE_GROSS_DOMESTIC, sortOrder: DESC`).
  * Grand spectacles (*Ponniyin Selvan 1 & 2*, *2.0*, *Kabali*, *Leo*).

*(Optional Lane 6: Popular Tamil Comedy with `genreConstraint: { anyGenreIds: ["Comedy"] }`)*

### TV Screen Layout:
* **Top 40% (Hero Spotlight)**: Highlights focused movie's 4K backdrop, title, rating, print quality badge, and big "PLAY" CTA.
* **Bottom 60%**: Horizontal scrollable lanes. D-pad down navigates between the curated rows.
* **Remote Interaction**: OK = Direct Play highest quality print. Long-press / Menu = Quality picker.

---

## 3. IMDb GraphQL Service Architecture

* **Endpoint**: `POST https://api.graphql.imdb.com/`
* **Headers**:
  * `Content-Type: application/json`
  * `Origin: https://www.imdb.com`
  * `Referer: https://www.imdb.com/`
  * `x-imdb-client-name: imdb-web-next`
  * `User-Agent: Mozilla/5.0`
* **Verified Sort Metrics**:
  1. *Current Buzz*: `sort: { sortBy: POPULARITY, sortOrder: ASC }`
  2. *All-Time Popular*: `sort: { sortBy: USER_RATING_COUNT, sortOrder: DESC }`
  3. *Box Office Hits*: `sort: { sortBy: BOX_OFFICE_GROSS_DOMESTIC, sortOrder: DESC }`
  4. *Comedy Filter*: `genreConstraint: { anyGenreIds: ["Comedy"] }`
* **Batch Fetching & Caching Strategy**:
  * Fetch `first: 50` in **1 single network request** per lane (~400ms).
  * Cache responses in SQLite / JSON on backend for **12 hours**.
  * Server makes total of **~6 requests per day** across all lanes. Invisible to AWS WAF.
  * TMDb official API resolves posters/backdrops via `/find/{imdb_id}?external_source=imdb_id`.
  * Fallback: If IMDb GraphQL returns non-200, silently fall back to TMDb discover endpoint.

---

## 4. Upstream Sync & "Recent Updates" Strategy

* Page 1 of current year directory (e.g. `moviezda.net/tamil-2026-movies/`) acts as chronological update log.
* Background worker checks Page 1 every 2 hours.
* Checks sub-links for `Original` / `HDRip` tags.
* Emits feed of newly indexed high-quality uploads to Lane 2.

---

## 5. Cache & Asset Migration

* **Reusable Assets**:
  * `domain_cache.json`: Retain active mirror domain resolving logic.
  * D-pad remote spatial navigation & row column-memory algorithms from old Flutter app.
  * TMDb client service integration & in-memory caching.
* **Discarded Assets**:
  * Video stream reverse proxy routes (`/streams/proxy/*`).
  * Manual server IP configuration dialogs.
  * WebView virtual cursor & embed injection engine.


  "https://vidsrc2.ru",
  "https://vidsrc.ir",
  "https://vidsrcme.ru",
  "https://vidsrcme.su",
  "https://vidsrc-me.ru",
  "https://vidsrc.me",
  "https://vidsrc.io",
  "https://vidsrc.tw"