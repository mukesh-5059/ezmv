import re
import json
import logging
import asyncio
from datetime import datetime
from pathlib import Path
from bs4 import BeautifulSoup
from urllib.parse import urlparse, parse_qs
from app.scrapers.base import BaseScraper
from app.core.session import get_session

logger = logging.getLogger(__name__)

DOMAIN_CACHE_FILE = Path(__file__).parent.parent / "domain_cache.json"
PATH_CACHE_FILE = Path(__file__).parent.parent / "movie_path_cache.json"
FILE_ID_LOG_FILE = Path(__file__).parent.parent / "file_id_log.json"

def get_cached_domain(key: str) -> str | None:
    try:
        if DOMAIN_CACHE_FILE.exists():
            with open(DOMAIN_CACHE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data.get(key)
    except Exception as e:
        logger.warning(f"Error reading domain cache: {e}")
    return None

def save_cached_domain(key: str, domain: str):
    try:
        data = {}
        if DOMAIN_CACHE_FILE.exists():
            with open(DOMAIN_CACHE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
        data[key] = domain
        with open(DOMAIN_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        logger.info(f"Updated domain cache for '{key}': {domain}")
    except Exception as e:
        logger.warning(f"Error writing domain cache: {e}")

def get_cached_movie_path(tmdb_id: int) -> dict | None:
    try:
        if PATH_CACHE_FILE.exists():
            with open(PATH_CACHE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                val = data.get(str(tmdb_id))
                if isinstance(val, dict):
                    return val
                elif isinstance(val, str):
                    return {"path": val, "page": 1}
    except Exception as e:
        logger.warning(f"Error reading movie path cache: {e}")
    return None

def save_cached_movie_path(tmdb_id: int, movie_path: str, page: int = 1):
    try:
        data = {}
        if PATH_CACHE_FILE.exists():
            with open(PATH_CACHE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
        data[str(tmdb_id)] = {
            "path": movie_path,
            "page": page
        }
        with open(PATH_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        logger.info(f"Permanently cached movie path for TMDB {tmdb_id}: {movie_path} (Page {page})")
    except Exception as e:
        logger.warning(f"Error writing movie path cache: {e}")

def log_file_id(tmdb_id: int, title: str, file_id: str, quality: str):
    try:
        logs = []
        if FILE_ID_LOG_FILE.exists():
            with open(FILE_ID_LOG_FILE, "r", encoding="utf-8") as f:
                logs = json.load(f)
        entry = {
            "timestamp": datetime.now().isoformat(),
            "tmdb_id": tmdb_id,
            "title": title,
            "file_id": file_id,
            "quality": quality
        }
        logs.append(entry)
        with open(FILE_ID_LOG_FILE, "w", encoding="utf-8") as f:
            json.dump(logs, f, indent=2)
        logger.info(f"Logged file ID for science: TMDB {tmdb_id} | File ID: {file_id} | Quality: {quality}")
    except Exception as e:
        logger.warning(f"Error logging file ID: {e}")

SEED_MIRRORS = [
    "https://moviesdatamil.net/",
    "https://moviesda33.com/",
    "https://isaimini.com.in/"
]

RESOLUTION_TOKENS = {"1080p", "720p", "640x360", "480p", "360p", "480x320", "320x240", "sample"}
QUALITY_SUBFOLDER_TOKENS = {"original", "predvd", "hd", "tamil", "dubbed", "multi audio", "single part"}
BLACKLIST_TOKENS = {"songs", "mp3", "bgm", "ringtone", "trailer", "video-songs", "telegram", "disclaimer", "a-z", "contact", "#"}

class IsaiminiScraper(BaseScraper):
    name = "Isaimini"

    def _clean_title_tokens(self, title: str) -> set[str]:
        title = title.lower()
        tokens = re.findall(r'[a-z0-9]+', title)
        return set(tokens)

    def _find_movie_in_soup(self, soup, target_tokens, base_url) -> str | None:
        links = soup.find_all("a")
        for link in links:
            href = link.get("href")
            text = link.get_text().strip()
            if href and text and ("-movie" in href or "-web-series" in href):
                link_tokens = self._clean_title_tokens(text)
                if target_tokens.issubset(link_tokens):
                    return href if href.startswith("http") else f"{base_url.rstrip('/')}{href}"
        return None

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

    async def _resolve_moviesda_domain(self, client) -> str:
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
        
        cached_domain = get_cached_domain("isaimini")
        if cached_domain:
            try:
                resp = await client.get(
                    cached_domain,
                    headers=headers,
                    allow_redirects=True,
                    timeout=5.0
                )
                if resp.status_code == 200:
                    final_domain = self._extract_base_domain(str(resp.url))
                    if final_domain != cached_domain:
                        logger.info(f"[{self.name}] Cached domain '{cached_domain}' redirected to '{final_domain}'. Updating cache.")
                        save_cached_domain("isaimini", final_domain)
                    else:
                        logger.info(f"[{self.name}] Using active cached domain: {final_domain}")
                    return final_domain
            except Exception as e:
                logger.warning(f"[{self.name}] Cached domain '{cached_domain}' unreachable ({e}). Resolving from seed mirrors...")

        for seed in SEED_MIRRORS:
            try:
                logger.info(f"[{self.name}] Pinging seed mirror: {seed}")
                resp = await client.get(
                    seed,
                    headers=headers,
                    allow_redirects=True,
                    timeout=5.0
                )
                if resp.status_code == 200:
                    active_domain = self._extract_base_domain(str(resp.url))
                    logger.info(f"[{self.name}] Discovered active domain via redirect: {seed} -> {active_domain}")
                    save_cached_domain("isaimini", active_domain)
                    return active_domain
            except Exception as e:
                logger.warning(f"[{self.name}] Seed mirror '{seed}' failed: {e}")

        fallback = "https://moviesdatamil.net/"
        save_cached_domain("isaimini", fallback)
        return fallback

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
        episode: int | None = None
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
                logger.info(f"[{self.name}] Using permanent cached movie path for TMDB {tmdb_id}: {movie_page_url} (Found on Page {cached_page})")

            # 2. If not cached, search directory pages 1..N
            if not movie_page_url:
                category_url = f"{base_url}tamil-{year}-movies/"
                logger.info(f"[{self.name}] Scanning directory for '{title}' ({year}): {category_url}")
                
                resp = await client.get(category_url, headers=headers, timeout=8.0)
                if resp.status_code != 200:
                    return results

                soup = BeautifulSoup(resp.text, "html.parser")
                max_pages = 1
                for a in soup.find_all("a"):
                    href = a.get("href")
                    if href and "?page=" in href:
                        match = re.search(r'page=(\d+)', href)
                        if match:
                            max_pages = max(max_pages, int(match.group(1)))

                movie_page_url = self._find_movie_in_soup(soup, target_tokens, base_url)
                if movie_page_url:
                    found_page = 1

                if not movie_page_url and max_pages > 1:
                    batch_size = 8
                    scanned_pages = {1}
                    
                    while scanned_pages != set(range(1, max_pages + 1)):
                        unscanned = sorted(list(set(range(2, max_pages + 1)) - scanned_pages))
                        batch = unscanned[:batch_size]
                        if not batch:
                            break
                            
                        urls = [f"{category_url}?page={p}" for p in batch]
                        tasks = [client.get(url, headers=headers, timeout=8.0) for url in urls]
                        responses = await asyncio.gather(*tasks, return_exceptions=True)
                        
                        for idx, r in enumerate(responses):
                            if isinstance(r, Exception) or r.status_code != 200:
                                continue
                            batch_soup = BeautifulSoup(r.text, "html.parser")
                            
                            for a in batch_soup.find_all("a"):
                                href = a.get("href")
                                if href and "?page=" in href:
                                    match = re.search(r'page=(\d+)', href)
                                    if match:
                                        max_pages = max(max_pages, int(match.group(1)))
                                        
                            matched_url = self._find_movie_in_soup(batch_soup, target_tokens, base_url)
                            if matched_url:
                                movie_page_url = matched_url
                                found_page = batch[idx]
                                break
                                
                        scanned_pages.update(batch)
                        if movie_page_url:
                            break

                # Save permanent path mapping to cache with page number
                if movie_page_url:
                    parsed_path = urlparse(movie_page_url).path
                    save_cached_movie_path(tmdb_id, parsed_path, page=found_page)

            if not movie_page_url:
                logger.info(f"[{self.name}] Movie '{title}' ({year}) not listed in year directory.")
                return results

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
                                                "subtitles": []
                                            })
                                            logger.info(f"[{self.name}] Resolved direct stream link ({quality}): {direct_stream_url}")
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

