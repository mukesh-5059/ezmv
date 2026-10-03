import logging
from datetime import date
from backend.config import settings
from backend.session import get_session
from backend.services.cache_db import get_tmdb_cache, set_tmdb_cache

logger = logging.getLogger(__name__)


EXCLUDED_ADULT_KEYWORD_IDS = "18321,155477,239225,190370,156470,224636,10714,596,207317,227652,298835"


class TMDBClient:
    BASE_URL = "https://api.themoviedb.org/3"

    def __init__(self):
        self.headers = {
            "Authorization": f"Bearer {settings.ReadAccessToken}",
            "accept": "application/json",
        }

    async def get_genres(self, language: str = "en") -> list[dict]:
        cache_key = f"tmdb_genres:{language}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return cached

        url = f"{self.BASE_URL}/genre/movie/list"
        params = {"language": language}
        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome", timeout=20.0)
            resp.raise_for_status()
            genres = resp.json().get("genres", [])
            set_tmdb_cache(cache_key, genres, ttl_seconds=2592000)
            return genres
        except Exception as e:
            logger.error(f"Failed to fetch TMDB genres: {e}")
            return []

    async def get_languages(self) -> list[dict]:
        cache_key = "tmdb_languages"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return cached

        url = f"{self.BASE_URL}/configuration/languages"
        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, impersonate="chrome", timeout=20.0)
            resp.raise_for_status()
            languages = resp.json()
            if isinstance(languages, list):
                set_tmdb_cache(cache_key, languages, ttl_seconds=2592000)
                return languages
            return []
        except Exception as e:
            logger.error(f"Failed to fetch TMDB languages: {e}")
            return []

    async def search_movie(
        self,
        query: str,
        year: int | None = None,
        year_min: int | None = None,
        year_max: int | None = None,
        genre: int | str | None = None,
        language: str | None = None,
        sort_by: str | None = None,
        page: int = 1,
    ) -> list[dict]:
        clean_q = query.strip() if query else ""
        if not clean_q:
            return await self.discover_movies(
                language=language,
                year=year,
                year_min=year_min,
                year_max=year_max,
                genre=genre,
                sort_by=sort_by,
                page=page,
            )

        cache_key = f"search_movie:{clean_q}_{year}_{language}_{page}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return cached

        url = f"{self.BASE_URL}/search/movie"
        params = {
            "query": clean_q,
            "page": str(page),
            "include_adult": "false",
        }
        if year:
            params["primary_release_year"] = str(year)
        if language == "anime":
            pass
        elif language and language != "all":
            params["language"] = language

        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome", timeout=20.0)
            resp.raise_for_status()
            results = resp.json().get("results", [])

            today_str = date.today().isoformat()
            filtered = [
                m for m in results
                if m.get("release_date") and m.get("release_date") <= today_str
            ]
            if language == "anime":
                filtered = [
                    m for m in filtered
                    if m.get("original_language") == "ja" or 16 in m.get("genre_ids", [])
                ]

            if len(clean_q) >= 2 and len(filtered) > 0:
                set_tmdb_cache(cache_key, filtered, ttl_seconds=86400)
            return filtered
        except Exception as e:
            logger.error(f"TMDB movie search failed for '{query}': {e}")
            return []

    async def get_movie_details(self, movie_id: int) -> dict | None:
        cache_key = f"movie_details:{movie_id}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return cached

        url = f"{self.BASE_URL}/movie/{movie_id}"
        params = {"append_to_response": "external_ids,credits"}

        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome", timeout=20.0)
            resp.raise_for_status()
            details = resp.json()

            set_tmdb_cache(cache_key, details, ttl_seconds=1296000)
            return details
        except Exception as e:
            logger.error(f"Failed to fetch TMDB movie details for id {movie_id}: {e}")
            return None

    async def get_tv_details(self, tv_id: int) -> dict | None:
        cache_key = f"tv_details:{tv_id}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return cached

        url = f"{self.BASE_URL}/tv/{tv_id}"
        params = {"append_to_response": "external_ids,credits"}

        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome", timeout=20.0)
            resp.raise_for_status()
            details = resp.json()

            set_tmdb_cache(cache_key, details, ttl_seconds=1296000)
            return details
        except Exception as e:
            logger.error(f"Failed to fetch TMDB TV details for id {tv_id}: {e}")
            return None

    async def get_tv_season(self, tv_id: int, season_number: int) -> dict | None:
        cache_key = f"tv_season:{tv_id}:{season_number}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return cached

        url = f"{self.BASE_URL}/tv/{tv_id}/season/{season_number}"

        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, impersonate="chrome", timeout=20.0)
            resp.raise_for_status()
            details = resp.json()

            set_tmdb_cache(cache_key, details, ttl_seconds=1296000)
            return details
        except Exception as e:
            logger.error(f"Failed to fetch TMDB TV season {season_number} for id {tv_id}: {e}")
            return None

    async def get_popular_movies(self, language: str = "en-US", page: int = 1) -> list[dict]:
        return await self.discover_movies(language=language, page=page, sort_by="popularity.desc")

    async def get_trending_movies(self, time_window: str = "week", page: int = 1) -> list[dict]:
        cache_key = f"trending:{time_window}_{page}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return cached

        url = f"{self.BASE_URL}/trending/movie/{time_window}"
        params = {"page": str(page)}

        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome", timeout=20.0)
            resp.raise_for_status()
            results = resp.json().get("results", [])

            set_tmdb_cache(cache_key, results, ttl_seconds=86400)
            return results
        except Exception as e:
            logger.error(f"TMDB trending failed for window '{time_window}': {e}")
            return []

    async def discover_movies(
        self,
        language: str | None = None,
        year: int | None = None,
        year_min: int | None = None,
        year_max: int | None = None,
        genre: int | str | None = None,
        page: int = 1,
        sort_by: str | None = None,
        vote_count_gte: int | None = None,
    ) -> list[dict]:
        cache_key = f"discover:{language}_{year}_{year_min}_{year_max}_{genre}_{sort_by}_{vote_count_gte}_{page}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return cached

        url = f"{self.BASE_URL}/discover/movie"
        today_str = date.today().isoformat()

        params = {
            "page": str(page),
            "primary_release_date.lte": today_str,
            "include_adult": "false",
            "without_keywords": EXCLUDED_ADULT_KEYWORD_IDS,
        }

        if language == "anime":
            params["with_original_language"] = "ja"
            if genre and str(genre).lower() != "all" and str(genre) != "0":
                if "16" not in str(genre).split(","):
                    params["with_genres"] = f"16,{genre}"
                else:
                    params["with_genres"] = str(genre)
            else:
                params["with_genres"] = "16"
        elif language and language != "all":
            lang_code = language.split("-")[0] if "-" in language else language
            params["with_original_language"] = lang_code
            if genre and str(genre).lower() != "all" and str(genre) != "0":
                params["with_genres"] = str(genre)
        elif genre and str(genre).lower() != "all" and str(genre) != "0":
            params["with_genres"] = str(genre)

        if year:
            params["primary_release_year"] = str(year)
        else:
            if year_min:
                params["primary_release_date.gte"] = f"{year_min}-01-01"
            if year_max:
                params["primary_release_date.lte"] = min(today_str, f"{year_max}-12-31")

        if sort_by:
            params["sort_by"] = sort_by
        else:
            params["sort_by"] = "popularity.desc"

        if vote_count_gte is not None:
            params["vote_count.gte"] = str(vote_count_gte)
        elif params["sort_by"] == "vote_average.desc":
            params["vote_count.gte"] = "100"
        elif params["sort_by"] == "popularity.desc":
            params["vote_count.gte"] = "20"

        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome", timeout=20.0)
            resp.raise_for_status()
            results = resp.json().get("results", [])

            set_tmdb_cache(cache_key, results, ttl_seconds=86400)
            return results
        except Exception as e:
            logger.error(f"TMDB discover failed for lang '{language}', genre '{genre}': {e}")
            return []

    async def find_movie_by_imdb_id(self, imdb_id: str) -> dict | None:
        cache_key = f"find_imdb:{imdb_id}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return cached

        url = f"{self.BASE_URL}/find/{imdb_id}"
        params = {"external_source": "imdb_id"}
        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome", timeout=20.0)
            resp.raise_for_status()
            data = resp.json()
            movie_results = data.get("movie_results", [])
            if movie_results:
                res = movie_results[0]
                set_tmdb_cache(cache_key, res, ttl_seconds=1296000)
                return res
            tv_results = data.get("tv_results", [])
            if tv_results:
                res = tv_results[0]
                set_tmdb_cache(cache_key, res, ttl_seconds=1296000)
                return res
            return None
        except Exception as e:
            logger.error(f"Failed to find TMDB item for IMDb ID '{imdb_id}': {e}")
            return None


tmdb_client = TMDBClient()
