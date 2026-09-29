import logging
from typing import Callable
from backend.scrappers.base import BaseScraper, MediaItem, StreamSource

logger = logging.getLogger(__name__)

class VidSrcScraper(BaseScraper):
    name = "VidSrc"

    async def scrape(
        self,
        media: MediaItem,
        on_progress: Callable[[str, str], None] | None = None
    ) -> list[StreamSource]:
        """
        Stub for VidSrc provider.
        """
        logger.info(f"[{self.name}] Scraper called for '{media.title}' ({media.year})")
        return []
