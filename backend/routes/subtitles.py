from fastapi import APIRouter, Query
from backend.models import SubtitleResponse
from backend.services.subtitles import subtitles_service

router = APIRouter()

@router.get("/", response_model=SubtitleResponse)
async def get_subtitles(
    tmdb_id: int = Query(..., description="TMDb ID of the movie/show"),
    media_type: str = Query("movie", description="Media type: movie or tv"),
    season: int | None = Query(None, description="Season number for tv series"),
    episode: int | None = Query(None, description="Episode number for tv series"),
    language: str | None = Query(None, description="Optional language filter (e.g. 'en', 'ta')"),
):
    return await subtitles_service.get_subtitles(
        tmdb_id=tmdb_id,
        media_type=media_type,
        season=season,
        episode=episode,
        language=language,
    )
