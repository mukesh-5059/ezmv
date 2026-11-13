# Curated Streaming Scrapers

Curated and empirically verified client-side JavaScript scrapers for anime, Indian movies (Tamil/Hindi), and English movies/series.

## Sources Overview

| File | Provider | Type | Primary Language | Output Stream Format | Origin Repo |
| :--- | :--- | :--- | :--- | :--- | :--- |
| [`hianime.js`](./hianime.js) | **HiAnime** | Anime | English (Sub/Dub) | Native HLS (`.m3u8` up to 1080p @ 5.3 Mbps) | Zangetsu |
| [`gogo.js`](./gogo.js) | **AniGoGo** | Anime | English (Sub/Dub) | Native HLS (`.m3u8` up to 1080p, Megavid) | Miru |
| [`hdhub.js`](./hdhub.js) | **HDHub4u** | Movies / Series | Hindi / Tamil / English | Direct MKV/MP4 (HEVC/x264, Dual-Audio tracks) | Zangetsu |
| [`4khdhub.js`](./4khdhub.js) | **4K HDHub** | Movies / Series | English / Multi | Direct MKV/MP4 (Up to 2160p UHD / HDR) | Zangetsu |

---

## Runtime Interfaces

### 1. Zangetsu Interface (`hianime.js`, `hdhub.js`, `4khdhub.js`)
Executed in a QuickJS sandbox exposing:
- `fetch(url, options)` -> `{ ok, status, body, headers }`
- `base64ToBytes(str)` / `bytesToBase64(bytes)`
- `htmlText(html)`
- `absUrl(relative, base)`

Exported top-level functions:
- `getInfo()` -> `{ name, lang, baseUrl, type, version }`
- `search(query, page)` -> `[{ id, title, cover, url }]`
- `getDetail(url)` -> `{ title, cover, description, episodes: [...] }`
- `getVideoSources(episodeUrl)` -> `[{ url, quality, headers, subtitles }]`

### 2. Miru Interface (`gogo.js`)
Extends `Extension` base class:
- `search(kw, page)` -> `[{ title, url, cover }]`
- `detail(url)` -> `{ title, cover, desc, episodes: [{ title, urls: [...] }] }`
- `watch(url)` -> `{ type: 'hls', url, headers, subtitles }`
