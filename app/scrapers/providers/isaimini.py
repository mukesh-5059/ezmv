import re
import logging
import asyncio
from bs4 import BeautifulSoup
from urllib.parse import urlparse, parse_qs
from app.scrapers.base import BaseScraper
from app.core.session import get_session

logger = logging.getLogger(__name__)

class IsaiminiScraper(BaseScraper):
    name = "Isaimini"

    def _clean_title_tokens(self, title: str) -> set[str]:
        # Lowercase and split into alphanumeric tokens
        title = title.lower()
        tokens = re.findall(r'[a-z0-9]+', title)
        return set(tokens)

    def _find_movie_in_soup(self, soup, target_tokens, base_url) -> str | None:
        links = soup.find_all("a")
        for link in links:
            href = link.get("href")
            text = link.get_text().strip()
            if href and text and ("-movie/" in href or "-web-series/" in href):
                link_tokens = self._clean_title_tokens(text)
                if target_tokens.issubset(link_tokens):
                    return href if href.startswith("http") else f"{base_url.rstrip('/')}{href}"
        return None

    async def _resolve_moviesda_domain(self, client) -> str:
        landing_url = "https://இசைமினி6.com/"
        logger.info(f"[{self.name}] Resolving domain from landing: {landing_url}")
        try:
            resp = await client.get(
                landing_url,
                headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"},
                allow_redirects=True,
                impersonate="chrome",
                timeout=8.0
            )
            if resp.status_code == 200:
                soup = BeautifulSoup(resp.text, "html.parser")
                
                # Check <a> tags inside <div class="dir">
                for div in soup.find_all("div", class_="dir"):
                    a_tag = div.find("a")
                    if a_tag:
                        href = a_tag.get("href")
                        if href and "google.com/url" in href:
                            parsed_url = urlparse(href)
                            params = parse_qs(parsed_url.query)
                            q_list = params.get("q")
                            if q_list:
                                domain = q_list[0]
                                if not domain.endswith("/"):
                                    domain += "/"
                                logger.info(f"[{self.name}] Extracted active mirror: {domain}")
                                return domain
                                
                # Fallback to general anchors
                for a_tag in soup.find_all("a"):
                    href = a_tag.get("href")
                    if href and "google.com/url" in href:
                        parsed_url = urlparse(href)
                        params = parse_qs(parsed_url.query)
                        q_list = params.get("q")
                        if q_list:
                            domain = q_list[0]
                            if not domain.endswith("/"):
                                domain += "/"
                            logger.info(f"[{self.name}] Extracted active mirror (fallback): {domain}")
                            return domain
        except Exception as e:
            logger.error(f"[{self.name}] Landing page resolution failed: {e}")
            
        return "https://moviesda33.com/" # Return standard mirror as final fallback

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
        Scrape Isaimini (Moviesda) landing page and categories for Tamil download/embed streams.
        """
        results = []
        # Isaimini only supports movies, ignore TV shows
        if media_type != "movie":
            return results

        try:
            client = get_session()
            base_url = await self._resolve_moviesda_domain(client)
            
            # Construct Year page URL
            category_url = f"{base_url}tamil-{year}-movies/"
            logger.info(f"[{self.name}] Scanning directory: {category_url}")
            
            target_tokens = self._clean_title_tokens(title)
            if not target_tokens:
                return results
                
            movie_page_url = None
            headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
            
            # Step 1: Fetch Page 1 to search and discover the total page count
            resp = await client.get(category_url, headers=headers, impersonate="chrome", timeout=8.0)
            if resp.status_code != 200:
                logger.info(f"[{self.name}] Year directory {category_url} returned status {resp.status_code}")
                return results

            soup = BeautifulSoup(resp.text, "html.parser")
            
            # Extract total page count from pagination links
            total_pages = 1
            for a in soup.find_all("a"):
                href = a.get("href")
                if href and "?page=" in href:
                    match = re.search(r'page=(\d+)', href)
                    if match:
                        total_pages = max(total_pages, int(match.group(1)))
            logger.info(f"[{self.name}] Total pages found in directory: {total_pages}")

            # Check if movie is on Page 1
            movie_page_url = self._find_movie_in_soup(soup, target_tokens, base_url)
            
            # Step 2: If not found on Page 1, scan remaining pages in parallel batches
            if not movie_page_url and total_pages > 1:
                batch_size = 8
                remaining_pages = list(range(2, total_pages + 1))
                
                for i in range(0, len(remaining_pages), batch_size):
                    batch = remaining_pages[i:i+batch_size]
                    logger.info(f"[{self.name}] Scanning batch of pages: {batch}")
                    urls = [f"{category_url}?page={p}" for p in batch]
                    tasks = [client.get(url, headers=headers, impersonate="chrome", timeout=8.0) for url in urls]
                    responses = await asyncio.gather(*tasks, return_exceptions=True)
                    
                    for r in responses:
                        if isinstance(r, Exception) or r.status_code != 200:
                            continue
                        batch_soup = BeautifulSoup(r.text, "html.parser")
                        matched_url = self._find_movie_in_soup(batch_soup, target_tokens, base_url)
                        if matched_url:
                            movie_page_url = matched_url
                            logger.info(f"[{self.name}] Found movie match on batch page: {movie_page_url}")
                            break
                            
                    if movie_page_url:
                        break

            if not movie_page_url:
                logger.info(f"[{self.name}] Movie '{title}' ({year}) not listed in year directory.")
                return results

            # Step 1: Fetch Movie page
            resp = await client.get(movie_page_url, impersonate="chrome", timeout=8.0)
            soup = BeautifulSoup(resp.text, "html.parser")
            
            # Check if this movie page already lists the resolutions directly
            has_direct_resolutions = False
            for a in soup.find_all("a"):
                href = a.get("href")
                text = a.get_text().strip()
                if href and any(res in text.lower() or res in href.lower() for res in ["720p", "1080p", "360p", "480p"]):
                    if "/tamil-" in href or "-movie/" in href:
                        has_direct_resolutions = True
                        break
            
            subfolder_url = None
            if has_direct_resolutions:
                logger.info(f"[{self.name}] Movie page directly contains resolution listings.")
                subfolder_url = movie_page_url
            else:
                for a in soup.find_all("a"):
                    href = a.get("href")
                    text = a.get_text().strip()
                    if href and any(k in href.lower() or k in text.lower() for k in ["original", "hd", "predvd"]):
                        subfolder_url = href if href.startswith("http") else f"{base_url.rstrip('/')}{href}"
                        break
                    
            if not subfolder_url:
                subfolder_url = movie_page_url
                
            # Step 2: Fetch subfolder for resolution lists
            resp = await client.get(subfolder_url, impersonate="chrome", timeout=8.0)
            soup = BeautifulSoup(resp.text, "html.parser")
            
            resolution_links = []
            for a in soup.find_all("a"):
                href = a.get("href")
                text = a.get_text().strip()
                if href and any(res in text.lower() or res in href.lower() for res in ["720p", "1080p", "360p", "480p"]):
                    res_url = href if href.startswith("http") else f"{base_url.rstrip('/')}{href}"
                    resolution_links.append((text, res_url))
                    
            if not resolution_links:
                resolution_links.append(("Default Quality", subfolder_url))
                
            # Step 3: Extract final file ID and build streaming links
            for res_name, res_url in resolution_links[:2]: # Max 2 quality options to keep responses snappy
                resp = await client.get(res_url, impersonate="chrome", timeout=8.0)
                soup = BeautifulSoup(resp.text, "html.parser")
                
                file_links = []
                for a in soup.find_all("a"):
                    href = a.get("href")
                    text = a.get_text().strip()
                    if href and ("/download/" in href or "download" in text.lower()):
                        file_url = href if href.startswith("http") else f"{base_url.rstrip('/')}{href}"
                        file_links.append(file_url)
                        
                for file_url in file_links[:1]:
                    resp = await client.get(file_url, impersonate="chrome", timeout=8.0)
                    soup = BeautifulSoup(resp.text, "html.parser")
                    
                    for a in soup.find_all("a"):
                        href = a.get("href")
                        if href and "download/file/" in href:
                            match = re.search(r'download/file/(\d+)', href)
                            if match:
                                file_id = match.group(1)
                                player_url = f"https://play.onestream.today/stream/page/{file_id}"
                                quality = "720p" if "720p" in res_name.lower() else ("1080p" if "1080p" in res_name.lower() else "360p")
                                
                                # Resolve direct HTML5 video stream URL from the player page
                                try:
                                    player_resp = await client.get(player_url, headers={"Referer": file_url}, impersonate="chrome", timeout=8.0)
                                    if player_resp.status_code == 200:
                                        player_soup = BeautifulSoup(player_resp.text, "html.parser")
                                        source_tag = player_soup.find("source")
                                        if source_tag and source_tag.get("src"):
                                            direct_stream_url = source_tag.get("src").replace("&amp;", "&")
                                            results.append({
                                                "provider": f"Isaimini (Server {quality})",
                                                "url": direct_stream_url,
                                                "quality": quality,
                                                "type": "embed",
                                                "subtitles": []
                                            })
                                            logger.info(f"[{self.name}] Resolved direct stream link ({quality}): {direct_stream_url}")
                                            break
                                except Exception as e:
                                    logger.error(f"[{self.name}] Failed to extract direct stream link from player: {e}")
                                    
                                # Fallback to player page URL if direct extraction fails
                                results.append({
                                    "provider": f"Isaimini (Server {quality})",
                                    "url": player_url,
                                    "quality": quality,
                                    "type": "embed",
                                    "subtitles": []
                                })
                                break

        except Exception as e:
            logger.error(f"[{self.name}] Error scraping movie streams: {e}", exc_info=True)
            
        return results
