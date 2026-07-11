from app.scrapers.base import BaseScraper

class VidSrcToScraper(BaseScraper):
    name = "VidSrcTo"

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
        Generate stream link for VidSrcTo embed player.
        """
        # VidSrcTo supports TMDB IDs natively
        if media_type == "movie":
            url = f"https://vidsrc.to/embed/movie/{tmdb_id}"
        else:
            if season is None or episode is None:
                return []
            url = f"https://vidsrc.to/embed/tv/{tmdb_id}/{season}/{episode}"

        return [{
            "provider": "VidSrcTo (Alternative)",
            "url": url,
            "quality": "Auto",
            "type": "embed",
            "subtitles": []
        }]
