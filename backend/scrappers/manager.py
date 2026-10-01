import asyncio
import json
import logging
import time
from typing import AsyncGenerator
from backend.services.tmdb import tmdb_client, TTLCache
from backend.services.catalog import catalog_service
from backend.services.cache_db import (
    get_cached_streams,
    save_cached_streams,
    delete_cached_streams,
)
from backend.models import StreamResponse
from backend.scrappers.base import BaseScraper, MediaItem, StreamSource
from backend.scrappers.providers import IsaiminiScraper, VidSrcScraper

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
                "error": self.error,
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
            "error": error,
        }
        for q in self._listeners:
            q.put_nowait(event)


class ScraperManager:
    def __init__(self):
        self.scrapers: list[BaseScraper] = [
            IsaiminiScraper(),
            VidSrcScraper(),
        ]
        self._in_flight: dict[str, asyncio.Task] = {}
        self._broadcasters: dict[str, StreamBroadcaster] = {}

    def register_scraper(self, scraper: BaseScraper):
        self.scrapers.append(scraper)

    async def _get_media_info(
        self, tmdb_id: int, media_type: str = "movie"
    ) -> tuple[str | None, int, str | None, str | None, list[str]]:
        if media_type == "movie":
            details = await tmdb_client.get_movie_details(tmdb_id)
            if not details:
                local = catalog_service.get_movie_by_tmdb_id(tmdb_id)
                if local:
                    return local["title"], local.get("year") or 0, local.get("imdb_id"), "ta", ["IN"]
                return None, 0, None, None, []
            title = details.get("title")
            release_date = details.get("release_date") or ""
            year = int(release_date.split("-")[0]) if release_date else 0
            imdb_id = details.get("imdb_id")
            original_language = details.get("original_language")
            prod_countries = details.get("production_countries") or []
            origin_countries = details.get("origin_country") or [
                c.get("iso_3166_1") for c in prod_countries if isinstance(c, dict) and c.get("iso_3166_1")
            ]
            return title, year, imdb_id, original_language, origin_countries
        else:
            details = await tmdb_client.get_tv_details(tmdb_id)
            if not details:
                return None, 0, None, None, []
            title = details.get("name")
            first_air_date = details.get("first_air_date") or ""
            year = int(first_air_date.split("-")[0]) if first_air_date else 0
            external_ids = details.get("external_ids") or {}
            imdb_id = external_ids.get("imdb_id")
            original_language = details.get("original_language")
            prod_countries = details.get("production_countries") or []
            origin_countries = details.get("origin_country") or [
                c.get("iso_3166_1") for c in prod_countries if isinstance(c, dict) and c.get("iso_3166_1")
            ]
            return title, year, imdb_id, original_language, origin_countries

    async def get_streams(
        self,
        media: MediaItem,
        provider: str | None = None,
        bypass_cache: bool = False,
        on_progress=None,
    ) -> list[dict]:
        now = int(time.time())

        # If bypass_cache is requested, purge target provider (or all) from persistent disk cache
        if bypass_cache and media.tmdb_id:
            delete_cached_streams(
                tmdb_id=media.tmdb_id,
                provider=provider,
                season=media.season,
                episode=media.episode,
            )

        # Check persistent disk cache if not bypassing
        if not bypass_cache and media.tmdb_id:
            disk_streams = get_cached_streams(
                tmdb_id=media.tmdb_id,
                season=media.season,
                episode=media.episode,
                provider=provider,
            )
            if disk_streams:
                logger.info(f"Serving {len(disk_streams)} streams for TMDB {media.tmdb_id} from SQLite disk cache")
                return disk_streams

        # Determine target scrapers
        target_scrapers = [
            s for s in self.scrapers
            if not provider or s.name.lower() == provider.lower()
        ]
        if not target_scrapers:
            target_scrapers = self.scrapers

        logger.info(
            f"Orchestrating scrapers for: {media.title} ({media.year}) | TMDb: {media.tmdb_id} | Provider: {provider or 'ALL'}"
        )

        tasks = [
            scraper.scrape(media, on_progress=on_progress)
            for scraper in target_scrapers
        ]

        try:
            results = await asyncio.gather(*tasks, return_exceptions=True)
        except Exception as e:
            logger.error(f"Error gathering scraping tasks: {e}")
            return []

        flat_results: list[StreamSource] = []
        for i, res in enumerate(results):
            scraper_name = target_scrapers[i].name
            if isinstance(res, Exception):
                logger.error(f"Scraper '{scraper_name}' raised an exception: {res}")
                continue

            if res:
                logger.info(f"Scraper '{scraper_name}' returned {len(res)} stream sources.")
                flat_results.extend(res)
            else:
                logger.info(f"Scraper '{scraper_name}' returned no sources.")

        seen_urls = set()
        new_streams: list[dict] = []
        for item in flat_results:
            if item.url and item.url not in seen_urls:
                seen_urls.add(item.url)
                ttl = item.ttl if item.ttl is not None else 86400  # Default 24h
                exp = item.expires_at if item.expires_at is not None else (now + ttl)
                new_streams.append({
                    "url": item.url,
                    "quality": item.quality,
                    "provider": item.provider,
                    "headers": item.headers,
                    "priority": item.priority,
                    "created_at": now,
                    "expires_at": exp,
                    "ttl": ttl,
                    "remaining_ttl": max(0, exp - now),
                })

        # Save freshly scraped streams to SQLite on-disk cache
        if media.tmdb_id and new_streams:
            save_cached_streams(
                tmdb_id=media.tmdb_id,
                streams=new_streams,
                season=media.season,
                episode=media.episode,
            )

        # Retrieve all currently valid cached streams (combining all providers)
        all_valid_streams = get_cached_streams(
            tmdb_id=media.tmdb_id,
            season=media.season,
            episode=media.episode,
        ) if media.tmdb_id else new_streams

        all_valid_streams.sort(key=lambda x: x.get("priority", 100))
        return all_valid_streams

    async def _execute_resolve_task(
        self,
        cache_key: str,
        broadcaster: StreamBroadcaster,
        tmdb_id: int,
        media_type: str,
        season: int | None,
        episode: int | None,
        provider: str | None,
        bypass_cache: bool,
    ) -> StreamResponse | None:
        try:
            title, year, imdb_id, original_language, origin_countries = await self._get_media_info(
                tmdb_id, media_type
            )
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
                episode=episode,
                original_language=original_language,
                origin_countries=origin_countries,
            )

            links = await self.get_streams(
                media=media,
                provider=provider,
                bypass_cache=bypass_cache,
                on_progress=on_progress,
            )

            min_remaining = min([s.get("remaining_ttl", 3600) for s in links]) if links else 0

            resp = StreamResponse(
                title=title,
                year=year,
                media_type=media_type,
                tmdb_id=tmdb_id,
                imdb_id=imdb_id,
                season=season,
                episode=episode,
                cache_expires_in=min_remaining,
                streams=links,
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
        provider: str | None = None,
        bypass_cache: bool = False,
    ) -> StreamResponse | None:
        cache_key = f"{tmdb_id}_{season}_{episode}_{provider or 'all'}"

        if not bypass_cache:
            disk_streams = get_cached_streams(
                tmdb_id=tmdb_id,
                season=season,
                episode=episode,
                provider=provider,
            )
            if disk_streams:
                title, year, imdb_id, _, _ = await self._get_media_info(tmdb_id, media_type)
                min_remaining = min([s.get("remaining_ttl", 3600) for s in disk_streams]) if disk_streams else 0
                return StreamResponse(
                    title=title or "",
                    year=year,
                    media_type=media_type,
                    tmdb_id=tmdb_id,
                    imdb_id=imdb_id,
                    season=season,
                    episode=episode,
                    cache_expires_in=min_remaining,
                    streams=disk_streams,
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
                provider=provider,
                bypass_cache=bypass_cache,
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
        provider: str | None = None,
        bypass_cache: bool = False,
    ) -> AsyncGenerator[str, None]:
        cache_key = f"{tmdb_id}_{season}_{episode}_{provider or 'all'}"

        if not bypass_cache:
            disk_streams = get_cached_streams(
                tmdb_id=tmdb_id,
                season=season,
                episode=episode,
                provider=provider,
            )
            if disk_streams:
                title, year, imdb_id, _, _ = await self._get_media_info(tmdb_id, media_type)
                min_remaining = min([s.get("remaining_ttl", 3600) for s in disk_streams]) if disk_streams else 0
                resp = StreamResponse(
                    title=title or "",
                    year=year,
                    media_type=media_type,
                    tmdb_id=tmdb_id,
                    imdb_id=imdb_id,
                    season=season,
                    episode=episode,
                    cache_expires_in=min_remaining,
                    streams=disk_streams,
                )
                yield f"data: {json.dumps({'step': 'cached', 'message': 'Loaded from SQLite disk cache'})}\n\n"
                yield f"data: {json.dumps({'step': 'done', 'result': resp.model_dump()})}\n\n"
                return

        if cache_key not in self._broadcasters:
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
                    provider=provider,
                    bypass_cache=bypass_cache,
                )
            )
            self._in_flight[cache_key] = task
        else:
            broadcaster = self._broadcasters[cache_key]

        queue = broadcaster.subscribe()
        try:
            while True:
                event = await queue.get()
                yield f"data: {json.dumps(event)}\n\n"
                if event.get("step") == "done":
                    break
        finally:
            broadcaster.unsubscribe(queue)


scraper_manager = ScraperManager()
