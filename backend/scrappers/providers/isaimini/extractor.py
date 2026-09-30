import re
import logging
from bs4 import BeautifulSoup
from backend.scrappers.base import StreamSource
from .constants import DEFAULT_HEADERS
from .crawler import detect_print_category
from .storage import log_file_id

logger = logging.getLogger(__name__)

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
    extracts the direct stream link from download server anchors, and returns StreamSource items.
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
                href = a.get("href", "")
                if "download/file/" in href:
                    match = re.search(r'download/file/(\d+)', href)
                    if not match:
                        continue
                    file_id = match.group(1)
                    quality = "720p" if "720p" in res_name.lower() else ("1080p" if "1080p" in res_name.lower() else ("360p" if "360p" in res_name.lower() or "320" in res_name.lower() else "HD"))

                    if tmdb_id:
                        log_file_id(tmdb_id, title, file_id, quality)

                    # 1. First fetch download.moviespage.xyz/download/file/{file_id}
                    file_page_resp = await session.get(href, headers=DEFAULT_HEADERS, timeout=8.0)
                    if file_page_resp.status_code != 200:
                        continue
                    file_soup = BeautifulSoup(file_page_resp.text, "html.parser")

                    direct_stream_url = None

                    # Check for direct download/open links on file page
                    for fa in file_soup.find_all("a"):
                        f_href = fa.get("href", "")
                        if "download.php" in f_href or "open.php" in f_href:
                            direct_stream_url = f_href
                            break
                        elif "download/page/" in f_href:
                            # 2. Fetch download page (movies.downloadpage.xyz/download/page/{file_id})
                            page_resp = await session.get(f_href, headers={"Referer": href, "User-Agent": DEFAULT_HEADERS["User-Agent"]}, timeout=8.0)
                            if page_resp.status_code == 200:
                                page_soup = BeautifulSoup(page_resp.text, "html.parser")
                                for pa in page_soup.find_all("a"):
                                    p_href = pa.get("href", "")
                                    if "download.php" in p_href or "open.php" in p_href:
                                        direct_stream_url = p_href
                                        break
                            break

                    # 3. Fallback to onestream player page if not found directly
                    if not direct_stream_url:
                        player_url = f"https://play.onestream.today/stream/page/{file_id}"
                        try:
                            player_resp = await session.get(
                                player_url,
                                headers={"Referer": href, "User-Agent": DEFAULT_HEADERS["User-Agent"]},
                                timeout=8.0
                            )
                            if player_resp.status_code == 200:
                                player_soup = BeautifulSoup(player_resp.text, "html.parser")
                                source_tag = player_soup.find("source")
                                if source_tag and source_tag.get("src"):
                                    direct_stream_url = source_tag.get("src").replace("&amp;", "&")
                        except Exception:
                            pass

                    if direct_stream_url:
                        results.append(StreamSource(
                            provider=f"{category} ({quality})",
                            url=direct_stream_url,
                            quality=quality,
                            headers={"User-Agent": DEFAULT_HEADERS["User-Agent"]}
                        ))
                        logger.debug(f"[Isaimini:Extractor] Extracted direct stream ({quality}): {direct_stream_url}")
                        return results
    except Exception as e:
        logger.error(f"[Isaimini:Extractor] Error extracting streams for {res_url}: {e}")

    return results
