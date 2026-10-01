import sys
import time
import asyncio
import logging
import json
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import Callable, Any
from urllib.parse import urlparse
from backend.session import get_session
from backend.scrappers.base import BaseScraper, MediaItem, StreamSource

logger = logging.getLogger(__name__)

DATA_DIR = Path(__file__).resolve().parents[3] / "data"
CONFIG_PATH = DATA_DIR / "vidsrc.json"

def get_vidsrc_config() -> tuple[str | None, list[str]]:
    if not CONFIG_PATH.exists():
        logger.warning(f"[VidSrc] Missing {CONFIG_PATH}. No active domain configured. Scraper aborted.")
        return None, []
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
            primary = data.get("primary_domain") or data.get("domain")
            domains = data.get("domains") or []
            if not primary or not primary.strip():
                logger.warning(f"[VidSrc] No active domain configured in {CONFIG_PATH}. Scraper aborted.")
                return None, []
            return primary.strip().rstrip("/"), [d.rstrip("/") for d in domains]
    except Exception as e:
        logger.warning(f"[VidSrc] Failed to read {CONFIG_PATH}: {e}. Scraper aborted.")
        return None, []

FIREFOX_PREFS = {
    "media.autoplay.default": 0,
    "media.autoplay.blocking_policy": 0,
    "media.block-autoplay-until-in-foreground": False,
    "media.autoplay.allow-extension-background-pages": True,
    "network.dns.disableIPv6": True,
    "network.trr.mode": 5,
}

ABORT_RESOURCE_TYPES = {"image", "font", "media"}
STUB_JS_PATTERNS = ("disable-devtool.js", "cloudflareinsights.com/beacon.min.js")

@dataclass(slots=True)
class StreamResult:
    success: bool
    m3u8_url: str | None = None
    headers: dict[str, str] | None = None
    elapsed_ms: int = 0
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

class HLSExtractorService:
    def __init__(self):
        self._playwright = None
        self._browser = None

    async def start(self):
        if self._browser is not None:
            return
        try:
            from playwright.async_api import async_playwright
        except ImportError as err:
            raise RuntimeError(
                "Playwright is not installed. Install with 'pip install playwright && playwright install firefox'"
            ) from err

        self._playwright = await async_playwright().start()
        self._browser = await self._playwright.firefox.launch(
            headless=True,
            firefox_user_prefs=FIREFOX_PREFS,
        )

    async def stop(self):
        if self._browser:
            await self._browser.close()
            self._browser = None
        if self._playwright:
            await self._playwright.stop()
            self._playwright = None

    async def extract_m3u8(
        self,
        target_url: str,
        wrap_in_parent_iframe: bool = False,
        timeout_ms: int = 15000,
        on_step: Callable[[str, str], None] | None = None
    ) -> StreamResult:
        start_time = time.monotonic()
        if not self._browser:
            await self.start()

        context = await self._browser.new_context(
            viewport={"width": 1280, "height": 720}
        )
        page = await context.new_page()
        manifest_event = asyncio.Event()
        captured_data: dict[str, Any] = {}

        context.on("page", lambda popup: asyncio.create_task(popup.close()))

        async def route_handler(route):
            req = route.request
            url_lower = req.url.lower()

            if any(pat in url_lower for pat in STUB_JS_PATTERNS):
                await route.fulfill(
                    status=200,
                    content_type="application/javascript",
                    body="/* neutralized */",
                )
                return

            if req.resource_type in ABORT_RESOURCE_TYPES and ".m3u8" not in url_lower:
                await route.abort()
                return

            await route.continue_()

        await context.route("**/*", route_handler)

        async def on_request(req):
            if manifest_event.is_set():
                return
            if ".m3u8" in req.url.lower():
                try:
                    all_headers = await req.all_headers()
                except Exception:
                    all_headers = {}
                captured_data["url"] = req.url
                captured_data["headers"] = {
                    "Referer": all_headers.get("referer", ""),
                    "Origin": all_headers.get("origin", ""),
                    "User-Agent": all_headers.get("user-agent", ""),
                }
                manifest_event.set()

        async def on_response(res):
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
                if on_step:
                    on_step("navigating", f"Navigating via iframe shell: {shell_url}")
                await page.goto(shell_url, wait_until="domcontentloaded", timeout=timeout_ms)
                player_locator = (
                    page.frame_locator("#playerFrame")
                    .frame_locator("#player_iframe")
                    .locator("#bigPlay, #player, .jw.landing, button.jw-bigplay")
                    .first
                )
            else:
                if on_step:
                    on_step("navigating", f"Navigating to {target_url}")
                await page.goto(target_url, wait_until="domcontentloaded", timeout=timeout_ms)
                if await page.locator("#playerFrame").count() > 0:
                    player_locator = (
                        page.frame_locator("#playerFrame")
                        .frame_locator("#player_iframe")
                        .locator("#bigPlay, #player, .jw.landing, button.jw-bigplay")
                        .first
                    )
                else:
                    player_locator = (
                        page.frame_locator("#player_iframe")
                        .locator("#bigPlay, #player, .jw.landing, button.jw-bigplay")
                        .first
                    )

            if on_step:
                on_step("waiting_player", "Waiting for player element")
            await player_locator.wait_for(state="visible", timeout=timeout_ms)

            for attempt in range(4):
                if manifest_event.is_set():
                    break
                if on_step:
                    on_step("clicking", f"Sending trusted click {attempt + 1}")
                await player_locator.click(force=True)
                try:
                    await asyncio.wait_for(manifest_event.wait(), timeout=1.5)
                    break
                except asyncio.TimeoutError:
                    continue

            if not manifest_event.is_set():
                try:
                    await asyncio.wait_for(manifest_event.wait(), timeout=5.0)
                except asyncio.TimeoutError:
                    pass

            elapsed = int((time.monotonic() - start_time) * 1000)
            if manifest_event.is_set() and "url" in captured_data:
                if on_step:
                    on_step("extracted", f"HLS stream captured: {captured_data['url']}")
                return StreamResult(
                    success=True,
                    m3u8_url=captured_data["url"],
                    headers=captured_data.get("headers", {}),
                    elapsed_ms=elapsed,
                )

            return StreamResult(
                success=False,
                elapsed_ms=elapsed,
                error="HLS manifest URL not captured within timeout."
            )

        except Exception as exc:
            elapsed = int((time.monotonic() - start_time) * 1000)
            return StreamResult(success=False, elapsed_ms=elapsed, error=str(exc))
        finally:
            await context.close()

_extractor_singleton: HLSExtractorService | None = None

def get_extractor_service() -> HLSExtractorService:
    global _extractor_singleton
    if _extractor_singleton is None:
        _extractor_singleton = HLSExtractorService()
    return _extractor_singleton

def build_embed_url(
    base_domain: str,
    media_id: str,
    media_type: str = "movie",
    season: int | None = None,
    episode: int | None = None
) -> str:
    base = base_domain.rstrip('/')
    if media_type == "tv":
        s = season if season is not None and season > 0 else 1
        e = episode if episode is not None and episode > 0 else 1
        return f"{base}/embed/tv/{media_id}/{s}/{e}"
    return f"{base}/embed/movie/{media_id}"

class VidSrcScraper(BaseScraper):
    name = "VidSrc"

    def __init__(self, extractor: HLSExtractorService | None = None):
        self._extractor = extractor or get_extractor_service()

    async def _check_content_info(self, media: MediaItem, media_id: str, primary_domain: str = "https://vidsrc.sh") -> tuple[bool, str, str | None]:
        if media.media_type == "tv":
            s = media.season if media.season is not None and media.season > 0 else 1
            e = media.episode if media.episode is not None and media.episode > 0 else 1
            info_url = f"{primary_domain}/info/tv/{media_id}/{s}/{e}.json"
        else:
            info_url = f"{primary_domain}/info/movie/{media_id}.json"

        try:
            session = get_session()
            resp = await session.get(info_url, timeout=4.0)
            if resp.status_code == 404:
                return False, "Auto", None
            if resp.status_code == 200:
                data = resp.json()
                if data.get("status_code") == 404 or "error" in data:
                    return False, "Auto", None
                quality = data.get("quality") or "1080p"
                embed_url = data.get("embed_url") or data.get("embed_url_tmdb")
                return True, quality, embed_url
        except Exception as e:
            logger.debug(f"[{self.name}] Info API check error: {e}")

        return True, "Auto", None

    async def scrape(
        self,
        media: MediaItem,
        on_progress: Callable[[str, str], None] | None = None
    ) -> list[StreamSource]:
        results: list[StreamSource] = []

        media_id = media.imdb_id or (str(media.tmdb_id) if media.tmdb_id else None)
        if not media_id:
            logger.warning(f"[{self.name}] No valid IMDb or TMDb identifier provided for '{media.title}'.")
            return results

        primary_domain, _ = get_vidsrc_config()
        if not primary_domain:
            return results

        if on_progress:
            on_progress("info", f"Checking VidSrc availability for '{media.title}'")

        is_available, quality_label, direct_embed_url = await self._check_content_info(media, media_id, primary_domain=primary_domain)
        if not is_available:
            logger.info(f"[{self.name}] '{media.title}' is not available on VidSrc (404).")
            if on_progress:
                on_progress("not_found", f"Title not hosted on VidSrc")
            return results

        candidate_urls: list[str] = []
        if direct_embed_url:
            candidate_urls.append(direct_embed_url)
        else:
            url = build_embed_url(
                base_domain=primary_domain,
                media_id=media_id,
                media_type=media.media_type,
                season=media.season,
                episode=media.episode
            )
            candidate_urls.append(url)

        for embed_url in candidate_urls:
            if on_progress:
                on_progress("probe", f"Extracting from: {embed_url}")

            try:
                res = await self._extractor.extract_m3u8(
                    target_url=embed_url,
                    wrap_in_parent_iframe=False,
                    timeout_ms=15000,
                    on_step=on_progress
                )
                if res.success and res.m3u8_url:
                    results.append(
                        StreamSource(
                            url=res.m3u8_url,
                            provider=f"VidSrc ({quality_label})",
                            quality=quality_label,
                            headers=res.headers or {},
                            ttl=7200,
                            priority=30
                        )
                    )
                    break
                elif res.error:
                    logger.debug(f"[{self.name}] Extraction failed on {embed_url}: {res.error}")
            except Exception as e:
                logger.warning(f"[{self.name}] Extraction error on {embed_url}: {e}")

        return results

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

    def progress_callback(step: str, msg: str):
        print(f"[*] [{step}] {msg}")

    async def main():
        args = sys.argv[1:]
        title = args[0] if len(args) > 0 else "The Matrix"
        year = int(args[1]) if len(args) > 1 and args[1].isdigit() else 1999
        tmdb_id = int(args[2]) if len(args) > 2 and args[2].isdigit() else 603
        imdb_id = args[3] if len(args) > 3 else "tt0133093"
        media_type = args[4] if len(args) > 4 else "movie"
        season = int(args[5]) if len(args) > 5 and args[5].isdigit() else None
        episode = int(args[6]) if len(args) > 6 and args[6].isdigit() else None

        item = MediaItem(
            title=title,
            year=year,
            tmdb_id=tmdb_id,
            imdb_id=imdb_id,
            media_type=media_type,
            season=season,
            episode=episode
        )

        print(f"=== Testing VidSrcScraper ===")
        print(f"MediaItem: {item}")
        scraper = VidSrcScraper()
        sources = await scraper.scrape(item, on_progress=progress_callback)

        print(f"\n=== Found {len(sources)} Stream Source(s) ===")
        for s in sources:
            print(f"- Provider: {s.provider} | Quality: {s.quality}")
            print(f"  URL: {s.url}")
            print(f"  Headers: {s.headers}")

        await scraper._extractor.stop()

    asyncio.run(main())
