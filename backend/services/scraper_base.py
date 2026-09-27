from abc import ABC, abstractmethod

class BaseScraper(ABC):
    name: str = "BaseScraper"
    
    def __init__(self):
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
        episode: int | None = None,
        on_progress = None
    ) -> list[dict]:
        pass
