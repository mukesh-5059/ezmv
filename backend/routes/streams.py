from fastapi import APIRouter, Query
from fastapi.responses import StreamingResponse
from backend.scrappers.manager import scraper_manager

router = APIRouter()

@router.get("/")
async def get_streaming_links(
    tmdb_id: int = Query(..., description="TMDb ID of the movie"),
    bypass_cache: bool = Query(False, description="Bypass manager cache and force re-scrape"),
):
    return StreamingResponse(
        scraper_manager.stream_events(
            tmdb_id=tmdb_id,
            bypass_cache=bypass_cache,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive"
        }
    )

