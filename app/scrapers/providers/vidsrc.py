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
        Generate stream link for VidSrc embed player.
        """
        if not imdb_id:
            logger.warning(f"[{self.name}] VidSrc scraper requires IMDb ID, none provided for {title}")
            return []

        results = []
        if media_type == "movie":
            url = f"https://vidsrcme.su/embed/movie?imdb={imdb_id}"
            results.append({
                "provider": "VidSrc (Mirror - Embed)",
                "url": url,
                "quality": "Auto",
                "type": "embed",
                "subtitles": []
            })
        else:
            if season is not None and episode is not None:
                url = f"https://vidsrcme.su/embed/tv?imdb={imdb_id}&season={season}&episode={episode}"
                results.append({
                    "provider": "VidSrc (Mirror - Embed)",
                    "url": url,
                    "quality": "Auto",
                    "type": "embed",
                    "subtitles": []
                })

        # Log the returned link matching Isaimini style
        for r in results:
            logger.info(f"[{self.name}] Resolved embed stream link: {r['url']}")

        return results
