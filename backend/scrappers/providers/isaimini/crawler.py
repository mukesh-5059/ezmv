import re
import asyncio
import logging
from bs4 import BeautifulSoup
from .constants import DEFAULT_HEADERS, RESOLUTION_TOKENS, QUALITY_SUBFOLDER_TOKENS, BLACKLIST_TOKENS
from .matcher import clean_title_tokens

logger = logging.getLogger(__name__)

def detect_print_category(soup: BeautifulSoup | None, root_soup: BeautifulSoup | None, res_name: str, res_url: str, movie_page_url: str) -> str:
    combined_text = f"{movie_page_url} {res_name} {res_url}".lower()

    for s in [root_soup, soup]:
        if s:
            page_text = s.get_text().lower()
            if "quality:" in page_text:
                match = re.search(r'quality:\s*([^\n\r<]+)', page_text)
                if match:
                    q_text = match.group(1).strip()
                    if "predvd" in q_text:
                        return "HQ PreDVD" if "hq" in q_text else "PreDVD"
                    elif "web-dl" in q_text or "webrip" in q_text:
                        return "WEB-DL"
                    elif "hdrip" in q_text:
                        return "HDRip"
                    elif "original" in q_text:
                        return "Original"
                    elif q_text:
                        return q_text.title()

    if "hq predvd" in combined_text or "hq-predvd" in combined_text:
        return "HQ PreDVD"
    elif "predvd" in combined_text:
        return "PreDVD"
    elif "web-dl" in combined_text or "webrip" in combined_text:
        return "WEB-DL"
    elif "hdrip" in combined_text:
        return "HDRip"
    elif "original" in combined_text:
        return "Original"

    return "Original"

async def crawl_movie_page(
    session,
    url: str,
    base_url: str,
    target_tokens: set[str],
    depth: int = 0,
    max_depth: int = 3
) -> list[tuple[str, str]]:
    """
    Recursively crawls movie pages up to max_depth to find resolution choices.
    """
    if depth > max_depth:
        return []

    try:
        resp = await session.get(url, headers=DEFAULT_HEADERS, timeout=6.0)
        if resp.status_code != 200:
            return []
        soup = BeautifulSoup(resp.text, "html.parser")
    except Exception as e:
        logger.warning(f"[Isaimini:Crawler] Crawl error at depth {depth} for {url}: {e}")
        return []

    resolutions = []
    subfolders = []

    for a in soup.find_all("a"):
        href = a.get("href")
        text = a.get_text().strip()
        if not href or any(skip in href.lower() or skip in text.lower() for skip in BLACKLIST_TOKENS):
            continue

        full_url = href if href.startswith("http") else f"{base_url.rstrip('/')}{href}"
        combined_tokens = clean_title_tokens(f"{text} {href}")

        # 1. Match Resolution Choice
        if any(res in combined_tokens for res in RESOLUTION_TOKENS):
            if full_url not in [r[1] for r in resolutions]:
                resolutions.append((text, full_url))

        # 2. Match Subfolder (Title tokens OR Quality tokens match, excluding category pages)
        elif target_tokens.issubset(combined_tokens) or any(q in combined_tokens for q in QUALITY_SUBFOLDER_TOKENS):
            if (
                full_url != url 
                and full_url not in subfolders 
                and not href.endswith("/movies.php")
                and not "/tamil-movies/" in href
                and not "-movies/" in href
            ):
                subfolders.append(full_url)

    # Pattern 1 & 2 Stop Condition: Direct resolution options found on this page
    if resolutions:
        return resolutions

    # Pattern 3 Recursion: Recurse into subfolders in parallel
    if subfolders:
        tasks = [
            crawl_movie_page(session, sf, base_url, target_tokens, depth + 1, max_depth)
            for sf in subfolders[:4]
        ]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        flat = []
        for r in results:
            if isinstance(r, list):
                for item in r:
                    if item[1] not in [x[1] for x in flat]:
                        flat.append(item)
        return flat

    return []
