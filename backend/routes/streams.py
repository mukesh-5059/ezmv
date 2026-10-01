from fastapi import APIRouter, Query, HTTPException, Request
from fastapi.responses import StreamingResponse
from backend.models import StreamResponse
from backend.scrappers.manager import scraper_manager

router = APIRouter()

@router.get("/", response_model=StreamResponse, responses={200: {"description": "Streaming links or SSE stream"}})
async def get_streaming_links(
    request: Request,
    tmdb_id: int = Query(..., description="TMDb ID of the movie or TV show"),
    media_type: str = Query("movie", enum=["movie", "tv"], description="Media type: movie or tv"),
    season: int | None = Query(None, description="Season number (required for TV shows)"),
    episode: int | None = Query(None, description="Episode number (required for TV shows)"),
    provider: str | None = Query(None, description="Optional specific provider name (e.g. Isaimini, VidSrc)"),
    bypass_cache: bool = Query(False, description="Bypass manager cache and force re-scrape"),
    format: str | None = Query(None, description="Response format ('sse' for server-sent events)")
):
    safe_season = season if isinstance(season, int) else None
    safe_episode = episode if isinstance(episode, int) else None

    if media_type == "tv" and (safe_season is None or safe_episode is None):
        raise HTTPException(status_code=400, detail="Season and Episode are required for TV shows.")

    accept_header = request.headers.get("accept", "")
    if format == "sse" or "text/event-stream" in accept_header:
        return StreamingResponse(
            scraper_manager.stream_events(
                tmdb_id=tmdb_id,
                media_type=media_type,
                season=safe_season,
                episode=safe_episode,
                provider=provider,
                bypass_cache=bypass_cache
            ),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive"
            }
        )

    result = await scraper_manager.resolve_streams(
        tmdb_id=tmdb_id,
        media_type=media_type,
        season=safe_season,
        episode=safe_episode,
        provider=provider,
        bypass_cache=bypass_cache
    )
    if not result:
        raise HTTPException(status_code=404, detail="Media not found on TMDB.")

    return result

