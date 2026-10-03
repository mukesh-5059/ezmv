import asyncio
import json
import logging
import time
from typing import AsyncGenerator
from backend.services.tmdb import tmdb_client
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
        return None, 0, None, None, []

    def _are_all_scrapers_cached(
        self,
        tmdb_id: int,
    ) -> bool:
        for s in self.scrapers:
            cached = get_cached_streams(
                tmdb_id=tmdb_id,
                scraper_id=s.name,
            )
            if not cached:
                return False
        return True

    async def get_streams(
        self,
        media: MediaItem,
        bypass_cache: bool = False,
        on_progress=None,
    ) -> list[dict]:
        now = int(time.time())

        # If bypass_cache is requested, purge all providers from persistent disk cache
        if bypass_cache and media.tmdb_id:
            delete_cached_streams(
                tmdb_id=media.tmdb_id,
            )

        scrapers_to_run: list[BaseScraper] = []
        if not bypass_cache and media.tmdb_id:
            for s in self.scrapers:
                cached_for_s = get_cached_streams(
                    tmdb_id=media.tmdb_id,
                    scraper_id=s.name,
                )
                if not cached_for_s:
                    scrapers_to_run.append(s)
        else:
            scrapers_to_run = self.scrapers

        # If all scrapers have valid unexpired streams in cache, return all cached streams!
        if not scrapers_to_run and media.tmdb_id:
            all_cached = get_cached_streams(
                tmdb_id=media.tmdb_id,
            )
            if all_cached:
                logger.info(f"Serving {len(all_cached)} cached streams for TMDB {media.tmdb_id}")
                return all_cached

        logger.info(
            f"Orchestrating scrapers for: {media.title} ({media.year}) | TMDb: {media.tmdb_id} | Running: {[s.name for s in scrapers_to_run]}"
        )

        tasks = [
            scraper.scrape(media, on_progress=on_progress)
            for scraper in scrapers_to_run
        ]

        try:
            results = await asyncio.gather(*tasks, return_exceptions=True)
        except Exception as e:
            logger.error(f"Error gathering scraping tasks: {e}")
            results = []

        for i, res in enumerate(results):
            scraper_name = scrapers_to_run[i].name
            if isinstance(res, Exception):
                logger.error(f"Scraper '{scraper_name}' raised an exception: {res}")
                continue

            if res:
                logger.info(f"Scraper '{scraper_name}' returned {len(res)} stream sources.")
                seen_urls = set()
                new_streams: list[dict] = []
                for item in res:
                    if item.url and item.url not in seen_urls:
                        seen_urls.add(item.url)
                        ttl = item.ttl if item.ttl is not None else 300  # Minimum 5m fallback
                        exp = item.expires_at if item.expires_at is not None else (now + ttl)
                        new_streams.append({
                            "url": item.url,
                            "quality": item.quality,
                            "provider": item.provider,
                            "scraper_id": scraper_name.lower(),
                            "headers": item.headers,
                            "priority": item.priority,
                            "created_at": now,
                            "expires_at": exp,
                            "ttl": ttl,
                            "remaining_ttl": max(0, exp - now),
                        })

                if media.tmdb_id and new_streams:
                    # Delete old streams for this scraper and save fresh ones
                    delete_cached_streams(
                        tmdb_id=media.tmdb_id,
                        scraper_id=scraper_name.lower(),
                        season=media.season,
                        episode=media.episode,
                    )
                    save_cached_streams(
                        tmdb_id=media.tmdb_id,
                        streams=new_streams,
                        season=media.season,
                        episode=media.episode,
                    )
            else:
                logger.info(f"Scraper '{scraper_name}' returned no sources.")

        # Return all currently valid streams from DB (cached untouched + freshly scraped)
        all_valid_streams = get_cached_streams(
            tmdb_id=media.tmdb_id,
            season=media.season,
            episode=media.episode,
        ) if media.tmdb_id else []

        all_valid_streams.sort(key=lambda x: x.get("priority", 100))
        return all_valid_streams

    async def _execute_resolve_task(
        self,
        cache_key: str,
        broadcaster: StreamBroadcaster,
        tmdb_id: int,
        bypass_cache: bool,
    ) -> StreamResponse | None:
        try:
            title, year, imdb_id, original_language, origin_countries = await self._get_media_info(
                tmdb_id, "movie"
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
                media_type="movie",
                tmdb_id=tmdb_id,
                imdb_id=imdb_id,
                original_language=original_language,
                origin_countries=origin_countries,
            )

            links = await self.get_streams(
                media=media,
                bypass_cache=bypass_cache,
                on_progress=on_progress,
            )

            min_remaining = min([s.get("remaining_ttl", 3600) for s in links]) if links else 0

            resp = StreamResponse(
                title=title or "",
                year=year,
                media_type="movie",
                tmdb_id=tmdb_id,
                imdb_id=imdb_id,
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

    async def stream_events(
        self,
        tmdb_id: int,
        bypass_cache: bool = False,
    ) -> AsyncGenerator[str, None]:
        cache_key = f"{tmdb_id}"

        if not bypass_cache and self._are_all_scrapers_cached(tmdb_id):
            disk_streams = get_cached_streams(
                tmdb_id=tmdb_id,
            )
            if disk_streams:
                title, year, imdb_id, _, _ = await self._get_media_info(tmdb_id, "movie")
                min_remaining = min([s.get("remaining_ttl", 3600) for s in disk_streams]) if disk_streams else 0
                resp = StreamResponse(
                    title=title or "",
                    year=year,
                    media_type="movie",
                    tmdb_id=tmdb_id,
                    imdb_id=imdb_id,
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
