import logging
from curl_cffi import CurlOpt
from curl_cffi.requests import AsyncSession
from app.core.config import settings

logger = logging.getLogger(__name__)

class TMDBClient:
    BASE_URL = "https://api.themoviedb.org/3"

    def __init__(self):
        self.headers = {
            "Authorization": f"Bearer {settings.ReadAccessToken}",
            "accept": "application/json"
        }
        # Native DNS-over-HTTPS configuration for libcurl
        self.curl_options = {
            CurlOpt.DOH_URL: b"https://1.1.1.1/dns-query"
        }

    async def search_movie(self, query: str, year: int = None) -> list[dict]:
        """
        Search for movies on TMDB.
        """
        url = f"{self.BASE_URL}/search/movie"
        params = {"query": query}
        if year:
            params["year"] = str(year)

        try:
            from datetime import date
            async with AsyncSession(curl_options=self.curl_options) as client:
                resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome")
                resp.raise_for_status()
                results = resp.json().get("results", [])
                
                # Filter out unreleased movies (where release_date is empty or in the future)
                today_str = date.today().isoformat()
                return [
                    m for m in results
                    if m.get("release_date") and m.get("release_date") <= today_str
                ]
        except Exception as e:
            logger.error(f"TMDB movie search failed for '{query}': {e}")
            return []

    async def search_tv(self, query: str, year: int = None) -> list[dict]:
        """
        Search for TV shows on TMDB.
        """
        url = f"{self.BASE_URL}/search/tv"
        params = {"query": query}
        if year:
            params["first_air_date_year"] = str(year)

        try:
            async with AsyncSession(curl_options=self.curl_options) as client:
                resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome")
                resp.raise_for_status()
                return resp.json().get("results", [])
        except Exception as e:
            logger.error(f"TMDB TV search failed for '{query}': {e}")
            return []

    async def get_movie_details(self, movie_id: int) -> dict | None:
        """
        Get full details for a movie, including external IDs.
        """
        url = f"{self.BASE_URL}/movie/{movie_id}"
        params = {"append_to_response": "external_ids"}

        try:
            async with AsyncSession(curl_options=self.curl_options) as client:
                resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome")
                resp.raise_for_status()
                return resp.json()
        except Exception as e:
            logger.error(f"Failed to fetch TMDB movie details for id {movie_id}: {e}")
            return None

    async def get_tv_details(self, tv_id: int) -> dict | None:
        """
        Get full details for a TV show, including external IDs.
        """
        url = f"{self.BASE_URL}/tv/{tv_id}"
        params = {"append_to_response": "external_ids"}

        try:
            async with AsyncSession(curl_options=self.curl_options) as client:
                resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome")
                resp.raise_for_status()
                return resp.json()
        except Exception as e:
            logger.error(f"Failed to fetch TMDB TV details for id {tv_id}: {e}")
            return None

    async def get_popular_movies(self, language: str = "en-US", page: int = 1) -> list[dict]:
        """
        Get popular movies from TMDB whose original language matches the requested language code.
        """
        url = f"{self.BASE_URL}/discover/movie"
        
        # Extract the base language code (e.g., 'hi' from 'hi-IN')
        lang_code = language.split("-")[0] if "-" in language else language
        
        from datetime import date
        today_str = date.today().isoformat()
        
        params = {
            "with_original_language": lang_code,
            "sort_by": "popularity.desc",
            "page": str(page),
            "primary_release_date.lte": today_str
        }

        try:
            async with AsyncSession(curl_options=self.curl_options) as client:
                resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome")
                resp.raise_for_status()
                return resp.json().get("results", [])
        except Exception as e:
            logger.error(f"Failed to fetch popular movies for original language '{lang_code}': {e}")
            return []

    async def discover_movies(self, language: str = "en-US", year: int | None = None, page: int = 1) -> list[dict]:
        """
        Discover movies filterable by original language and/or primary release year.
        If no year is specified, sorts by latest release date.
        """
        url = f"{self.BASE_URL}/discover/movie"
        lang_code = language.split("-")[0] if "-" in language else language
        
        from datetime import date
        today_str = date.today().isoformat()
        
        params = {
            "with_original_language": lang_code,
            "page": str(page),
            "primary_release_date.lte": today_str
        }
        
        if year:
            params["primary_release_year"] = str(year)
            params["sort_by"] = "popularity.desc"
        else:
            params["sort_by"] = "primary_release_date.desc"

        try:
            async with AsyncSession(curl_options=self.curl_options) as client:
                resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome")
                resp.raise_for_status()
                return resp.json().get("results", [])
        except Exception as e:
            logger.error(f"TMDB discover failed for lang '{lang_code}', year '{year}': {e}")
            return []

tmdb_client = TMDBClient()
