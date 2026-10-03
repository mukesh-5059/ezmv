import os
import asyncio
import logging
from datetime import datetime
from dotenv import load_dotenv
from curl_cffi.requests import AsyncSession
from backend.models import MovieSummary, TraktListSummary
from backend.services.tmdb import tmdb_client, get_tmdb_cache, set_tmdb_cache

load_dotenv()
logger = logging.getLogger(__name__)


class TraktClient:
    BASE_URL = "https://api.trakt.tv"

    def __init__(self):
        self.client_id = os.getenv("TRAKT_CLIENT_ID", "").strip()

    @property
    def headers(self) -> dict:
        return {
            "Content-Type": "application/json",
            "trakt-api-version": "2",
            "trakt-api-key": self.client_id,
        }

    async def _enrich_tmdb_movies(self, raw_items: list[dict]) -> list[MovieSummary]:
        seen_keys = set()
        tasks = []
        item_types = []

        for item in raw_items:
            item_type = item.get("type", "")
            if item_type in ("show", "season", "episode") or ("show" in item and "movie" not in item):
                show_data = item.get("show", item)
                tmdb_id = show_data.get("ids", {}).get("tmdb")
                if tmdb_id and ("tv", tmdb_id) not in seen_keys:
                    seen_keys.add(("tv", tmdb_id))
                    tasks.append(tmdb_client.get_tv_details(tmdb_id))
                    item_types.append("tv")
            else:
                movie_data = item.get("movie", item)
                tmdb_id = movie_data.get("ids", {}).get("tmdb")
                if tmdb_id and ("movie", tmdb_id) not in seen_keys:
                    seen_keys.add(("movie", tmdb_id))
                    tasks.append(tmdb_client.get_movie_details(tmdb_id))
                    item_types.append("movie")

        if not tasks:
            return []

        results = await asyncio.gather(*tasks, return_exceptions=True)
        summaries = []
        for res, m_type in zip(results, item_types):
            if isinstance(res, dict) and res.get("id"):
                summaries.append(MovieSummary.from_tmdb(res, media_type=m_type))
        return summaries

    async def get_trending(self, page: int = 1, limit: int = 20) -> list[MovieSummary]:
        cache_key = f"trakt:trending:{page}_{limit}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return [MovieSummary(**m) for m in cached]

        if not self.client_id:
            logger.warning("TRAKT_CLIENT_ID not set. Falling back to empty trending list.")
            return []

        url = f"{self.BASE_URL}/movies/trending"
        params = {"page": str(page), "limit": str(limit), "extended": "full"}
        try:
            async with AsyncSession(impersonate="chrome") as session:
                resp = await session.get(url, headers=self.headers, params=params, timeout=25.0)
                resp.raise_for_status()
                raw_items = resp.json()

            summaries = await self._enrich_tmdb_movies(raw_items)
            if summaries:
                set_tmdb_cache(cache_key, [s.model_dump() for s in summaries], ttl_seconds=43200)
            return summaries
        except Exception as e:
            logger.error(f"Failed to fetch Trakt trending: {e}")
            return []

    async def get_watched(self, period: str = "weekly", page: int = 1, limit: int = 20) -> list[MovieSummary]:
        cache_key = f"trakt:watched:{period}_{page}_{limit}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return [MovieSummary(**m) for m in cached]

        if not self.client_id:
            return []

        url = f"{self.BASE_URL}/movies/watched/{period}"
        params = {"page": str(page), "limit": str(limit), "extended": "full"}
        try:
            async with AsyncSession(impersonate="chrome") as session:
                resp = await session.get(url, headers=self.headers, params=params, timeout=25.0)
                resp.raise_for_status()
                raw_items = resp.json()

            summaries = await self._enrich_tmdb_movies(raw_items)
            if summaries:
                set_tmdb_cache(cache_key, [s.model_dump() for s in summaries], ttl_seconds=43200)
            return summaries
        except Exception as e:
            logger.error(f"Failed to fetch Trakt watched ({period}): {e}")
            return []

    async def get_box_office(self) -> list[MovieSummary]:
        cache_key = "trakt:boxoffice"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return [MovieSummary(**m) for m in cached]

        if not self.client_id:
            return []

        url = f"{self.BASE_URL}/movies/boxoffice"
        try:
            async with AsyncSession(impersonate="chrome") as session:
                resp = await session.get(url, headers=self.headers, params={"extended": "full"}, timeout=25.0)
                resp.raise_for_status()
                raw_items = resp.json()

            summaries = await self._enrich_tmdb_movies(raw_items)
            if summaries:
                set_tmdb_cache(cache_key, [s.model_dump() for s in summaries], ttl_seconds=43200)
            return summaries
        except Exception as e:
            logger.error(f"Failed to fetch Trakt box office: {e}")
            return []

    async def get_anticipated(self, page: int = 1, limit: int = 20) -> list[MovieSummary]:
        cache_key = f"trakt:anticipated:{page}_{limit}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return [MovieSummary(**m) for m in cached]

        if not self.client_id:
            return []

        url = f"{self.BASE_URL}/movies/anticipated"
        params = {"page": str(page), "limit": str(limit), "extended": "full"}
        try:
            async with AsyncSession(impersonate="chrome") as session:
                resp = await session.get(url, headers=self.headers, params=params, timeout=25.0)
                resp.raise_for_status()
                raw_items = resp.json()

            summaries = await self._enrich_tmdb_movies(raw_items)
            if summaries:
                set_tmdb_cache(cache_key, [s.model_dump() for s in summaries], ttl_seconds=43200)
            return summaries
        except Exception as e:
            logger.error(f"Failed to fetch Trakt anticipated: {e}")
            return []

    async def get_list_items(self, list_id: str, page: int = 1, limit: int = 20) -> list[MovieSummary]:
        cache_key = f"trakt:list:{list_id}:{page}_{limit}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return [MovieSummary(**m) for m in cached]

        if not self.client_id:
            return []

        url = f"{self.BASE_URL}/lists/{list_id}/items"
        params = {"page": str(page), "limit": str(limit), "extended": "full"}
        try:
            async with AsyncSession(impersonate="chrome") as session:
                resp = await session.get(url, headers=self.headers, params=params, timeout=25.0)
                resp.raise_for_status()
                raw_items = resp.json()

            summaries = await self._enrich_tmdb_movies(raw_items)
            if summaries:
                set_tmdb_cache(cache_key, [s.model_dump() for s in summaries], ttl_seconds=43200)
            return summaries
        except Exception as e:
            logger.error(f"Failed to fetch Trakt list {list_id}: {e}")
            return []


    async def search_movies(
        self,
        query: str,
        year: int | None = None,
        language: str | None = None,
        page: int = 1,
        limit: int = 20,
    ) -> list[MovieSummary]:
        clean_q = (query or "").strip()
        if not clean_q:
            return []

        cache_key = f"trakt:search:{clean_q}_{year}_{language}_{page}_{limit}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return [MovieSummary(**m) for m in cached]

        if not self.client_id:
            return []

        url = f"{self.BASE_URL}/search/movie,show"
        params = {"query": clean_q, "page": str(page), "limit": str(limit), "extended": "full"}
        if year:
            params["years"] = str(year)
        if language == "anime":
            params["languages"] = "ja"
            params["genres"] = "animation"
        elif language and language != "all":
            params["languages"] = language.split("-")[0]

        try:
            async with AsyncSession(impersonate="chrome") as session:
                resp = await session.get(url, headers=self.headers, params=params, timeout=25.0)
                resp.raise_for_status()
                raw_items = resp.json()

            summaries = await self._enrich_tmdb_movies(raw_items)
            if len(clean_q) >= 2 and len(summaries) > 0:
                set_tmdb_cache(cache_key, [s.model_dump() for s in summaries], ttl_seconds=86400)
            return summaries
        except Exception as e:
            logger.error(f"Failed to search Trakt movies for '{query}': {e}")
            return []


    async def get_popular_lists(self, page: int = 1, limit: int = 20) -> list[TraktListSummary]:
        cache_key = f"trakt:lists:popular:{page}_{limit}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return [TraktListSummary(**item) for item in cached]

        if not self.client_id:
            return []

        url = f"{self.BASE_URL}/lists/popular"
        params = {"page": str(page), "limit": str(limit)}
        try:
            async with AsyncSession(impersonate="chrome") as session:
                resp = await session.get(url, headers=self.headers, params=params, timeout=25.0)
                resp.raise_for_status()
                raw_items = resp.json()

            lists = []
            for entry in raw_items:
                l = entry.get("list", {})
                if l.get("name") and l.get("ids", {}).get("trakt"):
                    lists.append(
                        TraktListSummary(
                            id=str(l["ids"]["trakt"]),
                            name=l.get("name", ""),
                            description=l.get("description") or "",
                            item_count=l.get("item_count") or 0,
                            likes=l.get("likes") or 0,
                            user_name=l.get("user", {}).get("username") or "",
                            slug=l.get("ids", {}).get("slug") or "",
                        )
                    )
            if lists:
                set_tmdb_cache(cache_key, [l.model_dump() for l in lists], ttl_seconds=43200)
            return lists
        except Exception as e:
            logger.error(f"Failed to fetch popular Trakt lists: {e}")
            return []

    async def search_lists(self, query: str, page: int = 1, limit: int = 20) -> list[TraktListSummary]:
        clean_q = (query or "").strip()
        if not clean_q:
            return await self.get_popular_lists(page=page, limit=limit)

        cache_key = f"trakt:lists:search:{clean_q}_{page}_{limit}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return [TraktListSummary(**item) for item in cached]

        if not self.client_id:
            return []

        url = f"{self.BASE_URL}/search/list"
        params = {"query": clean_q, "page": str(page), "limit": str(limit)}
        try:
            async with AsyncSession(impersonate="chrome") as session:
                resp = await session.get(url, headers=self.headers, params=params, timeout=25.0)
                resp.raise_for_status()
                raw_items = resp.json()

            lists = []
            for entry in raw_items:
                l = entry.get("list", {})
                if l.get("name") and l.get("ids", {}).get("trakt"):
                    lists.append(
                        TraktListSummary(
                            id=str(l["ids"]["trakt"]),
                            name=l.get("name", ""),
                            description=l.get("description") or "",
                            item_count=l.get("item_count") or 0,
                            likes=l.get("likes") or 0,
                            user_name=l.get("user", {}).get("username") or "",
                            slug=l.get("ids", {}).get("slug") or "",
                        )
                    )
            lists.sort(key=lambda x: x.likes, reverse=True)
            if len(clean_q) >= 2 and len(lists) > 0:
                set_tmdb_cache(cache_key, [l.model_dump() for l in lists], ttl_seconds=43200)
            return lists
        except Exception as e:
            logger.error(f"Failed to search Trakt lists for '{query}': {e}")
            return []


trakt_client = TraktClient()
