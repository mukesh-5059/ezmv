import asyncio
import json
import logging
from typing import AsyncGenerator
from backend.services.tmdb import tmdb_client, TTLCache
from backend.services.catalog import catalog_service
from backend.models import StreamResponse, StreamSource as ModelStreamSource
from backend.scrappers.base import BaseScraper, MediaItem, StreamSource
from backend.scrappers.providers.isaimini import IsaiminiScraper

logger = logging.getLogger(__name__)

class StreamBroadcaster:
    def __init__(self):
        self._listeners: list[asyncio.Queue] = []
        self._history: list[dict] = []
        self.done: bool = False
        self.result: dict | None = None
        self.error: str | None = None

    def subscribe(self) -> asyncio.Queue:
        q = asyncio.Queue()
        for event in self._history:
            q.put_nowait(event)
        if self.done:
            q.put_nowait({
                "step": "done",
                "message": "Complete" if not self.error else f"Error: {self.error}",
                "result": self.result,
                "error": self.error
            })
        self._listeners.append(q)
        return q

    def unsubscribe(self, q: asyncio.Queue):
        if q in self._listeners:
            self._listeners.remove(q)

    def emit(self, step: str, message: str, **kwargs):
        event = {"step": step, "message": message, **kwargs}
        self._history.append(event)
        for q in self._listeners:
            q.put_nowait(event)

    def finish(self, result: dict | None = None, error: str | None = None):
        self.done = True
        self.result = result
        self.error = error
        event = {
            "step": "done",
            "message": "Complete" if not error else f"Error: {error}",
            "result": result,
            "error": error
        }
        for q in self._listeners:
            q.put_nowait(event)

class ScraperManager:
    def __init__(self):
        self.scrapers: list[BaseScraper] = [
            IsaiminiScraper()
        ]
        self._stream_cache = TTLCache(ttl_seconds=180)
        self._in_flight: dict[str, asyncio.Task] = {}
        self._broadcasters: dict[str, StreamBroadcaster] = {}

    def register_scraper(self, scraper: BaseScraper):
        self.scrapers.append(scraper)

    async def _get_media_info(self, tmdb_id: int, media_type: str = "movie") -> tuple[str | None, int, str | None]:
        if media_type == "movie":
            details = await tmdb_client.get_movie_details(tmdb_id)
            if not details:
                local = catalog_service.get_movie_by_tmdb_id(tmdb_id)
                if local:
                    return local["title"], local.get("year") or 0, local.get("imdb_id")
                return None, 0, None
            title = details.get("title")
            release_date = details.get("release_date", "")
            year = int(release_date.split("-")[0]) if release_date else 0
            imdb_id = details.get("imdb_id")
            return title, year, imdb_id
        else:
            details = await tmdb_client.get_tv_details(tmdb_id)
            if not details:
                return None, 0, None
            title = details.get("name")
            first_air_date = details.get("first_air_date", "")
            year = int(first_air_date.split("-")[0]) if first_air_date else 0
            external_ids = details.get("external_ids", {})
            imdb_id = external_ids.get("imdb_id")
            return title, year, imdb_id

    async def get_streams(
        self,
        media: MediaItem,
        bypass_cache: bool = False,
        on_progress = None
    ) -> list[dict]:
        cache_key = f"{media.tmdb_id}_{media.season}_{media.episode}"
        if not bypass_cache:
            cached_result = self._stream_cache.get(cache_key)
            if cached_result is not None:
                logger.info(f"Serving streams for TMDB {media.tmdb_id} from manager cache")
                return cached_result

        logger.info(f"Orchestrating scrapers for: {media.title} ({media.year}) | Type: {media.media_type} | TMDb: {media.tmdb_id} | IMDb: {media.imdb_id}")

        tasks = [
            scraper.scrape(media, on_progress=on_progress)
            for scraper in self.scrapers
        ]

        try:
            results = await asyncio.gather(*tasks, return_exceptions=True)
        except Exception as e:
            logger.error(f"Error gathering scraping tasks: {e}")
            return []

        flat_results: list[StreamSource] = []
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
        deduplicated: list[dict] = []
        for item in flat_results:
            if item.url and item.url not in seen_urls:
                seen_urls.add(item.url)
                deduplicated.append({
                    "url": item.url,
                    "quality": item.quality,
                    "provider": item.provider,
                    "headers": item.headers
                })

        deduplicated.sort(key=lambda x: 0 if any(k in x.get("provider", "") for k in ["Original", "PreDVD", "Isaimini"]) else 1)
        self._stream_cache.set(cache_key, deduplicated)

        for s in deduplicated:
            logger.info(f"🎬 [STREAM READY] {s.get('quality')} ({s.get('provider')}) -> {s.get('url')}")

        return deduplicated

    async def _execute_resolve_task(
        self,
        cache_key: str,
        broadcaster: StreamBroadcaster,
        tmdb_id: int,
        media_type: str,
        season: int | None,
        episode: int | None,
        bypass_cache: bool
    ) -> StreamResponse | None:
        try:
            title, year, imdb_id = await self._get_media_info(tmdb_id, media_type)
            if not title:
                broadcaster.finish(error="Media not found on TMDB.")
                return None

            broadcaster.emit("init", f"Searching sources for {title} ({year})")

            def on_progress(step: str, message: str):
                broadcaster.emit(step, message)

            media = MediaItem(
                title=title,
                year=year,
                media_type=media_type,
                tmdb_id=tmdb_id,
                imdb_id=imdb_id,
                season=season,
                episode=episode
            )

            links = await self.get_streams(
                media=media,
                bypass_cache=bypass_cache,
                on_progress=on_progress
            )

            resp = StreamResponse(
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
            broadcaster.finish(result=resp.model_dump())
            return resp
        except Exception as e:
            logger.error(f"Error resolving streams for TMDB {tmdb_id}: {e}", exc_info=True)
            broadcaster.finish(error=str(e))
            return None
        finally:
            self._in_flight.pop(cache_key, None)
            self._broadcasters.pop(cache_key, None)

    async def resolve_streams(
        self,
        tmdb_id: int,
        media_type: str = "movie",
        season: int | None = None,
        episode: int | None = None,
        bypass_cache: bool = False
    ) -> StreamResponse | None:
        cache_key = f"{tmdb_id}_{season}_{episode}"

        if not bypass_cache:
            cached_result = self._stream_cache.get(cache_key)
            if cached_result is not None:
                logger.info(f"Serving streams for TMDB {tmdb_id} from manager cache")
                title, year, imdb_id = await self._get_media_info(tmdb_id, media_type)
                return StreamResponse(
                    title=title or "",
                    year=year,
                    media_type=media_type,
                    tmdb_id=tmdb_id,
                    imdb_id=imdb_id,
                    season=season,
                    episode=episode,
                    cache_expires_in=self._stream_cache.get_remaining_ttl(cache_key),
                    streams=cached_result
                )

        if cache_key in self._in_flight:
            return await self._in_flight[cache_key]

        broadcaster = StreamBroadcaster()
        self._broadcasters[cache_key] = broadcaster
        task = asyncio.create_task(
            self._execute_resolve_task(
                cache_key=cache_key,
                broadcaster=broadcaster,
                tmdb_id=tmdb_id,
                media_type=media_type,
                season=season,
                episode=episode,
                bypass_cache=bypass_cache
            )
        )
        self._in_flight[cache_key] = task
        return await task

    async def stream_events(
        self,
        tmdb_id: int,
        media_type: str = "movie",
        season: int | None = None,
        episode: int | None = None,
        bypass_cache: bool = False
    ) -> AsyncGenerator[str, None]:
        cache_key = f"{tmdb_id}_{season}_{episode}"

        if not bypass_cache:
            cached_result = self._stream_cache.get(cache_key)
            if cached_result is not None:
                title, year, imdb_id = await self._get_media_info(tmdb_id, media_type)
                resp = StreamResponse(
                    title=title or "",
                    year=year,
                    media_type=media_type,
                    tmdb_id=tmdb_id,
                    imdb_id=imdb_id,
                    season=season,
                    episode=episode,
                    cache_expires_in=self._stream_cache.get_remaining_ttl(cache_key),
                    streams=cached_result
                )
                yield f"data: {json.dumps({'step': 'cached', 'message': 'Loaded from cache'})}\n\n"
                yield f"data: {json.dumps({'step': 'done', 'result': resp.model_dump()})}\n\n"
                return

        if cache_key in self._broadcasters:
            broadcaster = self._broadcasters[cache_key]
        else:
            broadcaster = StreamBroadcaster()
            self._broadcasters[cache_key] = broadcaster
            task = asyncio.create_task(
                self._execute_resolve_task(
                    cache_key=cache_key,
                    broadcaster=broadcaster,
                    tmdb_id=tmdb_id,
                    media_type=media_type,
                    season=season,
                    episode=episode,
                    bypass_cache=bypass_cache
                )
            )
            self._in_flight[cache_key] = task

        q = broadcaster.subscribe()
        try:
            while True:
                event = await q.get()
                yield f"data: {json.dumps(event)}\n\n"
                if event.get("step") == "done":
                    break
        finally:
            broadcaster.unsubscribe(q)

scraper_manager = ScraperManager()
