# Stream URL Resolution & Scraper Pipeline — Handoff

## Summary & Current Architecture

The stream resolution and scraping pipeline is cleanly separated between the orchestrator ([`backend/scrappers/manager.py`](file:///home/mukes/dev/movies/backend/scrappers/manager.py)) and provider implementations ([`backend/scrappers/providers/isaimini/`](file:///home/mukes/dev/movies/backend/scrappers/providers/isaimini/)).

```
backend/scrappers/
├── base.py                   # MediaItem, StreamSource (url, provider, quality, headers, expires_at, ttl, priority)
├── manager.py                # Generic orchestrator, dynamic min() TTL cache & SSE broadcaster
└── providers/
    ├── isaimini/
    │   ├── constants.py      # INDIAN_LANGUAGES = {"ta", "te", "hi", "ml", "kn"}
    │   ├── crawler.py
    │   ├── domain.py
    │   ├── extractor.py
    │   ├── matcher.py
    │   ├── resolver.py       # URL resolver + exact expiry & priority extraction
    │   ├── scraper.py        # IsaiminiScraper (Language Guard + Extraction + Resolution)
    │   └── storage.py
    └── vidsrc/               # Isolated (handled by parallel agent)
```

---

## 1. Dynamic Cache TTL Mechanics

`Isaimini` provider parses exact expiry timestamps (`e=`, `etag=`, or base64 `dl=` parameter) and sets `StreamSource.expires_at`, `StreamSource.ttl`, and `StreamSource.priority`.

`ScraperManager` remains provider-agnostic, sorting streams by `priority` and computing effective cache TTL via `min(s.ttl for s in streams if s.ttl)` (with a minimum floor of 30s).

| Stream Type | Expiration Calculation | TTL Set in Response & Cache |
|---|---|---|
| **Raw `.php` links** (*Fastly / open.php*) | Decodes base64 `exp=` timestamp minus 30s safety buffer | **~300–330 seconds (~5.5 minutes)** |
| **Resolved direct URLs** (*mv1.uptomkv.ch*) | Decodes `e=<timestamp>` query parameter | **~864,000s (~10 days)** |
| **Multi-source bundle** (*e.g. VidSrc + Fastly*) | `min(all_streams_ttl)` | **Matches the shortest stream (~300s)** |
| **Empty results** | Fast retry window | **60 seconds** |

---

## 2. Isaimini Language & Origin Guard

To eliminate false-positive title token collisions on non-Indian titles (e.g. *The Matrix*) and save network bandwidth, `IsaiminiScraper.scrape()` checks:

```python
countries = media.origin_countries or []
is_indian_origin = (
    (media.original_language in INDIAN_LANGUAGES) or
    ("IN" in countries)
)
if (media.original_language or countries) and not is_indian_origin:
    return []  # Immediate fast-exit
```

---

## 3. Live Verification Test Results

| Title | Media Type & Language | Isaimini Action | Returned Streams | Cache TTL (`cache_expires_in`) |
|---|---|---|---|---|
| **The Matrix (1999)** | Movie (`en`, `US`) | **Skipped instantly** via Language Guard | 0 streams | `59s` (empty cache) |
| **Dude (2025)** | Movie (`ta`, `IN`) | **Scraped & Resolved** to `mv1.uptomkv.ch` | 3 streams (720p, 360p, 1080p) | `864,034s` (10 days) |
