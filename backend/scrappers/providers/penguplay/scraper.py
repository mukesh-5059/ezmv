import re
import logging
from typing import Callable
from urllib.parse import quote
from backend.session import get_session
from backend.config import settings
from backend.scrappers.base import BaseScraper, MediaItem, StreamSource

logger = logging.getLogger(__name__)

DEFAULT_PENGUPLAY_MANIFEST_URL = (
    'https://pengu.uk/%7B%22auth_token%22%3A%22p30MBIC3MSN4Dbh5ZGDeVyGUzMoFFJUBEL4FNv36DWY%22%7D/manifest.json'
)

def sanitize_pengu_label(raw_name: str | None, raw_filename: str | None, raw_title: str | None) -> tuple[str, str]:
    text = f"{raw_name or ''} {raw_filename or ''} {raw_title or ''}"

    quality = "720p"
    if re.search(r'\b(2160p|4k|uhd)\b', text, re.I):
        quality = "4K UHD"
    elif re.search(r'\b(1080p|fhd)\b', text, re.I):
        quality = "1080p"
    elif re.search(r'\b(720p)\b', text, re.I):
        quality = "720p"
    elif re.search(r'\b(480p|360p|sd)\b', text, re.I):
        quality = "480p SD"
    elif re.search(r'\b(hd)\b', text, re.I):
        quality = "720p HD"

    audio_badge = ""
    languages = []
    if re.search(r'\b(tam|tamil)\b', text, re.I):
        languages.append("Tam")
    if re.search(r'\b(tel|telugu)\b', text, re.I):
        languages.append("Tel")
    if re.search(r'\b(hin|hindi)\b', text, re.I):
        languages.append("Hin")
    if re.search(r'\b(kan|kannada)\b', text, re.I):
        languages.append("Kan")
    if re.search(r'\b(mal|malayalam)\b', text, re.I):
        languages.append("Mal")
    if re.search(r'\b(eng|english)\b', text, re.I):
        languages.append("Eng")

    if len(languages) > 1:
        audio_badge = f" ({' + '.join(languages)})"
    elif len(languages) == 1:
        audio_badge = f" ({languages[0]})"
    elif re.search(r'\b(multi|dual)\b', text, re.I):
        audio_badge = " (Multi-Audio)"

    source_tag = ""
    for s_name in ["MovieBox", "SuperStream", "ShowBox", "VidSrc", "StreamTape"]:
        if s_name.lower() in text.lower():
            source_tag = f" • {s_name}"
            break

    label = f"PenguPlay • {quality}{audio_badge}{source_tag}"
    return label, quality

class PenguPlayScraper(BaseScraper):
    name = "PenguPlay"

    def __init__(self, manifest_url: str | None = None):
        self.manifest_url = (
            manifest_url
            or getattr(settings, "PENGUPLAY_MANIFEST_URL", None)
            or DEFAULT_PENGUPLAY_MANIFEST_URL
        )
        self.base_url = self.manifest_url.rsplit("/manifest.json", 1)[0]

    async def scrape(
        self,
        media: MediaItem,
        on_progress: Callable[[str, str], None] | None = None
    ) -> list[StreamSource]:
        results: list[StreamSource] = []

        if on_progress:
            on_progress("init", "Connecting to PenguPlay...")

        target_id = media.imdb_id
        if not target_id and media.tmdb_id:
            target_id = f"tmdb:{media.tmdb_id}"

        if not target_id:
            logger.warning("[PenguPlay] No valid IMDb or TMDB ID provided.")
            return results

        if media.media_type == "tv":
            season = media.season or 1
            episode = media.episode or 1
            stream_endpoint = f"{self.base_url}/stream/series/{quote(target_id)}:{season}:{episode}.json"
        else:
            stream_endpoint = f"{self.base_url}/stream/movie/{quote(target_id)}.json"

        if on_progress:
            on_progress("searching", f"Fetching PenguPlay streams for {media.title}...")

        session = get_session()
        try:
            resp = await session.get(stream_endpoint, timeout=12.0)
            if resp.status_code == 429:
                logger.warning(f"[PenguPlay] Rate limit exceeded (HTTP 429) on {stream_endpoint}")
                if on_progress:
                    on_progress("error", "PenguPlay rate limit exceeded.")
                return results

            if resp.status_code != 200:
                logger.warning(f"[PenguPlay] HTTP error {resp.status_code} from {stream_endpoint}")
                return results

            data = resp.json()
            raw_streams = data.get("streams", [])
            if on_progress:
                on_progress("extracted", f"Discovered {len(raw_streams)} PenguPlay streams.")

            for s in raw_streams:
                url = s.get("url")
                if not url:
                    continue

                hints = s.get("behaviorHints") or {}
                raw_filename = hints.get("filename")
                raw_title = s.get("title")
                raw_name = s.get("name")

                headers = {}
                proxy_headers = hints.get("proxyHeaders", {}).get("request")
                if isinstance(proxy_headers, dict):
                    headers.update(proxy_headers)
                elif not headers:
                    headers = {
                        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
                    }

                # Filter out direct external MP4 streams that lack CloudFront/nginx signed cookies (which return HTTP 428)
                if (".mp4" in url or ".mp4?" in url) and ("pengu.uk/direct/external" in url or "hakunaymatata" in url):
                    if not headers.get("Cookie"):
                        continue

                label, quality = sanitize_pengu_label(raw_name, raw_filename, raw_title)

                priority = 50
                if media.original_language and media.original_language == "ta":
                    if (raw_filename and re.search(r'\b(tam|tamil)\b', raw_filename, re.I)) or \
                       (raw_name and re.search(r'\b(tam|tamil)\b', raw_name, re.I)):
                        priority = 25
                elif quality == "4K UHD":
                    priority = 35
                elif quality == "1080p":
                    priority = 40

                results.append(
                    StreamSource(
                        url=url,
                        provider=label,
                        quality=quality,
                        headers=headers,
                        ttl=86400,
                        priority=priority
                    )
                )

        except Exception as e:
            logger.error(f"[PenguPlay] Error fetching streams: {e}")
            if on_progress:
                on_progress("error", f"PenguPlay error: {e}")

        return results
