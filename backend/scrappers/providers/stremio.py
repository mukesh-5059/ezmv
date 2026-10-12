import re
import difflib
import logging
from typing import Callable
from urllib.parse import quote
from backend.session import get_session
from backend.scrappers.base import BaseScraper, MediaItem, StreamSource

logger = logging.getLogger(__name__)

SCENE_JUNK_REGEX = re.compile(
    r'\b(2160p|1080p|720p|480p|360p|4k|uhd|fhd|hd|sd|web-?dl|webrip|bluray|bdrip|brrip|hdtv|remux|'
    r'x264|x265|hevc|h\.264|h\.265|10bit|hdr10\+|hdr10|hdr|dv|dovi|dolby\s*vision|atmos|'
    r'ddp\s*5\.1|dd\+\s*5\.1|dd\s*5\.1|ac3|eac3|aac|dts-hd|dts|esub|esubs|msub|multi|dual|'
    r'hindi|tamil|telugu|kannada|malayalam|english|uncut|proper|repack|imax|amzn|nf|dsnp|bcore)\b',
    re.I
)

def clean_tokens(text: str) -> list[str]:
    return [w for w in re.findall(r'[a-z0-9]+', (text or "").lower()) if w]

def extract_file_title_and_year(filename: str) -> tuple[str, int | None]:
    clean_name = re.sub(r'\.(mkv|mp4|avi|webm)$', '', filename, flags=re.I)
    clean_name = clean_name.replace('.', ' ').replace('_', ' ').replace('-', ' ')
    
    year_match = re.search(r'\b(19\d\d|20\d\d)\b', clean_name)
    file_year = int(year_match.group(1)) if year_match else None
    
    if year_match:
        raw_title = clean_name[:year_match.start()].strip()
    else:
        raw_title = SCENE_JUNK_REGEX.split(clean_name)[0].strip()
        
    return raw_title, file_year

def is_title_match(media: MediaItem, filename: str) -> bool:
    if not filename:
        return True
    
    file_title, file_year = extract_file_title_and_year(filename)
    
    if file_year and media.year and abs(file_year - media.year) > 1:
        return False
        
    target_tokens = clean_tokens(media.title)
    file_tokens = clean_tokens(file_title)
    
    if not target_tokens:
        return True
    if not file_tokens:
        return False
        
    target_set = set(target_tokens)
    file_set = set(file_tokens)
    
    if not target_set.issubset(file_set):
        target_str = " ".join(target_tokens)
        file_str = " ".join(file_tokens)
        sim = difflib.SequenceMatcher(None, target_str, file_str).ratio()
        return sim >= 0.75
        
    extra_tokens = file_set - target_set
    if len(extra_tokens) > len(target_tokens) and len(target_tokens) <= 2:
        target_str = " ".join(target_tokens)
        file_str = " ".join(file_tokens)
        sim = difflib.SequenceMatcher(None, target_str, file_str).ratio()
        return sim >= 0.60
        
    return True

def parse_stremio_stream(
    raw_stream: dict,
    provider_name: str,
    media: MediaItem,
) -> StreamSource | None:
    url = raw_stream.get("url")
    if not url or not url.startswith("http"):
        return None

    raw_name = (raw_stream.get("name") or "").replace("\n", " ").strip()
    raw_desc = (raw_stream.get("description") or "").strip()
    hints = raw_stream.get("behaviorHints") or {}
    raw_filename = hints.get("filename") or ""

    if not raw_filename:
        first_line = raw_desc.splitlines()[0] if raw_desc else ""
        if any(ext in first_line.lower() for ext in [".mkv", ".mp4", ".avi"]):
            raw_filename = first_line.strip("[]() ")

    if raw_filename and not is_title_match(media, raw_filename):
        logger.debug(f"[{provider_name}] Discarded mismatched title: '{raw_filename}' (expected '{media.title}')")
        return None

    full_text = f"{raw_name} {raw_desc} {raw_filename}"

    quality = "720p"
    if re.search(r'\b(2160p|4k|uhd)\b', full_text, re.I):
        quality = "4K UHD"
    elif re.search(r'\b(1080p|fhd)\b', full_text, re.I):
        quality = "1080p"
    elif re.search(r'\b(720p)\b', full_text, re.I):
        quality = "720p"
    elif re.search(r'\b(480p|360p|sd)\b', full_text, re.I):
        quality = "480p SD"

    size_mb = None
    video_size = hints.get("videoSize")
    if video_size and video_size > 0:
        size_mb = round(video_size / (1024 * 1024), 2)
    else:
        size_match = re.search(r'💾?\s*(\d+(?:\.\d+)?)\s*(GB|MB)', full_text, re.I)
        if size_match:
            val = float(size_match.group(1))
            unit = size_match.group(2).upper()
            size_mb = round(val * 1024 if unit == "GB" else val, 2)

    formatted_size = None
    if size_mb:
        if size_mb >= 1024:
            formatted_size = f"{round(size_mb / 1024, 2)} GB"
        else:
            formatted_size = f"{int(size_mb)} MB"

    bitrate_kbps = None
    bitrate_str = None
    bitrate_match = re.search(r'~(\d+(?:\.\d+)?)\s*Mbps', full_text, re.I)
    if bitrate_match:
        val = float(bitrate_match.group(1))
        bitrate_kbps = int(val * 1000)
        bitrate_str = f"{val} Mbps"
    else:
        kbps_match = re.search(r'~(\d+)\s*kbps', full_text, re.I)
        if kbps_match:
            bitrate_kbps = int(kbps_match.group(1))
            bitrate_str = f"{bitrate_kbps} kbps"
        elif size_mb and media.runtime_minutes and media.runtime_minutes > 0:
            total_sec = media.runtime_minutes * 60
            calc_kbps = int((size_mb * 8 * 1024) / total_sec)
            bitrate_kbps = calc_kbps
            if calc_kbps >= 1000:
                bitrate_str = f"{round(calc_kbps / 1000, 1)} Mbps"
            else:
                bitrate_str = f"{calc_kbps} kbps"

    languages = []
    lang_patterns = [
        (r'\b(tam|tamil)\b', 'Tamil'),
        (r'\b(tel|telugu)\b', 'Telugu'),
        (r'\b(hin|hindi)\b', 'Hindi'),
        (r'\b(kan|kannada)\b', 'Kannada'),
        (r'\b(mal|malayalam)\b', 'Malayalam'),
        (r'\b(eng|english)\b', 'English'),
        (r'\b(french|fre|fra)\b', 'French'),
        (r'\b(spanish|spa)\b', 'Spanish'),
        (r'\b(korean|kor)\b', 'Korean'),
        (r'\b(japanese|jap)\b', 'Japanese'),
        (r'\b(bengali|ben)\b', 'Bengali'),
    ]
    for pat, name in lang_patterns:
        if re.search(pat, full_text, re.I) and name not in languages:
            languages.append(name)

    source = None
    for s_name in ["MovieBox", "4KHDHub", "HDHub4u", "VegaMovies", "VAPlayer", "CineFreak", "SuperStream", "ShowBox", "VidSrc"]:
        if s_name.lower() in full_text.lower():
            source = s_name
            break

    host = None
    host_checks = [
        ("pixeldrain", "PixelDrain"),
        ("hubcloud", "HubCloud"),
        ("r2.cloudflarestorage", "Cloudflare R2"),
        ("fsl", "FSL"),
        ("hakunaymatata", "Sacdn"),
        ("googleusercontent", "GDrive"),
        ("hubcdn", "HubCDN"),
        ("fastdl", "FastDL"),
    ]
    for pattern, h_name in host_checks:
        if pattern in url.lower() or pattern in full_text.lower():
            host = h_name
            break

    headers = dict(raw_stream.get("headers") or {})
    if not any(k.lower() == "user-agent" for k in headers):
        headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    priority = 50
    if media.original_language == "ta":
        if "Tamil" in languages:
            priority = 10
        elif "Hindi" in languages and "Tamil" not in languages:
            priority = 85
    elif media.original_language == "en":
        if "English" in languages or not languages:
            priority = 10

    if quality == "4K UHD":
        priority -= 5
    elif quality == "720p":
        priority += 10
    elif quality == "480p SD":
        priority += 20

    clean_file = raw_filename if raw_filename else None

    return StreamSource(
        url=url,
        provider=provider_name,
        quality=quality,
        headers=headers,
        ttl=10800,
        priority=priority,
        size_mb=size_mb,
        formatted_size=formatted_size,
        bitrate_kbps=bitrate_kbps,
        bitrate_str=bitrate_str,
        languages=languages,
        source=source,
        host=host,
        filename=clean_file,
    )


class StremioScraper(BaseScraper):
    def __init__(self, name: str, manifest_url: str):
        self.name = name
        self.manifest_url = manifest_url
        self.base_url = manifest_url.rsplit("/manifest.json", 1)[0] if manifest_url else ""

    async def scrape(
        self,
        media: MediaItem,
        on_progress: Callable[[str, str], None] | None = None
    ) -> list[StreamSource]:
        results: list[StreamSource] = []
        if not self.manifest_url:
            return results

        target_id = media.imdb_id
        if not target_id:
            return results

        if media.media_type == "tv":
            season = media.season or 1
            episode = media.episode or 1
            stream_endpoint = f"{self.base_url}/stream/series/{quote(target_id)}:{season}:{episode}.json"
        else:
            stream_endpoint = f"{self.base_url}/stream/movie/{quote(target_id)}.json"

        if on_progress:
            on_progress("searching", f"Fetching {self.name} streams for {media.title}...")

        session = get_session()
        try:
            resp = await session.get(stream_endpoint, timeout=20.0)
            if resp.status_code != 200:
                logger.warning(f"[{self.name}] HTTP {resp.status_code} from {stream_endpoint}")
                return results

            data = resp.json()
            raw_streams = data.get("streams", [])
            for s in raw_streams:
                parsed = parse_stremio_stream(s, self.name, media)
                if parsed:
                    results.append(parsed)

            if on_progress:
                on_progress("extracted", f"Discovered {len(results)} {self.name} streams.")
        except Exception as e:
            logger.error(f"[{self.name}] Error scraping {media.title}: {e}")

        return results
