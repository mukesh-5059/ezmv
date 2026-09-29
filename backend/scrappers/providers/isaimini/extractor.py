import re
import logging
from urllib.parse import urlparse, quote
from bs4 import BeautifulSoup
from backend.scrappers.base import StreamSource
from .constants import DEFAULT_HEADERS
from .crawler import detect_print_category
from .storage import log_file_id

logger = logging.getLogger(__name__)

async def resolve_direct_url(session, url: str) -> str:
    """
    Resolves 302 redirects to the final direct .mp4 media URL.
    """
    if "download.php" not in url and ".php" not in url and "uptomkv" not in url and "fastbytes" not in url:
        return url

    parsed = urlparse(url)
    origin = f"{parsed.scheme}://{parsed.netloc}/"
    headers = {
        "User-Agent": DEFAULT_HEADERS["User-Agent"],
        "Referer": origin
    }
    try:
        resp = await session.get(url, headers=headers, allow_redirects=False, timeout=5.0)
        if resp.status_code in (301, 302, 303, 307, 308):
            loc = resp.headers.get("Location") or resp.headers.get("location")
            if loc:
                resolved = quote(str(loc), safe=":/%?&=#+,-")
                logger.info(f"[Isaimini:Extractor] Resolved 302 redirect: {url} -> {resolved}")
                return resolved
    except Exception as e:
        logger.warning(f"[Isaimini:Extractor] Failed to resolve direct redirect for {url}: {e}")
    return url

async def extract_streams_from_resolution(
    session,
    res_url: str,
    res_name: str,
    base_url: str,
    root_soup: BeautifulSoup | None,
    movie_page_url: str,
    tmdb_id: int | None,
    title: str
) -> list[StreamSource]:
    """
    Given a resolution download page URL, traverses download intermediate pages,
    extracts the onestream file ID, and parses direct HTML5 video stream links.
    """
    results: list[StreamSource] = []
    try:
        resp = await session.get(res_url, headers=DEFAULT_HEADERS, timeout=8.0)
        if resp.status_code != 200:
            return results
        soup = BeautifulSoup(resp.text, "html.parser")
        category = detect_print_category(soup, root_soup, res_name, res_url, movie_page_url)

        file_links = []
        for a in soup.find_all("a"):
            href = a.get("href")
            text = a.get_text().strip()
            if href and ("/download/" in href or "download" in text.lower()):
                file_url = href if href.startswith("http") else f"{base_url.rstrip('/')}{href}"
                file_links.append(file_url)

        for file_url in file_links[:1]:
            resp = await session.get(file_url, headers=DEFAULT_HEADERS, timeout=8.0)
            if resp.status_code != 200:
                continue
            soup = BeautifulSoup(resp.text, "html.parser")

            for a in soup.find_all("a"):
                href = a.get("href")
                if href and "download/file/" in href:
                    match = re.search(r'download/file/(\d+)', href)
                    if match:
                        file_id = match.group(1)
                        quality = "720p" if "720p" in res_name.lower() else ("1080p" if "1080p" in res_name.lower() else ("360p" if "360p" in res_name.lower() or "320" in res_name.lower() else "HD"))

                        if tmdb_id:
                            log_file_id(tmdb_id, title, file_id, quality)

                        player_url = f"https://play.onestream.today/stream/page/{file_id}"

                        # Attempt direct HTML5 video stream extraction
                        try:
                            player_resp = await session.get(
                                player_url,
                                headers={"Referer": file_url, "User-Agent": DEFAULT_HEADERS["User-Agent"]},
                                timeout=8.0
                            )
                            if player_resp.status_code == 200:
                                player_soup = BeautifulSoup(player_resp.text, "html.parser")
                                source_tag = player_soup.find("source")
                                if source_tag and source_tag.get("src"):
                                    direct_stream_url = source_tag.get("src").replace("&amp;", "&")
                                    parsed_stream = urlparse(direct_stream_url)
                                    stream_origin = f"{parsed_stream.scheme}://{parsed_stream.netloc}/"
                                    results.append(StreamSource(
                                        provider=f"{category} ({quality})",
                                        url=direct_stream_url,
                                        quality=quality,
                                        headers={
                                            "User-Agent": DEFAULT_HEADERS["User-Agent"],
                                            "Referer": stream_origin
                                        }
                                    ))
                                    logger.debug(f"[Isaimini:Extractor] Extracted direct stream ({quality}): {direct_stream_url}")
                                    return results
                        except Exception as e:
                            logger.error(f"[Isaimini:Extractor] Failed to extract direct stream from player: {e}")

                        # Fallback to player page URL if direct extraction fails
                        results.append(StreamSource(
                            provider=f"{category} ({quality})",
                            url=player_url,
                            quality=quality,
                            headers={
                                "User-Agent": DEFAULT_HEADERS["User-Agent"],
                                "Referer": file_url
                            }
                        ))
                        return results
    except Exception as e:
        logger.error(f"[Isaimini:Extractor] Error extracting streams for {res_url}: {e}")

    return results
