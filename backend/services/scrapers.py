import asyncio
import logging
from backend.services.scraper_base import BaseScraper
from backend.services.isaimini import IsaiminiScraper
from backend.services.tmdb import TTLCache

logger = logging.getLogger(__name__)

class ScraperManager:
    def __init__(self):
        self.scrapers = [
            IsaiminiScraper()
        ]
        self._stream_cache = TTLCache(ttl_seconds=10800)

    async def get_streams(
        self,
        title: str,
        year: int,
        media_type: str,
        tmdb_id: int,
        imdb_id: str | None = None,
        season: int | None = None,
        episode: int | None = None,
        bypass_cache: bool = False
    ) -> list[dict]:
        cache_key = f"{tmdb_id}_{season}_{episode}"
        if not bypass_cache:
            cached_result = self._stream_cache.get(cache_key)
            if cached_result is not None:
                logger.info(f"Serving streams for TMDB {tmdb_id} from manager cache")
                return cached_result

        logger.info(f"Orchestrating scrapers for: {title} ({year}) | Type: {media_type} | TMDb: {tmdb_id} | IMDb: {imdb_id}")
        
        tasks = [
            scraper.scrape(
                title=title,
                year=year,
                media_type=media_type,
                tmdb_id=tmdb_id,
                imdb_id=imdb_id,
                season=season,
                episode=episode
            )
            for scraper in self.scrapers
        ]

        try:
            results = await asyncio.gather(*tasks, return_exceptions=True)
        except Exception as e:
            logger.error(f"Error gathering scraping tasks: {e}")
            return []

        flat_results = []
        for i, res in enumerate(results):
            scraper_name = self.scrapers[i].name
            if isinstance(res, Exception):
                logger.error(f"Scraper '{scraper_name}' raised an exception: {res}")
                continue
            
            if res:
                logger.info(f"Scraper '{scraper_name}' returned {len(res)} stream sources.")
                flat_results.extend(res)
            else:
                logger.info(f"Scraper '{scraper_name}' returned no sources.")

        seen_urls = set()
        deduplicated = []
        for item in flat_results:
            url = item.get("url")
            if url and url not in seen_urls:
                seen_urls.add(url)
                deduplicated.append(item)

        deduplicated.sort(key=lambda x: 0 if any(k in x.get("provider", "") for k in ["Original", "PreDVD", "Isaimini"]) else 1)
        self._stream_cache.set(cache_key, deduplicated)
        return deduplicated

scraper_manager = ScraperManager()
