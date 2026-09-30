import re
import logging
import asyncio
from typing import Callable
from urllib.parse import urlparse
from bs4 import BeautifulSoup
from backend.session import get_session
from backend.scrappers.base import BaseScraper, MediaItem, StreamSource
from .constants import DEFAULT_HEADERS
from .storage import (
    get_cached_movie_path,
    save_cached_movie_path,
    get_catalog_by_year,
)
from .domain import resolve_moviesda_domain
from .matcher import (
    clean_title_tokens,
    find_candidates_in_entries,
    find_candidates_in_soup,
)
from .crawler import crawl_movie_page
from .extractor import extract_streams_from_resolution
from .resolver import probe_and_resolve_all

logger = logging.getLogger(__name__)

class IsaiminiScraper(BaseScraper):
    name = "Isaimini"

    async def scrape(
        self,
        media: MediaItem,
        on_progress: Callable[[str, str], None] | None = None
    ) -> list[StreamSource]:
        """
        Scrapes Isaimini / Moviesda for Tamil stream sources for a given MediaItem.
        """
        results: list[StreamSource] = []
        if media.media_type != "movie":
            return results

        try:
            session = get_session()
            base_url = await resolve_moviesda_domain(session)
            if not base_url:
                logger.warning(f"[{self.name}] No valid base domain available.")
                return results

            if on_progress:
                on_progress("domain", f"Active mirror: {base_url}")

            target_tokens = clean_title_tokens(media.title)
            if not target_tokens:
                return results

            movie_page_url: str | None = None
            found_page = 1

            # 1. Check permanent movie path database cache
            if media.tmdb_id:
                cached_path_data = get_cached_movie_path(media.tmdb_id)
                if cached_path_data:
                    cached_path_slug = cached_path_data.get("path")
                    cached_page = cached_path_data.get("page", 1)
                    movie_page_url = f"{base_url.rstrip('/')}{cached_path_slug}"
                    logger.info(f"[{self.name}] Movie directory (cached): {movie_page_url}")
                    if on_progress:
                        on_progress("path", f"Movie directory (cached): {movie_page_url}")

            # 2. Check local catalog cache for this year
            if not movie_page_url and media.year:
                local_entries = get_catalog_by_year(media.year)
                if local_entries:
                    local_candidates = find_candidates_in_entries(local_entries, target_tokens, base_url)
                    strict_local = [c for c in local_candidates if c["is_strict"]]
                    best = None
                    if strict_local:
                        strict_local.sort(key=lambda c: (c["extra_tokens"], c["page"]))
                        best = strict_local[0]
                    elif local_candidates:
                        local_candidates.sort(key=lambda c: (-c["overlap"], c["extra_tokens"], c["page"]))
                        best = local_candidates[0]

                    if best:
                        movie_page_url = best["url"]
                        found_page = best["page"]
                        logger.info(f"[{self.name}] Found match in local catalog for '{media.title}' (Page {found_page}): {movie_page_url}")
                        if on_progress:
                            on_progress("path", f"Movie directory (local catalog): {movie_page_url}")
                        if media.tmdb_id:
                            parsed_path = urlparse(movie_page_url).path
                            save_cached_movie_path(media.tmdb_id, parsed_path, page=found_page)

            # 3. If still not found, search live directory pages
            if not movie_page_url and media.year:
                category_url = f"{base_url}tamil-{media.year}-movies/"
                logger.info(f"[{self.name}] Scanning directory for '{media.title}' ({media.year}): {category_url}")

                resp = None
                for attempt in range(1, 3):
                    try:
                        resp = await session.get(category_url, headers=DEFAULT_HEADERS, timeout=8.0)
                        if resp.status_code == 200:
                            break
                    except Exception as e:
                        logger.warning(f"[{self.name}] Error fetching page 1 (attempt {attempt}): {e}")
                        if attempt < 2:
                            await asyncio.sleep(1.5)

                if not resp or resp.status_code != 200:
                    return results

                soup = BeautifulSoup(resp.text, "html.parser")
                max_pages = 1
                for a in soup.find_all("a"):
                    text = a.get_text().strip()
                    if text.isdigit() and int(text) > max_pages:
                        max_pages = int(text)
                    elif "page" in text.lower():
                        match = re.search(r'page\s*(\d+)', text.lower())
                        if match and int(match.group(1)) > max_pages:
                            max_pages = int(match.group(1))

                all_candidates = find_candidates_in_soup(soup, target_tokens, base_url, year=media.year, page_num=1)

                if not all_candidates and max_pages > 1:
                    batch_size = 4
                    pages_to_crawl = list(range(2, max_pages + 1))

                    for i in range(0, len(pages_to_crawl), batch_size):
                        batch = pages_to_crawl[i:i + batch_size]
                        tasks = [session.get(f"{category_url}?page={p}", headers=DEFAULT_HEADERS, timeout=8.0) for p in batch]
                        responses = await asyncio.gather(*tasks, return_exceptions=True)

                        batch_found = False
                        for p_idx, r in enumerate(responses):
                            if isinstance(r, Exception) or r.status_code != 200:
                                continue
                            p_num = batch[p_idx]
                            page_soup = BeautifulSoup(r.text, "html.parser")
                            cands = find_candidates_in_soup(page_soup, target_tokens, base_url, year=media.year, page_num=p_num)
                            if cands:
                                all_candidates.extend(cands)
                                batch_found = True

                        if batch_found:
                            strict_candidates = [c for c in all_candidates if c["is_strict"]]
                            if strict_candidates or all_candidates:
                                break

                strict_candidates = [c for c in all_candidates if c["is_strict"]]
                if strict_candidates:
                    strict_candidates.sort(key=lambda c: (c["extra_tokens"], c["page"]))
                    best = strict_candidates[0]
                    movie_page_url = best["url"]
                    found_page = best["page"]
                    logger.info(f"[{self.name}] Best strict match for '{media.title}' on Page {found_page}: {movie_page_url}")
                elif all_candidates:
                    all_candidates.sort(key=lambda c: (-c["overlap"], c["extra_tokens"], c["page"]))
                    best = all_candidates[0]
                    movie_page_url = best["url"]
                    found_page = best["page"]
                    logger.info(f"[{self.name}] Best fallback match for '{media.title}' on Page {found_page}: {movie_page_url}")

                if movie_page_url and media.tmdb_id:
                    logger.info(f"[{self.name}] Movie directory (newly found): {movie_page_url}")
                    if on_progress:
                        on_progress("path", f"Movie directory (newly found): {movie_page_url}")
                    parsed_path = urlparse(movie_page_url).path
                    save_cached_movie_path(media.tmdb_id, parsed_path, page=found_page)

            if not movie_page_url:
                logger.info(f"[{self.name}] Movie '{media.title}' ({media.year}) not found in directory.")
                return results

            if on_progress:
                on_progress("extracting", "Extracting stream file links...")

            root_soup = None
            try:
                root_resp = await session.get(movie_page_url, headers=DEFAULT_HEADERS, timeout=8.0)
                if root_resp.status_code == 200:
                    root_soup = BeautifulSoup(root_resp.text, "html.parser")
            except Exception:
                pass

            # 4. Recursive quality resolution crawling
            resolution_links = await crawl_movie_page(session, movie_page_url, base_url, target_tokens)
            if not resolution_links:
                resolution_links = [("Default Quality", movie_page_url)]

            # 5. Extract stream sources from resolution candidates concurrently
            tasks = [
                extract_streams_from_resolution(
                    session=session,
                    res_url=res_url,
                    res_name=res_name,
                    base_url=base_url,
                    root_soup=root_soup,
                    movie_page_url=movie_page_url,
                    tmdb_id=media.tmdb_id,
                    title=media.title
                )
                for res_name, res_url in resolution_links
            ]
            extraction_results = await asyncio.gather(*tasks, return_exceptions=True)
            for extracted in extraction_results:
                if isinstance(extracted, list):
                    results.extend(extracted)

            if results:
                results = await probe_and_resolve_all(results)

        except Exception as e:
            logger.error(f"[{self.name}] Error scraping movie streams: {e}", exc_info=True)

        return results
