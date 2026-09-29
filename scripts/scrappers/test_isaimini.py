import sys
import asyncio
import logging
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[2]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from backend.scrappers.base import MediaItem
from backend.scrappers.providers.isaimini import IsaiminiScraper
from backend.session import init_session, close_session

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("test_isaimini")

async def test_scraper(title: str, year: int, tmdb_id: int | None = None):
    await init_session()
    scraper = IsaiminiScraper()

    media = MediaItem(
        title=title,
        year=year,
        media_type="movie",
        tmdb_id=tmdb_id
    )

    def on_progress(step: str, msg: str):
        logger.info(f"Progress [{step}]: {msg}")

    logger.info(f"Testing IsaiminiScraper for '{title}' ({year})...")
    sources = await scraper.scrape(media, on_progress=on_progress)

    print("\n--- Scrape Results ---")
    if not sources:
        print("No stream sources found.")
    for i, s in enumerate(sources, 1):
        print(f"[{i}] Provider: {s.provider} | Quality: {s.quality}")
        print(f"    URL: {s.url}")
        if s.headers:
            print(f"    Headers: {s.headers}")

    await close_session()

if __name__ == "__main__":
    test_title = sys.argv[1] if len(sys.argv) > 1 else "Leo"
    test_year = int(sys.argv[2]) if len(sys.argv) > 2 else 2023
    test_tmdb = int(sys.argv[3]) if len(sys.argv) > 3 else 1075794

    asyncio.run(test_scraper(test_title, test_year, test_tmdb))
