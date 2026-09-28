import re
import logging
import asyncio
from bs4 import BeautifulSoup
from urllib.parse import urlparse, parse_qs, quote
from backend.services.scraper_base import BaseScraper
from backend.services.scraper_cache import (
    get_cached_domain,
    save_cached_domain,
    get_cached_movie_path,
    save_cached_movie_path,
    log_file_id,
    save_isaimini_catalog_entries,
    get_isaimini_catalog_by_year,
)
from backend.session import get_session

logger = logging.getLogger(__name__)


RESOLUTION_TOKENS = {"1080p", "720p", "640x360", "480p", "360p", "480x320", "320x240", "sample"}
QUALITY_SUBFOLDER_TOKENS = {"original", "predvd", "hd", "tamil", "dubbed", "multi audio", "single part"}
BLACKLIST_TOKENS = {"songs", "mp3", "bgm", "ringtone", "trailer", "video-songs", "telegram", "disclaimer", "a-z", "contact", "#"}

class IsaiminiScraper(BaseScraper):
    name = "Isaimini"

    def _clean_title_tokens(self, title: str) -> set[str]:
        title = title.lower()
        tokens = re.findall(r'[a-z0-9]+', title)
        return set(tokens)

    def _extract_and_save_all_movies_from_soup(self, soup, year: int, page_num: int = 1) -> list[dict]:
        entries = []
        for a in soup.find_all("a"):
            href = a.get("href")
            text = a.get_text().strip()
            if not href or not text:
                continue

            parsed = urlparse(href)
            if parsed.query:
                continue

            path = parsed.path.strip('/')
            if path.startswith("tamil-movies/") or path.endswith("-movies"):
                continue

            if not (path.endswith("-movie") or path.endswith("-web-series")):
                continue

            clean_path = f"/{path}/"
            entries.append({
                "path": clean_path,
                "title": text,
                "year": year,
                "page": page_num
            })

        if entries:
            save_isaimini_catalog_entries(entries)
        return entries

    def _find_candidates_in_entries(self, entries: list[dict], target_tokens: set[str], base_url: str) -> list[dict]:
        candidates = []
        alpha_target = {t for t in target_tokens if not t.isdigit()}
        for e in entries:
            text = e["title"]
            path = e["path"]
            page_num = e.get("page", 1)

            combined_tokens = self._clean_title_tokens(f"{text} {path}")
            if any(black in combined_tokens for black in BLACKLIST_TOKENS):
                continue

            link_tokens = self._clean_title_tokens(text)
            if alpha_target and not (alpha_target & link_tokens):
                continue

            overlap = target_tokens & link_tokens
            score = len(overlap)
            if score > 0:
                is_strict = target_tokens.issubset(link_tokens)
                extra_tokens = len(link_tokens - target_tokens)
                full_url = f"{base_url.rstrip('/')}{path}"
                candidates.append({
                    "url": full_url,
                    "page": page_num,
                    "is_strict": is_strict,
                    "extra_tokens": extra_tokens,
                    "overlap": score,
                    "text": text
                })
        return candidates

    def _find_candidates_in_soup(self, soup, target_tokens: set[str], base_url: str, year: int, page_num: int = 1) -> list[dict]:
        entries = self._extract_and_save_all_movies_from_soup(soup, year=year, page_num=page_num)
        return self._find_candidates_in_entries(entries, target_tokens, base_url)

    def _detect_print_category(self, soup, root_soup, res_name: str, res_url: str, movie_page_url: str) -> str:
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

    def _extract_base_domain(self, url: str) -> str:
        parsed = urlparse(url)
        return f"{parsed.scheme}://{parsed.netloc}/"

    async def _resolve_direct_url(self, client, url: str) -> str:
        """
        Resolves 302 redirects (e.g. from download.php) to the final direct .mp4 media URL.
        Enforces clean URL encoding for spaces and special characters.
        """
        if "download.php" not in url and "uptomkv" not in url:
            return url

        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": "https://cdn.uptomkv.ch/"
        }
        try:
            resp = await client.get(url, headers=headers, allow_redirects=False, timeout=5.0)
            if resp.status_code in (301, 302, 303, 307, 308):
                loc = resp.headers.get("Location") or resp.headers.get("location")
                if loc:
                    resolved = quote(str(loc), safe=":/%?&=#+,-")
                    logger.info(f"[{self.name}] Resolved 302 redirect: {url} -> {resolved}")
                    return resolved
        except Exception as e:
            logger.warning(f"[{self.name}] Failed to resolve direct redirect for {url}: {e}")
        return url

    async def _resolve_moviesda_domain(self, client) -> str | None:
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
        
        cached_domain = get_cached_domain("isaimini")
        if not cached_domain:
            logger.warning(f"[{self.name}] No active domain configured in domain_cache.json. Scraper aborted.")
            return None

        for attempt in range(1, 3):
            try:
                resp = await client.get(
                    cached_domain,
                    headers=headers,
                    allow_redirects=True,
                    timeout=8.0
                )
                if resp.status_code == 200:
                    final_domain = self._extract_base_domain(str(resp.url))
                    if final_domain != cached_domain:
                        logger.info(f"[Domain] Active mirror redirected: {cached_domain} -> {final_domain}")
                        save_cached_domain("isaimini", final_domain)
                    else:
                        logger.info(f"[Domain] Active mirror (cached): {final_domain}")
                    return final_domain
            except Exception as e:
                logger.warning(f"[{self.name}] Attempt {attempt} failed on '{cached_domain}': {e}")
                if attempt < 2:
                    await asyncio.sleep(1.5)

        logger.warning(f"[{self.name}] Cached domain '{cached_domain}' is unreachable after retries. Please update domain_cache.json.")
        return None

    async def _crawl_movie_page(
        self,
        client,
        url: str,
        base_url: str,
        target_tokens: set[str],
        depth: int = 0,
        max_depth: int = 3
    ) -> list[tuple[str, str]]:
        """
        Recursively crawls movie pages up to max_depth to find resolution choices.
        Supports direct resolution lists, quality subfolders, and deep title subfolders.
        """
        if depth > max_depth:
            return []

        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
        try:
            resp = await client.get(url, headers=headers, timeout=6.0)
            if resp.status_code != 200:
                return []
            soup = BeautifulSoup(resp.text, "html.parser")
        except Exception as e:
            logger.warning(f"[{self.name}] Crawl error at depth {depth} for {url}: {e}")
            return []

        resolutions = []
        subfolders = []

        for a in soup.find_all("a"):
            href = a.get("href")
            text = a.get_text().strip()
            if not href or any(skip in href.lower() or skip in text.lower() for skip in BLACKLIST_TOKENS):
                continue

            full_url = href if href.startswith("http") else f"{base_url.rstrip('/')}{href}"
            combined_tokens = self._clean_title_tokens(f"{text} {href}")

            # 1. Match Resolution Choice
            if any(res in combined_tokens for res in RESOLUTION_TOKENS):
                resolutions.append((text, full_url))

            # 2. Match Subfolder (Title tokens OR Quality tokens match)
            elif target_tokens.issubset(combined_tokens) or any(q in combined_tokens for q in QUALITY_SUBFOLDER_TOKENS):
                if full_url != url and full_url not in subfolders and not href.endswith("/movies.php"):
                    subfolders.append(full_url)

        # Pattern 1 & 2 Stop Condition: Direct resolution options found on this page
        if resolutions:
            return resolutions

        # Pattern 3 Recursion: Recurse into subfolders in parallel
        if subfolders:
            tasks = [
                self._crawl_movie_page(client, sf, base_url, target_tokens, depth + 1, max_depth)
                for sf in subfolders[:4] # Max 4 subfolder candidates
            ]
            results = await asyncio.gather(*tasks, return_exceptions=True)
            flat = []
            for r in results:
                if isinstance(r, list):
                    flat.extend(r)
            return flat

        return []

    async def scrape(
        self, 
        title: str, 
        year: int, 
        media_type: str, 
        tmdb_id: int, 
        imdb_id: str | None = None,
        season: int | None = None, 
        episode: int | None = None,
        on_progress = None
    ) -> list[dict]:
        """
        Scrape Isaimini (Moviesda) for Tamil download/embed streams.
        """
        results = []
        if media_type != "movie":
            return results

        try:
            client = get_session()
            base_url = await self._resolve_moviesda_domain(client)
            if not base_url:
                logger.warning(f"[{self.name}] No valid base domain available.")
                return results
            if on_progress:
                on_progress("domain", f"Active mirror: {base_url}")
            target_tokens = self._clean_title_tokens(title)
            if not target_tokens:
                return results

            headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
            movie_page_url = None
            found_page = 1

            # 1. Check permanent movie path database cache
            cached_path_data = get_cached_movie_path(tmdb_id)
            if cached_path_data:
                cached_path_slug = cached_path_data.get("path")
                cached_page = cached_path_data.get("page", 1)
                movie_page_url = f"{base_url.rstrip('/')}{cached_path_slug}"
                logger.info(f"[Path] Movie directory (cached): {movie_page_url}")
                if on_progress:
                    on_progress("path", f"Movie directory (cached): {movie_page_url}")

            # 2. Check local isaimini_catalog for this year
            if not movie_page_url:
                local_entries = get_isaimini_catalog_by_year(year)
                if local_entries:
                    local_candidates = self._find_candidates_in_entries(local_entries, target_tokens, base_url)
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
                        logger.info(f"[{self.name}] Found match in local isaimini_catalog for '{title}' (Page {found_page}): {movie_page_url}")
                        if on_progress:
                            on_progress("path", f"Movie directory (local catalog): {movie_page_url}")
                        parsed_path = urlparse(movie_page_url).path
                        save_cached_movie_path(tmdb_id, parsed_path, page=found_page)

            # 3. If still not found, search live directory pages
            if not movie_page_url:
                category_url = f"{base_url}tamil-{year}-movies/"
                logger.info(f"[{self.name}] Scanning directory for '{title}' ({year}): {category_url}")
                
                resp = None
                for attempt in range(1, 3):
                    try:
                        resp = await client.get(category_url, headers=headers, timeout=8.0)
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
                    href = a.get("href")
                    if href and "?page=" in href:
                        match = re.search(r'page=(\d+)', href)
                        if match:
                            max_pages = max(max_pages, int(match.group(1)))

                # 1. Check Page 1 candidates first (and auto-save Page 1 items to catalog)
                all_candidates = list(self._find_candidates_in_soup(soup, target_tokens, base_url, year=year, page_num=1))
                strict_candidates = [c for c in all_candidates if c["is_strict"]]

                # 2. If not found on Page 1, scan remaining pages in batches of 2
                if not strict_candidates and max_pages > 1:
                    batch_size = 2
                    unscanned = list(range(2, max_pages + 1))
                    
                    for i in range(0, len(unscanned), batch_size):
                        batch = unscanned[i:i+batch_size]
                        urls = [f"{category_url}?page={p}" for p in batch]
                        tasks = [client.get(url, headers=headers, timeout=8.0) for url in urls]
                        responses = await asyncio.gather(*tasks, return_exceptions=True)
                        
                        batch_found = False
                        for idx, r in enumerate(responses):
                            if isinstance(r, Exception) or r.status_code != 200:
                                continue
                            batch_soup = BeautifulSoup(r.text, "html.parser")
                            cands = self._find_candidates_in_soup(batch_soup, target_tokens, base_url, year=year, page_num=batch[idx])
                            if cands:
                                all_candidates.extend(cands)
                                batch_found = True
                        
                        # Stop as soon as candidate found in this batch
                        if batch_found:
                            strict_candidates = [c for c in all_candidates if c["is_strict"]]
                            if strict_candidates or all_candidates:
                                break

                # Filter strict matches (containing all title tokens)
                strict_candidates = [c for c in all_candidates if c["is_strict"]]

                if strict_candidates:
                    # Sort by extra_tokens ascending (fewest extra words wins), then page ascending
                    strict_candidates.sort(key=lambda c: (c["extra_tokens"], c["page"]))
                    best = strict_candidates[0]
                    movie_page_url = best["url"]
                    found_page = best["page"]
                    logger.info(f"[{self.name}] Found best strict match for '{title}' (text: '{best['text']}', extra tokens: {best['extra_tokens']}) on Page {found_page}: {movie_page_url}")
                elif all_candidates:
                    # Fallback: Sort by overlap descending, extra_tokens ascending, page ascending
                    all_candidates.sort(key=lambda c: (-c["overlap"], c["extra_tokens"], c["page"]))
                    best = all_candidates[0]
                    movie_page_url = best["url"]
                    found_page = best["page"]
                    logger.info(f"[{self.name}] Found best fallback match for '{title}' (text: '{best['text']}', overlap: {best['overlap']}) on Page {found_page}: {movie_page_url}")

                # Save permanent path mapping to cache with page number
                if movie_page_url:
                    logger.info(f"[Path] Movie directory (newly found): {movie_page_url}")
                    if on_progress:
                        on_progress("path", f"Movie directory (newly found): {movie_page_url}")
                    parsed_path = urlparse(movie_page_url).path
                    save_cached_movie_path(tmdb_id, parsed_path, page=found_page)

            if not movie_page_url:
                logger.info(f"[{self.name}] Movie '{title}' ({year}) not listed in year directory.")
                return results

            if on_progress:
                on_progress("extracting", "Extracting stream file links...")

            # Fetch root movie page soup for metadata / quality tag extraction
            root_soup = None
            try:
                root_resp = await client.get(movie_page_url, headers=headers, timeout=8.0)
                if root_resp.status_code == 200:
                    root_soup = BeautifulSoup(root_resp.text, "html.parser")
            except Exception:
                pass

            # 3. Hybrid Token Recursive Crawler
            resolution_links = await self._crawl_movie_page(client, movie_page_url, base_url, target_tokens)
            if not resolution_links:
                resolution_links = [("Default Quality", movie_page_url)]

            # 4. Extract final file ID and build streaming links
            for res_name, res_url in resolution_links[:2]:
                resp = await client.get(res_url, headers=headers, timeout=8.0)
                if resp.status_code != 200:
                    continue
                soup = BeautifulSoup(resp.text, "html.parser")
                category = self._detect_print_category(soup, root_soup, res_name, res_url, movie_page_url)
                
                file_links = []
                for a in soup.find_all("a"):
                    href = a.get("href")
                    text = a.get_text().strip()
                    if href and ("/download/" in href or "download" in text.lower()):
                        file_url = href if href.startswith("http") else f"{base_url.rstrip('/')}{href}"
                        file_links.append(file_url)
                        
                for file_url in file_links[:1]:
                    resp = await client.get(file_url, headers=headers, timeout=8.0)
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
                                
                                # Log File ID for science!
                                log_file_id(tmdb_id, title, file_id, quality)

                                player_url = f"https://play.onestream.today/stream/page/{file_id}"
                                
                                # Resolve direct HTML5 video stream URL from player page
                                try:
                                    player_resp = await client.get(player_url, headers={"Referer": file_url, "User-Agent": headers["User-Agent"]}, timeout=8.0)
                                    if player_resp.status_code == 200:
                                        player_soup = BeautifulSoup(player_resp.text, "html.parser")
                                        source_tag = player_soup.find("source")
                                        if source_tag and source_tag.get("src"):
                                            direct_stream_url = source_tag.get("src").replace("&amp;", "&")
                                            results.append({
                                                "provider": f"{category} ({quality})",
                                                "url": direct_stream_url,
                                                "quality": quality,
                                                "type": "direct",
                                                "headers": {
                                                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                                                    "Referer": "https://cdn.uptomkv.ch/"
                                                },
                                                "subtitles": []
                                            })
                                            logger.debug(f"[{self.name}] Scraped raw stream link ({quality}): {direct_stream_url}")
                                            break
                                except Exception as e:
                                    logger.error(f"[{self.name}] Failed to extract direct stream link from player: {e}")

                                # Fallback to player page URL if direct extraction fails
                                results.append({
                                    "provider": f"{category} ({quality})",
                                    "url": player_url,
                                    "quality": quality,
                                    "type": "embed",
                                    "subtitles": []
                                })
                                break

        except Exception as e:
            logger.error(f"[{self.name}] Error scraping movie streams: {e}", exc_info=True)
            
        return results

