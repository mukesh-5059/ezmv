from fastapi import APIRouter, Query
from backend.models import SubtitleResponse
from backend.services.subtitles import subtitles_service

router = APIRouter()

@router.get("/", response_model=SubtitleResponse)
async def get_subtitles(
    tmdb_id: int = Query(..., description="TMDb ID of the movie"),
    language: str | None = Query(None, description="Optional language filter (e.g. 'en', 'ta')")
):
    return await subtitles_service.get_subtitles(
        tmdb_id=tmdb_id,
        language=language
    )
