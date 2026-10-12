import asyncio
import json
import logging
import time
from urllib.parse import urljoin
from typing import AsyncGenerator
from backend.services.tmdb import tmdb_client
from backend.services.catalog import catalog_service
from backend.services.cache_db import (
    get_cached_streams,
    save_cached_streams,
    delete_cached_streams,
)
from backend.models import StreamResponse
from backend.config import settings
from backend.session import get_session
from backend.scrappers.base import BaseScraper, MediaItem, StreamSource
from backend.scrappers.providers import (
    IsaiminiScraper,
    VidSrcScraper,
    StremioScraper,
)
from backend.logger import (
    scraper_start_tag,
    scraper_exec_tag,
    scraper_error_tag,
    scraper_done_tag,
    scraper_cache_tag,
)

logger = logging.getLogger(__name__)


def _curate_streams(streams: list[dict], max_total: int = 15) -> list[dict]:
    streams.sort(key=lambda x: x.get("priority", 100))
    return streams[:max_total]


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
            StremioScraper(name="PenguPlay", manifest_url=settings.PENGUPLAY_MANIFEST_URL),
            StremioScraper(name="HdHub", manifest_url=settings.HDHUB_MANIFEST_URL),
            IsaiminiScraper(),
        ]
        self._in_flight: dict[str, asyncio.Task] = {}
        self._broadcasters: dict[str, StreamBroadcaster] = {}

    def register_scraper(self, scraper: BaseScraper):
        self.scrapers.append(scraper)

    async def _get_media_info(
        self, tmdb_id: int, media_type: str = "movie"
    ) -> tuple[str | None, int, str | None, str | None, list[str], int | None]:
        if media_type == "tv":
            details = await tmdb_client.get_tv_details(tmdb_id)
            if not details:
                return None, 0, None, None, [], None
            title = details.get("name") or details.get("original_name") or ""
            release_date = details.get("first_air_date") or ""
            year = int(release_date.split("-")[0]) if release_date else 0
            imdb_id = details.get("imdb_id") or details.get("external_ids", {}).get("imdb_id")
            original_language = details.get("original_language")
            prod_countries = details.get("production_countries") or []
            origin_countries = details.get("origin_country") or [
                c.get("iso_3166_1") for c in prod_countries if isinstance(c, dict) and c.get("iso_3166_1")
            ]
            runtimes = details.get("episode_run_time") or []
            runtime = runtimes[0] if runtimes else None
            return title, year, imdb_id, original_language, origin_countries, runtime

        details = await tmdb_client.get_movie_details(tmdb_id)
        if not details:
            local = catalog_service.get_movie_by_tmdb_id(tmdb_id)
            if local:
                return local["title"], local.get("year") or 0, local.get("imdb_id"), "ta", ["IN"], None
            return None, 0, None, None, [], None
        title = details.get("title")
        release_date = details.get("release_date") or ""
        year = int(release_date.split("-")[0]) if release_date else 0
        imdb_id = details.get("imdb_id")
        original_language = details.get("original_language")
        prod_countries = details.get("production_countries") or []
        origin_countries = details.get("origin_country") or [
            c.get("iso_3166_1") for c in prod_countries if isinstance(c, dict) and c.get("iso_3166_1")
        ]
        runtime = details.get("runtime")
        return title, year, imdb_id, original_language, origin_countries, runtime

    def _are_all_scrapers_cached(
        self,
        tmdb_id: int,
        season: int | None = None,
        episode: int | None = None,
    ) -> bool:
        for s in self.scrapers:
            cached = get_cached_streams(
                tmdb_id=tmdb_id,
                season=season,
                episode=episode,
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
                season=media.season,
                episode=media.episode,
            )

        scrapers_to_run: list[BaseScraper] = []
        if not bypass_cache and media.tmdb_id:
            for s in self.scrapers:
                cached_for_s = get_cached_streams(
                    tmdb_id=media.tmdb_id,
                    season=media.season,
                    episode=media.episode,
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
                season=media.season,
                episode=media.episode,
            )
            if all_cached:
                logger.info(scraper_cache_tag(media.title, len(all_cached)))
                return all_cached

        logger.info(scraper_start_tag(media.title, media.year, media.tmdb_id, [s.name for s in scrapers_to_run]))

        async def _timed_scrape(scraper: BaseScraper):
            t0 = time.time()
            try:
                sources = await scraper.scrape(media, on_progress=on_progress)
                elapsed = time.time() - t0
                return scraper.name, sources, elapsed, None
            except Exception as e:
                elapsed = time.time() - t0
                return scraper.name, None, elapsed, e

        tasks = [_timed_scrape(s) for s in scrapers_to_run]
        results = await asyncio.gather(*tasks)

        session = get_session()
        for scraper_name, res, elapsed, err in results:
            if err:
                logger.error(scraper_error_tag(scraper_name, str(err), elapsed))
                continue

            if res:
                logger.info(scraper_exec_tag(scraper_name, len(res), elapsed))
                seen_urls = set()
                new_streams: list[dict] = []
                for item in res:
                    if item.url and item.url not in seen_urls:
                        seen_urls.add(item.url)
                        ttl = item.ttl if item.ttl is not None else 10800
                        exp = item.expires_at if item.expires_at is not None else (now + ttl)
                        new_streams.append({
                            "url": item.url,
                            "quality": item.quality,
                            "provider": item.provider,
                            "scraper_id": scraper_name.lower(),
                            "headers": item.headers,
                            "priority": item.priority,
                            "size_mb": item.size_mb,
                            "formatted_size": item.formatted_size,
                            "bitrate_kbps": item.bitrate_kbps,
                            "bitrate_str": item.bitrate_str,
                            "languages": item.languages,
                            "source": item.source,
                            "host": item.host,
                            "filename": item.filename,
                            "created_at": now,
                            "expires_at": exp,
                            "ttl": ttl,
                            "remaining_ttl": max(0, exp - now),
                        })

                if media.tmdb_id and new_streams:
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
                logger.info(scraper_exec_tag(scraper_name, 0, elapsed))

        all_valid_streams = get_cached_streams(
            tmdb_id=media.tmdb_id,
            season=media.season,
            episode=media.episode,
        ) if media.tmdb_id else []

        all_valid_streams.sort(key=lambda x: x.get("priority", 100))
        curated_streams = all_valid_streams

        logger.info(scraper_done_tag(media.title, len(curated_streams)))
        
        print(f"\n{'='*75}")
        print(f" [STREAMS CONSOLE] Found {len(curated_streams)} stream(s) for '{media.title}':")
        print(f"{'='*75}")
        for idx, s in enumerate(curated_streams, 1):
            prio = s.get("priority", 100)
            prov = s.get("provider", "Unknown")
            qual = s.get("quality", "HD")
            langs = "+".join(s.get("languages", [])) or "Unknown"
            size = s.get("formatted_size", "")
            bitrate = s.get("bitrate_str", "")
            url = s.get("url", "")
            print(f" [{idx:02d}] (Prio {prio}) {prov} [{qual}] [{langs}] {size} {bitrate}")
            print(f"      -> {url}")
        print(f"{'='*75}\n")

        return curated_streams

    async def _execute_resolve_task(
        self,
        cache_key: str,
        broadcaster: StreamBroadcaster,
        tmdb_id: int,
        media_type: str = "movie",
        season: int | None = None,
        episode: int | None = None,
        bypass_cache: bool = False,
    ) -> StreamResponse | None:
        try:
            title, year, imdb_id, original_language, origin_countries, runtime = await self._get_media_info(
                tmdb_id, media_type
            )
            if not title:
                broadcaster.finish(error="Media not found on TMDB.")
                return None

            desc = f"{title} ({year})" if media_type == "movie" else f"{title} S{season or 1}E{episode or 1}"
            broadcaster.emit("init", f"Searching sources for {desc}")

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
                runtime_minutes=runtime,
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
                media_type=media_type,
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
        media_type: str = "movie",
        season: int | None = None,
        episode: int | None = None,
        bypass_cache: bool = False,
    ) -> AsyncGenerator[str, None]:
        clean_type = (media_type or "movie").strip().lower()
        s_num = season if clean_type == "tv" else 0
        e_num = episode if clean_type == "tv" else 0
        cache_key = f"{tmdb_id}:{clean_type}:{s_num or 0}:{e_num or 0}"

        if not bypass_cache and self._are_all_scrapers_cached(tmdb_id, season=s_num, episode=e_num):
            disk_streams = get_cached_streams(
                tmdb_id=tmdb_id,
                season=s_num,
                episode=e_num,
            )
            if disk_streams:
                title, year, imdb_id, _, _, _ = await self._get_media_info(tmdb_id, clean_type)
                min_remaining = min([s.get("remaining_ttl", 3600) for s in disk_streams]) if disk_streams else 0
                resp = StreamResponse(
                    title=title or "",
                    year=year,
                    media_type=clean_type,
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
                    media_type=clean_type,
                    season=s_num,
                    episode=e_num,
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
