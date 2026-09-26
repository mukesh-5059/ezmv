from abc import ABC, abstractmethod
import httpx
import logging

logger = logging.getLogger(__name__)

class BaseScraper(ABC):
    """
    Abstract Base Class for all movie and TV show scrapers.
    """
    name: str = "BaseScraper"
    
    def __init__(self):
        # Setup standard headers to mimic a real browser
        self.headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Referer": "https://google.com"
        }

    @abstractmethod
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
        Scrapes the website for streaming links.
        Returns a list of dicts with keys:
            - 'provider': Name of the source/host (e.g., 'Filemoon')
            - 'url': The streaming URL (.m3u8 or .mp4) or embed page URL
            - 'quality': '1080p', '720p', etc.
            - 'type': 'direct' (m3u8/mp4) or 'embed' (iframe/embed player URL)
            - 'subtitles': list of subtitle dicts (optional)
        """
        pass
