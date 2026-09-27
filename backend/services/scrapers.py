import asyncio
import logging
from urllib.parse import quote
import httpx
from backend.services.scraper_base import BaseScraper
from backend.services.isaimini import IsaiminiScraper
from backend.services.tmdb import tmdb_client, TTLCache
from backend.services.catalog import catalog_service
from backend.models import StreamResponse

logger = logging.getLogger(__name__)

async def resolve_cdn_redirect(url: str) -> str:
    if "download.php" not in url and ".php" not in url and "uptomkv" not in url:
        return url

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://cdn.uptomkv.ch/"
    }
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(url, headers=headers, follow_redirects=False)
            if resp.status_code in (301, 302, 303, 307, 308):
                loc = resp.headers.get("Location") or resp.headers.get("location")
                if loc:
                    return quote(str(loc), safe=":/%?&=#+,-")
    except Exception as e:
        logger.warning(f"Failed to resolve 302 redirect for {url}: {e}")
    return url

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

        async def process_stream(stream: dict):
            raw_url = stream.get("url", "")
            if "download.php" in raw_url or ".php" in raw_url or "uptomkv" in raw_url:
                resolved_url = await resolve_cdn_redirect(raw_url)
                if resolved_url != raw_url:
                    stream["url"] = resolved_url
                    stream["type"] = "direct"

        if deduplicated:
            await asyncio.gather(*(process_stream(s) for s in deduplicated))

        deduplicated.sort(key=lambda x: 0 if any(k in x.get("provider", "") for k in ["Original", "PreDVD", "Isaimini"]) else 1)
        self._stream_cache.set(cache_key, deduplicated)
        return deduplicated

    async def resolve_streams(
        self,
        tmdb_id: int,
        media_type: str = "movie",
        season: int | None = None,
        episode: int | None = None,
        bypass_cache: bool = False
    ) -> dict | None:
        if media_type == "movie":
            details = await tmdb_client.get_movie_details(tmdb_id)
            if not details:
                local = catalog_service.get_movie_by_tmdb_id(tmdb_id)
                if local:
                    title = local["title"]
                    year = local.get("year") or 0
                    imdb_id = local.get("imdb_id")
                else:
                    return None
            else:
                title = details.get("title")
                release_date = details.get("release_date", "")
                year = int(release_date.split("-")[0]) if release_date else 0
                imdb_id = details.get("imdb_id")
        else:
            details = await tmdb_client.get_tv_details(tmdb_id)
            if not details:
                return None
            title = details.get("name")
            first_air_date = details.get("first_air_date", "")
            year = int(first_air_date.split("-")[0]) if first_air_date else 0
            external_ids = details.get("external_ids", {})
            imdb_id = external_ids.get("imdb_id")

        links = await self.get_streams(
            title=title,
            year=year,
            media_type=media_type,
            tmdb_id=tmdb_id,
            imdb_id=imdb_id,
            season=season,
            episode=episode,
            bypass_cache=bypass_cache
        )

        cache_key = f"{tmdb_id}_{season}_{episode}"
        return StreamResponse(
            title=title,
            year=year,
            media_type=media_type,
            tmdb_id=tmdb_id,
            imdb_id=imdb_id,
            season=season,
            episode=episode,
            cache_expires_in=self._stream_cache.get_remaining_ttl(cache_key),
            streams=links
        )

scraper_manager = ScraperManager()
