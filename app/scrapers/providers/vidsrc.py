import re
from bs4 import BeautifulSoup
import logging
from app.scrapers.base import BaseScraper

logger = logging.getLogger(__name__)

class VidSrcScraper(BaseScraper):
    name = "VidSrc"

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
        Scrape VidSrc.me embed to extract source iframe/host links.
        """
        results = []
        if not imdb_id:
            logger.warning(f"{self.name} scraper requires an IMDb ID.")
            return results

        if media_type == "movie":
            url = f"https://vidsrc.me/embed/movie?imdb={imdb_id}"
        else:
            if season is None or episode is None:
                logger.warning(f"{self.name} TV request requires season and episode.")
                return results
            url = f"https://vidsrc.me/embed/tv?imdb={imdb_id}&season={season}&episode={episode}"

        try:
            from app.core.session import get_session
            client = get_session()
            logger.info(f"{self.name} fetching embed URL: {url}")
            resp = await client.get(url, headers=self.headers, allow_redirects=True, impersonate="chrome", timeout=10.0)
            if resp.status_code != 200:
                logger.error(f"{self.name} returned status code {resp.status_code}")
                return results

            soup = BeautifulSoup(resp.text, "lxml")

            # Look for iframes
            iframes = soup.find_all("iframe")
            for iframe in iframes:
                src = iframe.get("src")
                if src:
                    if src.startswith("//"):
                        src = f"https:{src}"
                    results.append({
                        "provider": "VidSrc (Primary Player)",
                        "url": src,
                        "quality": "Auto",
                        "type": "embed",
                        "subtitles": []
                    })

            # Look for alternative sources in scripts
            script_tags = soup.find_all("script")
            for script in script_tags:
                if script.string:
                    urls = re.findall(r'https?://[^\s\'"<>]+', script.string)
                    for u in urls:
                        if any(host in u for host in ["filemoon", "vidplay", "mixdrop", "streamtape", "rabbit"]):
                            results.append({
                                "provider": f"VidSrc (Alt Resolver)",
                                "url": u,
                                "quality": "Auto",
                                "type": "embed",
                                "subtitles": []
                            })

        except Exception as e:
            logger.error(f"Error scraping {self.name}: {e}", exc_info=True)

        return results
