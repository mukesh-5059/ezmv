from fastapi import APIRouter, Query, HTTPException
from backend.models import SubtitleResponse
from backend.services.subtitles import subtitles_service

router = APIRouter()

@router.get("/", response_model=SubtitleResponse)
async def get_subtitles(
    tmdb_id: int = Query(..., description="TMDb ID of the movie or TV show"),
    media_type: str = Query("movie", enum=["movie", "tv"], description="Media type: movie or tv"),
    season: int | None = Query(None, description="Season number (required for TV shows)"),
    episode: int | None = Query(None, description="Episode number (required for TV shows)"),
    language: str | None = Query(None, description="Optional language filter (e.g. 'en', 'ta')")
):
    safe_season = season if isinstance(season, int) else None
    safe_episode = episode if isinstance(episode, int) else None

    if media_type == "tv" and (safe_season is None or safe_episode is None):
        raise HTTPException(status_code=400, detail="Season and Episode are required for TV shows.")

    return await subtitles_service.get_subtitles(
        tmdb_id=tmdb_id,
        media_type=media_type,
        season=safe_season,
        episode=safe_episode,
        language=language
    )
