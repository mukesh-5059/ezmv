import asyncio
import logging
from app.scrapers.providers.vidsrc import VidSrcScraper

logger = logging.getLogger(__name__)

class ScraperManager:
    def __init__(self):
        # Register active scraper instances
        self.scrapers = [
            VidSrcScraper()
        ]

    async def get_streams(
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
        Runs all registered scrapers concurrently to find streaming links.
        """
        logger.info(f"Orchestrating scrapers for: {title} ({year}) | Type: {media_type} | TMDb: {tmdb_id} | IMDb: {imdb_id}")
        
        tasks = []
        for scraper in self.scrapers:
            tasks.append(
                scraper.scrape(
                    title=title,
                    year=year,
                    media_type=media_type,
                    tmdb_id=tmdb_id,
                    imdb_id=imdb_id,
                    season=season,
                    episode=episode
                )
            )

        # Run scrapers in parallel with a timeout to keep responses fast
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

        # De-duplicate results based on URL
        seen_urls = set()
        deduplicated = []
        for item in flat_results:
            url = item.get("url")
            if url and url not in seen_urls:
                seen_urls.add(url)
                deduplicated.append(item)

        return deduplicated

scraper_manager = ScraperManager()
