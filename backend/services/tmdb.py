import logging
import time
from backend.config import settings
from backend.session import get_session

logger = logging.getLogger(__name__)

class TTLCache:
    """
    A lightweight, in-memory key-value cache with TTL expiration.
    """
    def __init__(self, ttl_seconds: int):
        self.ttl = ttl_seconds
        self.cache = {}

    def get(self, key):
        if key in self.cache:
            expire_time, val = self.cache[key]
            if time.time() < expire_time:
                return val
            else:
                del self.cache[key]  # Clean up expired entry
        return None

    def get_remaining_ttl(self, key) -> int:
        if key in self.cache:
            expire_time, _ = self.cache[key]
            remaining = int(expire_time - time.time())
            if remaining > 0:
                return remaining
            else:
                del self.cache[key]
        return 0

    def set(self, key, val, ttl: int | None = None):
        duration = ttl if ttl is not None else self.ttl
        self.cache[key] = (time.time() + duration, val)

    def clear(self):
        self.cache.clear()

class TMDBClient:
    BASE_URL = "https://api.themoviedb.org/3"

    def __init__(self):
        self.headers = {
            "Authorization": f"Bearer {settings.ReadAccessToken}",
            "accept": "application/json"
        }
        
        # Initialize Cache instances (TTL: 1 hour for searches, 24 hours for discover/details)
        self._search_cache = TTLCache(ttl_seconds=3600)
        self._discover_cache = TTLCache(ttl_seconds=86400)
        self._details_cache = TTLCache(ttl_seconds=86400)

    async def search_movie(self, query: str, year: int = None, page: int = 1) -> list[dict]:
        """
        Search for movies on TMDB, with in-memory TTL caching.
        """
        cache_key = f"{query}_{year}_{page}"
        cached_result = self._search_cache.get(cache_key)
        if cached_result is not None:
            logger.info(f"Serving search query '{query}' (page: {page}) from TMDB cache")
            return cached_result

        url = f"{self.BASE_URL}/search/movie"
        params = {
            "query": query,
            "page": str(page),
            "include_adult": "false"
        }
        if year:
            params["year"] = str(year)

        try:
            from datetime import date
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome")
            resp.raise_for_status()
            results = resp.json().get("results", [])
            
            # Filter out unreleased movies
            today_str = date.today().isoformat()
            filtered_results = [
                m for m in results
                if m.get("release_date") and m.get("release_date") <= today_str
            ]
            
            self._search_cache.set(cache_key, filtered_results)
            return filtered_results
        except Exception as e:
            logger.error(f"TMDB movie search failed for '{query}': {e}")
            return []

    async def search_tv(self, query: str, year: int = None) -> list[dict]:
        """
        Search for TV shows on TMDB.
        """
        url = f"{self.BASE_URL}/search/tv"
        params = {
            "query": query,
            "include_adult": "false"
        }
        if year:
            params["first_air_date_year"] = str(year)

        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome")
            resp.raise_for_status()
            results = resp.json().get("results", [])
            return results
        except Exception as e:
            logger.error(f"TMDB TV search failed for '{query}': {e}")
            return []

    async def get_movie_details(self, movie_id: int) -> dict | None:
        """
        Get full details for a movie, with in-memory TTL caching.
        """
        cached_result = self._details_cache.get(movie_id)
        if cached_result is not None:
            return cached_result

        url = f"{self.BASE_URL}/movie/{movie_id}"
        params = {"append_to_response": "external_ids,credits"}

        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome")
            resp.raise_for_status()
            details = resp.json()
            
            self._details_cache.set(movie_id, details)
            return details
        except Exception as e:
            logger.error(f"Failed to fetch TMDB movie details for id {movie_id}: {e}")
            return None

    async def get_tv_details(self, tv_id: int) -> dict | None:
        """
        Get full details for a TV show.
        """
        url = f"{self.BASE_URL}/tv/{tv_id}"
        params = {"append_to_response": "external_ids,credits"}

        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome")
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            logger.error(f"Failed to fetch TMDB TV details for id {tv_id}: {e}")
            return None

    async def get_popular_movies(self, language: str = "en-US", page: int = 1) -> list[dict]:
        return await self.discover_movies(language=language, page=page, sort_by="popularity.desc")

    async def discover_movies(self, language: str = "en-US", year: int | None = None, genre: int | None = None, page: int = 1, sort_by: str | None = None) -> list[dict]:
        cache_key = f"{language}_{year}_{genre}_{sort_by}_{page}"
        cached_result = self._discover_cache.get(cache_key)
        if cached_result is not None:
            logger.info(f"Serving discovered movies (language: {language}, year: {year}, genre: {genre}, sort_by: {sort_by}, page: {page}) from TMDB cache")
            return cached_result

        url = f"{self.BASE_URL}/discover/movie"
        lang_code = language.split("-")[0] if "-" in language else language
        
        from datetime import date
        today_str = date.today().isoformat()
        
        params = {
            "with_original_language": lang_code,
            "page": str(page),
            "primary_release_date.lte": today_str,
            "include_adult": "false"
        }
        
        if genre:
            params["with_genres"] = str(genre)
            
        if sort_by:
            params["sort_by"] = sort_by
        elif year:
            params["primary_release_year"] = str(year)
            params["sort_by"] = "popularity.desc"
        else:
            params["sort_by"] = "primary_release_date.desc"

        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome")
            resp.raise_for_status()
            results = resp.json().get("results", [])
            
            self._discover_cache.set(cache_key, results)
            return results
        except Exception as e:
            logger.error(f"TMDB discover failed for lang '{lang_code}', year '{year}', genre '{genre}': {e}")
            return []

    async def find_movie_by_imdb_id(self, imdb_id: str) -> dict | None:
        url = f"{self.BASE_URL}/find/{imdb_id}"
        params = {"external_source": "imdb_id"}
        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome")
            resp.raise_for_status()
            data = resp.json()
            movie_results = data.get("movie_results", [])
            if movie_results:
                return movie_results[0]
            tv_results = data.get("tv_results", [])
            if tv_results:
                return tv_results[0]
            return None
        except Exception as e:
            logger.error(f"Failed to find TMDB item for IMDb ID '{imdb_id}': {e}")
            return None

tmdb_client = TMDBClient()
