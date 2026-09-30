# Stream URL Resolution — Handoff

## Summary & Current Architecture

The stream resolution logic is strictly encapsulated inside [`backend/scrappers/providers/isaimini/`](file:///home/mukes/dev/movies/backend/scrappers/providers/isaimini/). The orchestrator [`backend/scrappers/manager.py`](file:///home/mukes/dev/movies/backend/scrappers/manager.py) remains completely generic and provider-agnostic.

### Encapsulation Layout

```
backend/scrappers/
├── base.py                   # Generic BaseScraper, MediaItem, StreamSource
├── manager.py                # Pure orchestrator, cache & event broadcaster
└── providers/
    ├── isaimini/
    │   ├── constants.py
    │   ├── crawler.py
    │   ├── domain.py
    │   ├── extractor.py
    │   ├── matcher.py
    │   ├── resolver.py       # Encapsulated Isaimini/Moviesda URL resolver
    │   ├── scraper.py        # IsaiminiScraper (runs extraction + resolution internally)
    │   └── storage.py
    └── vidsrc/               # Isolated (handled by parallel subagent)
```

---

### Isaimini Resolution Mechanics (`isaimini/resolver.py`)

1. **Uptomkv CDN (`download.php` -> `mv1.uptomkv.ch`):**
   - Resolves the 302 redirect on the server.
   - Percent-encodes path spaces and brackets (`%20`).
   - Verifies 206 streamability in an isolated session.
   - Returns sanitized direct `mv1.uptomkv.ch` URL to bypass player seek-loop.

2. **Fastly CDN (`open.php` -> `open.*.xyz` with `htag=`):**
   - Detects `htag=` / `fastly.` in redirect location.
   - Preserves and returns original `open.php` URL.
   - Allows client player (`mpv`/`media_kit`) to perform 302 and capture `Set-Cookie: download_token=...`.

---

## Verification

- `scripts/scrappers/test_isaimini.py "Dude" 2025 1321108`: All 3 streams autonomously resolved to `https://mv1.uptomkv.ch/files/...%20...mp4?h=...&e=...`.
- `manager.py`: Has zero provider-specific code.
