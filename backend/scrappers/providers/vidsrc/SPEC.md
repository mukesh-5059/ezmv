# Technical Specification: Headless Firefox HLS (`master.m3u8`) Stream Extractor

## 1. Objective & System Overview

Build an asynchronous Python service using **Playwright (Headless Firefox)** (or **Camoufox** for stealth) that loads a protected video embed page, pierces a multi-layered cross-origin `<iframe>` hierarchy, neutralizes anti-devtools scripts, triggers playback via trusted hardware-level mouse clicks, and intercepts the resulting HLS `master.m3u8` manifest URL alongside its required HTTP context headers (`Referer`, `Origin`, `User-Agent`).

---

## 2. Target DOM & Security Topology

The target streaming provider isolates its video player across nested iframes and runs active anti-tamper checks:

* **Outer Iframe (`#playerFrame`):** Hosted on the primary embed domain with `src="/embed/movie/{imdb_id}"` and `allow="autoplay; fullscreen"`.
* **Inner Cross-Origin Iframe (`#player_iframe`):** Dynamically resolved via `data-api="/vs_src.php?type=movie&id={imdb_id}"` and hosted on an external rotating CDN domain (e.g., `https://cloudorchestranova.com/embed/movie/{imdb_id}?vs={token}`). It enforces `referrerpolicy="origin"` and `allow="autoplay; fullscreen; picture-in-picture; encrypted-media"`.
* **Click Target (`#player`):** Inside `#player_iframe`, the player starts as an uninitialized facade `<div id="player" class="jw landing">` that requires a trusted user click (`event.isTrusted === true`) to initialize JWPlayer and fetch the HLS manifest.
* **Anti-Tamper Kill Switch (`disable-devtool.js`):** `#player_iframe` loads `/embed/iframe_player/assets/disable-devtool.js` followed by an inline script containing `if (!window.DisableDevtool) return; function kill() { ... }`. If triggered, `kill()` pauses the `<video>`, strips its `src`, emits a `VS_DEVTOOLS` postMessage to the parent window, and wipes the DOM (`about:blank` / `innerHTML = ''`).
* **Third-Party Telemetry:** The inner frame also loads `https://static.cloudflareinsights.com/beacon.min.js`.

---

## 3. Architecture & Execution Pipeline

### Phase 1: Browser Pool & Preferences Configuration

* **Warm Browser Instance:** Launch a single persistent headless Firefox process on application startup and create an isolated `BrowserContext` per extraction request (~50ms overhead vs. ~1.5s cold boot).
* **Firefox Autoplay Overrides:** Configure `firefox_user_prefs` at launch so Gecko never blocks unmuted media execution in background/headless tabs:
  - `"media.autoplay.default": 0` (Allow all autoplay)
  - `"media.autoplay.blocking_policy": 0` (Disable sticky user-gesture activation check)
  - `"media.block-autoplay-until-in-foreground": False`
  - `"media.autoplay.allow-extension-background-pages": True`

### Phase 2: Network Interception & Anti-Tamper Neutralization

Attach a unified `context.route("**/*", ...)` handler before navigation:

1. **Neutralize `disable-devtool.js`:** Intercept any request matching `*disable-devtool.js*` and fulfill it with HTTP `200 OK`, `Content-Type: application/javascript`, and an empty body (`"/* stub */"`). **Do not use `route.abort()`**, as aborting triggers `<script onerror>` handlers; returning an empty `200 OK` keeps `window.DisableDevtool` undefined and safely exits the inline guard `if (!window.DisableDevtool) return;`.
2. **Block Bloat & Telemetry:** Abort requests where `request.resource_type` is in `{"image", "font", "media"}` or where the URL matches telemetry domains (`cloudflareinsights.com`, analytics, ad scripts).
3. **Preserve Stylesheets (`stylesheet`):** **Do not block CSS.** Blocking stylesheets collapses `<div id="player" class="jw landing">` to `0x0` pixels, which breaks Playwright's bounding-box visibility checks and prevents coordinate clicking.

### Phase 3: Dual-Layer HLS Stream Sniffing

Providers frequently disguise HLS manifests behind non-standard URLs (e.g., `.txt`, `.png`, or extensionless endpoints). Implement two listeners joined by an `asyncio.Event` (`manifest_found_event`) for instant short-circuiting:

1. **Fast Request Listener (`page.on("request")`):** If `.m3u8` appears in `request.url`, immediately capture `request.url` and `await request.all_headers()`, then set `manifest_found_event`.
2. **Deep Response Fallback (`page.on("response")`):** For `xhr` or `fetch` responses with status `200`, inspect `content-type` for `mpegurl` or read the first 128 bytes of the response text. If the body starts with `#EXTM3U` and contains `#EXT-X-STREAM-INF` (master playlist) or `#EXT-X-TARGETDURATION` (media playlist), capture the corresponding `response.request.url` and headers, then set `manifest_found_event`.

### Phase 4: Synthetic Parent Wrapper (Direct Embed Mode)

If the input to the service is a relative or direct embed path (e.g., `https://provider-domain.com/embed/movie/tt0364647`) rather than a full host webpage:

* Intercept a dummy route on the expected parent origin (`https://provider-domain.com/__shell__`) and fulfill it with a minimal HTML document containing `<iframe id="playerFrame" src="/embed/movie/tt0364647" allow="autoplay; fullscreen" width="1280" height="720"></iframe>`.
* This guarantees `window.self !== window.top`, `Sec-Fetch-Dest: iframe`, and valid `Referer`/`Origin` headers without loading a heavy parent webpage.

### Phase 5: Nested Iframe Piercing & Trusted Click Loop

1. **Popup Blocker:** Register `context.on("page", lambda p: asyncio.create_task(p.close()))` to immediately kill ad tabs spawned when clicking the landing player.
2. **Frame Traversal:** Use Playwright's `frame_locator` chain to pierce both iframes:
   - Mode A (Full Page): `page.frame_locator("#playerFrame").frame_locator("#player_iframe").locator("#player")`.
   - Mode B (Direct `/embed/` URL): `page.frame_locator("#player_iframe").locator("#player")`.
   - Fallback Selector: `iframe[src*='/embed/'] >> iframe >> #player, .jw.landing`.
3. **Click Retry Loop with Early Exit:** Wait for `#player` to become attached/visible, then fire up to 3 trusted clicks spaced `1.2s` apart while awaiting `manifest_found_event`. The first click often clears an invisible ad overlay; the second click initializes JWPlayer. The moment `manifest_found_event.is_set()` is true, break the loop and tear down the `BrowserContext`.

---

## 4. Data Contracts (Input / Output Schema)

### Input Payload

```json
{
  "target_url": "https://example-site.com/embed/movie/tt0364647",
  "parent_referer": "https://example-site.com/",
  "timeout_ms": 15000
}
```

### Output Payload

```json
{
  "success": true,
  "m3u8_url": "https://cdn-node.com/hls/tt0364647/master.m3u8?token=...",
  "headers": {
    "Referer": "https://cloudorchestranova.com/",
    "Origin": "https://cloudorchestranova.com",
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:136.0) Gecko/20100101 Firefox/136.0"
  },
  "is_master_playlist": true,
  "elapsed_ms": 1840,
  "error": null
}
```

---

## 5. Reference Implementation Blueprint

```python
import asyncio
import time
from dataclasses import dataclass, asdict
from typing import Optional, Dict
from urllib.parse import urlparse
from playwright.async_api import async_playwright, Browser, BrowserContext, Route, Request, Response

FIREFOX_PREFS = {
    "media.autoplay.default": 0,
    "media.autoplay.blocking_policy": 0,
    "media.block-autoplay-until-in-foreground": False,
    "media.autoplay.allow-extension-background-pages": True,
}

ABORT_RESOURCE_TYPES = {"image", "font", "media"}
STUB_JS_PATTERNS = ("disable-devtool.js", "cloudflareinsights.com/beacon.min.js")


@dataclass
class StreamResult:
    success: bool
    m3u8_url: Optional[str] = None
    headers: Optional[Dict[str, str]] = None
    elapsed_ms: int = 0
    error: Optional[str] = None

    def to_dict(self):
        return asdict(self)


class HLSExtractorService:
    def __init__(self):
        self._playwright = None
        self._browser: Optional[Browser] = None

    async def start(self):
        """Initialize persistent headless Firefox instance."""
        self._playwright = await async_playwright().start()
        self._browser = await self._playwright.firefox.launch(
            headless=True,
            firefox_user_prefs=FIREFOX_PREFS,
        )

    async def stop(self):
        """Gracefully close browser and Playwright driver."""
        if self._browser:
            await self._browser.close()
        if self._playwright:
            await self._playwright.stop()

    async def extract_m3u8(
        self,
        target_url: str,
        wrap_in_parent_iframe: bool = False,
        timeout_ms: int = 15000,
    ) -> StreamResult:
        start_time = time.monotonic()
        if not self._browser:
            await self.start()

        context: BrowserContext = await self._browser.new_context(
            viewport={"width": 1280, "height": 720}
        )
        page = await context.new_page()
        manifest_event = asyncio.Event()
        captured_data: Dict[str, any] = {}

        # 1. Auto-close ad popup tabs
        context.on("page", lambda popup: asyncio.create_task(popup.close()))

        # 2. Network Router: Neutralize disable-devtool.js & strip heavy assets
        async def route_handler(route: Route):
            req = route.request
            url_lower = req.url.lower()

            # Stub anti-tamper and beacon scripts with 200 OK empty JS
            if any(pat in url_lower for pat in STUB_JS_PATTERNS):
                await route.fulfill(
                    status=200,
                    content_type="application/javascript",
                    body="/* neutralized */",
                )
                return

            # Drop images, fonts, and raw video segments (keep CSS for bounding boxes!)
            if req.resource_type in ABORT_RESOURCE_TYPES and ".m3u8" not in url_lower:
                await route.abort()
                return

            await route.continue_()

        await context.route("**/*", route_handler)

        # 3. Fast Request Sniffer (URL matches .m3u8)
        async def on_request(req: Request):
            if manifest_event.is_set():
                return
            if ".m3u8" in req.url.lower():
                all_headers = await req.all_headers()
                captured_data["url"] = req.url
                captured_data["headers"] = {
                    "Referer": all_headers.get("referer", ""),
                    "Origin": all_headers.get("origin", ""),
                    "User-Agent": all_headers.get("user-agent", ""),
                }
                manifest_event.set()

        # 4. Deep Response Sniffer (Disguised #EXTM3U manifests)
        async def on_response(res: Response):
            if manifest_event.is_set() or res.status != 200:
                return
            if res.request.resource_type in ("xhr", "fetch", "other"):
                ct = res.headers.get("content-type", "").lower()
                if "mpegurl" in ct or ".m3u8" not in res.url.lower():
                    try:
                        body = await res.text()
                        if body.lstrip().startswith("#EXTM3U"):
                            all_headers = await res.request.all_headers()
                            captured_data["url"] = res.url
                            captured_data["headers"] = {
                                "Referer": all_headers.get("referer", ""),
                                "Origin": all_headers.get("origin", ""),
                                "User-Agent": all_headers.get("user-agent", ""),
                            }
                            manifest_event.set()
                    except Exception:
                        pass

        page.on("request", lambda req: asyncio.create_task(on_request(req)))
        page.on("response", lambda res: asyncio.create_task(on_response(res)))

        try:
            # 5. Navigate (either via synthetic parent shell or directly)
            if wrap_in_parent_iframe:
                parsed = urlparse(target_url)
                shell_url = f"{parsed.scheme}://{parsed.netloc}/__iframe_shell__"
                await page.route(
                    shell_url,
                    lambda r: r.fulfill(
                        status=200,
                        content_type="text/html",
                        body=f'<!DOCTYPE html><html><body style="margin:0">'
                             f'<iframe id="playerFrame" src="{target_url}" '
                             f' width="1280" height="720" allow="autoplay; fullscreen"></iframe>'
                             f'</body></html>',
                    ),
                )
                await page.goto(shell_url, wait_until="domcontentloaded", timeout=timeout_ms)
                player_locator = (
                    page.frame_locator("#playerFrame")
                    .frame_locator("#player_iframe")
                    .locator("#player, .jw.landing")
                    .first
                )
            else:
                await page.goto(target_url, wait_until="domcontentloaded", timeout=timeout_ms)
                # Support both 2-level (#playerFrame -> #player_iframe) and 1-level (#player_iframe)
                if await page.locator("#playerFrame").count() > 0:
                    player_locator = (
                        page.frame_locator("#playerFrame")
                        .frame_locator("#player_iframe")
                        .locator("#player, .jw.landing")
                        .first
                    )
                else:
                    player_locator = (
                        page.frame_locator("#player_iframe")
                        .locator("#player, .jw.landing")
                        .first
                    )

            # 6. Wait for inner #player and send trusted clicks until manifest_event fires
            await player_locator.wait_for(state="visible", timeout=timeout_ms)

            for _ in range(4):
                if manifest_event.is_set():
                    break
                await player_locator.click(force=True)
                try:
                    await asyncio.wait_for(manifest_event.wait(), timeout=1.5)
                    break
                except asyncio.TimeoutError:
                    continue

            # Final wait window if token resolution is still in flight
            if not manifest_event.is_set():
                await asyncio.wait_for(manifest_event.wait(), timeout=5.0)

            elapsed = int((time.monotonic() - start_time) * 1000)
            return StreamResult(
                success=True,
                m3u8_url=captured_data["url"],
                headers=captured_data["headers"],
                elapsed_ms=elapsed,
            )

        except Exception as exc:
            elapsed = int((time.monotonic() - start_time) * 1000)
            return StreamResult(success=False, elapsed_ms=elapsed, error=str(exc))
        finally:
            await context.close()
```

---

## 6. Verification Checklist

1. **Verify `disable-devtool.js` Bypass:** Confirm that `window.DisableDevtool` evaluates to `undefined` inside `#player_iframe` and that no `VS_DEVTOOLS` postMessage is emitted.
2. **Verify Header Fidelity:** Confirm that `result.headers["Referer"]` matches the inner iframe's origin (`https://cloudorchestranova.com/`) rather than the outer page's URL, honoring `referrerpolicy="origin"`.
3. **Verify Sub-2-Second Teardown:** Confirm that `manifest_event.set()` immediately unblocks `asyncio.wait_for()` and closes the `BrowserContext` without waiting for `.ts` or `.m4s` video segments to download.
