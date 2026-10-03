import asyncio
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

    async def get_person_details(self, person_id: int) -> dict | None:
        cache_key = f"person_details:{person_id}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return cached

        url = f"{self.BASE_URL}/person/{person_id}"
        params = {"append_to_response": "combined_credits,external_ids"}
        try:
            client = get_session()
            resp = await client.get(url, headers=self.headers, params=params, impersonate="chrome", timeout=20.0)
            resp.raise_for_status()
            data = resp.json()
            set_tmdb_cache(cache_key, data, ttl_seconds=604800)
            return data
        except Exception as e:
            logger.error(f"Failed to fetch TMDB person details for id {person_id}: {e}")
            return None

    async def get_person_filmography(self, person_id: int) -> dict | None:
        data = await self.get_person_details(person_id)
        if not data:
            return None

        combined_credits = data.get("combined_credits", {})
        cast_items = combined_credits.get("cast", [])

        seen_ids = set()
        valid_items = []
        today_str = date.today().isoformat()

        for item in cast_items:
            m_id = item.get("id")
            media_type = item.get("media_type") or "movie"
            if not m_id or (m_id, media_type) in seen_ids:
                continue
            seen_ids.add((m_id, media_type))
            if not item.get("poster_path"):
                continue
            valid_items.append(item)

        def get_popularity_score(x):
            pop = float(x.get("popularity") or 0.0)
            votes = int(x.get("vote_count") or 0)
            avg = float(x.get("vote_average") or 0.0)
            order = int(x.get("order") if x.get("order") is not None else 10)
            billing_multiplier = 1.3 if order < 4 else 1.0
            return ((pop * 2.5) + (votes * (avg / 5.0))) * billing_multiplier

        popular_sorted = sorted(valid_items, key=get_popularity_score, reverse=True)

        def get_date(x):
            return x.get("release_date") or x.get("first_air_date") or ""

        recent_items = [
            x for x in valid_items
            if get_date(x) and get_date(x) <= today_str
        ]
        recent_sorted = sorted(recent_items, key=get_date, reverse=True)

        return {
            "id": data.get("id", person_id),
            "name": data.get("name", ""),
            "biography": data.get("biography", ""),
            "profile_path": data.get("profile_path"),
            "known_for_department": data.get("known_for_department"),
            "birthday": data.get("birthday"),
            "place_of_birth": data.get("place_of_birth"),
            "popular": popular_sorted[:30],
            "recent": recent_sorted[:30],
        }

    async def get_curated_actors(self, language: str = "ta") -> list[dict]:
        cache_key = f"curated_actors:{language}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            return cached

        curated_ids = [
            (91555, "Rajinikanth"),
            (93193, "Kamal Haasan"),
            (91547, "Vijay"),
            (148360, "Ajith Kumar"),
            (85720, "Suriya"),
            (93191, "Vikram"),
            (550165, "Dhanush"),
            (1123766, "Vijay Sethupathi"),
            (587982, "Sivakarthikeyan"),
            (123066, "Karthi"),
            (222760, "Silambarasan"),
            (1072750, "Fahadh Faasil"),
            (559892, "Vishal"),
            (292250, "S. J. Suryah"),
            (91548, "Nayanthara"),
            (116925, "Trisha Krishnan"),
            (225312, "Samantha Ruth Prabhu"),
            (1295762, "Keerthy Suresh"),
            (91549, "Vadivelu"),
            (85523, "Vivek"),
            (141076, "Santhanam"),
            (1540764, "Yogi Babu"),
            (544897, "Soori"),
        ]

        async def fetch_actor_info(p_id: int, fallback_name: str):
            details = await self.get_person_details(p_id)
            if details:
                return {
                    "id": details.get("id", p_id),
                    "name": details.get("name") or fallback_name,
                    "profile_path": details.get("profile_path"),
                    "known_for_department": details.get("known_for_department", "Acting"),
                }
            return {
                "id": p_id,
                "name": fallback_name,
                "profile_path": None,
                "known_for_department": "Acting",
            }

        actors = await asyncio.gather(
            *[fetch_actor_info(p_id, name) for p_id, name in curated_ids],
            return_exceptions=False,
        )

        valid_actors = [a for a in actors if isinstance(a, dict)]
        set_tmdb_cache(cache_key, valid_actors, ttl_seconds=604800)
        return valid_actors


tmdb_client = TMDBClient()
