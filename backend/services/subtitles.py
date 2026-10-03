import logging
from backend.session import get_session
from backend.services.tmdb import tmdb_client
from backend.services.cache_db import get_tmdb_cache, set_tmdb_cache
from backend.models import SubtitleTrack, SubtitleResponse

logger = logging.getLogger(__name__)

LANG_MAP = {
    "eng": ("English", "en"),
    "en": ("English", "en"),
    "tam": ("Tamil", "ta"),
    "ta": ("Tamil", "ta"),
    "hin": ("Hindi", "hi"),
    "hi": ("Hindi", "hi"),
    "tel": ("Telugu", "te"),
    "te": ("Telugu", "te"),
    "mal": ("Malayalam", "ml"),
    "ml": ("Malayalam", "ml"),
    "kan": ("Kannada", "kn"),
    "kn": ("Kannada", "kn"),
    "spa": ("Spanish", "es"),
    "es": ("Spanish", "es"),
    "fre": ("French", "fr"),
    "fra": ("French", "fr"),
    "fr": ("French", "fr"),
    "ger": ("German", "de"),
    "deu": ("German", "de"),
    "de": ("German", "de"),
    "ita": ("Italian", "it"),
    "it": ("Italian", "it"),
    "por": ("Portuguese", "pt"),
    "pob": ("Portuguese (BR)", "pt-br"),
    "pt": ("Portuguese", "pt"),
    "rus": ("Russian", "ru"),
    "ru": ("Russian", "ru"),
    "zho": ("Chinese", "zh"),
    "chi": ("Chinese", "zh"),
    "zh": ("Chinese", "zh"),
    "jpn": ("Japanese", "ja"),
    "ja": ("Japanese", "ja"),
    "kor": ("Korean", "ko"),
    "ko": ("Korean", "ko"),
    "ara": ("Arabic", "ar"),
    "ar": ("Arabic", "ar"),
}


class SubtitlesService:
    BASE_URL = "https://opensubtitles-v3.strem.io/subtitles"

    async def _get_imdb_id(self, tmdb_id: int) -> str | None:
        details = await tmdb_client.get_movie_details(tmdb_id)
        if details:
            ext = details.get("external_ids") or {}
            return details.get("imdb_id") or ext.get("imdb_id")
        return None

    async def get_subtitles(
        self,
        tmdb_id: int,
        language: str | None = None,
    ) -> SubtitleResponse:
        cache_key = f"subtitles:{tmdb_id}"
        cached = get_tmdb_cache(cache_key)
        if cached is not None:
            cached_response = SubtitleResponse.model_validate(cached)
            if language:
                lang_lower = language.lower()
                filtered = [
                    s for s in cached_response.subtitles
                    if s.code.lower() == lang_lower or s.language.lower() == lang_lower
                ]
                return SubtitleResponse(
                    tmdb_id=cached_response.tmdb_id,
                    imdb_id=cached_response.imdb_id,
                    media_type="movie",
                    subtitles=filtered,
                )
            return cached_response

        imdb_id = await self._get_imdb_id(tmdb_id)
        if not imdb_id:
            logger.warning(f"[Subtitles] No IMDb ID found for TMDb {tmdb_id}")
            return SubtitleResponse(
                tmdb_id=tmdb_id,
                imdb_id=None,
                media_type="movie",
                subtitles=[],
            )

        url = f"{self.BASE_URL}/movie/{imdb_id}.json"
        raw_tracks: list[SubtitleTrack] = []

        try:
            session = get_session()
            resp = await session.get(url, timeout=6.0)
            if resp.status_code == 200:
                data = resp.json()
                for sub in data.get("subtitles", []):
                    raw_lang = (sub.get("lang") or "").lower()
                    lang_name, lang_code = LANG_MAP.get(raw_lang, (raw_lang.title(), raw_lang))
                    sub_url = sub.get("url")
                    if not sub_url:
                        continue

                    raw_tracks.append(
                        SubtitleTrack(
                            id=str(sub.get("id") or ""),
                            language=lang_name,
                            code=lang_code,
                            url=sub_url,
                            format="vtt",
                            release=sub.get("movieReleaseName") or sub.get("subtitleFileName"),
                        )
                    )
        except Exception as e:
            logger.warning(f"[Subtitles] Failed fetching subtitles for {imdb_id}: {e}")

        # Sort: English subtitles first, then others by language name
        raw_tracks.sort(key=lambda x: (0 if x.code == "en" else 1, x.language))

        full_response = SubtitleResponse(
            tmdb_id=tmdb_id,
            imdb_id=imdb_id,
            media_type="movie",
            subtitles=raw_tracks,
        )
        set_tmdb_cache(cache_key, full_response.model_dump(), ttl_seconds=86400)

        if language:
            lang_lower = language.lower()
            filtered_tracks = [
                s for s in raw_tracks
                if s.code.lower() == lang_lower or s.language.lower() == lang_lower
            ]
            return SubtitleResponse(
                tmdb_id=tmdb_id,
                imdb_id=imdb_id,
                media_type="movie",
                subtitles=filtered_tracks,
            )

        return full_response


subtitles_service = SubtitlesService()
