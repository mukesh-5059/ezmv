from fastapi import APIRouter, Query
from fastapi.responses import StreamingResponse
from backend.scrappers.manager import scraper_manager

router = APIRouter()

@router.get("/")
async def get_streaming_links(
    tmdb_id: int = Query(..., description="TMDb ID of the movie/show"),
    media_type: str = Query("movie", description="Media type: movie or tv"),
    season: int | None = Query(None, description="Season number (for tv)"),
    episode: int | None = Query(None, description="Episode number (for tv)"),
    bypass_cache: bool = Query(False, description="Bypass manager cache and force re-scrape"),
):
    return StreamingResponse(
        scraper_manager.stream_events(
            tmdb_id=tmdb_id,
            media_type=media_type,
            season=season,
            episode=episode,
            bypass_cache=bypass_cache,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive"
        }
    )

