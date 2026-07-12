from fastapi import APIRouter, Query, HTTPException
from app.services.tmdb import tmdb_client
from app.scrapers.manager import scraper_manager
import logging

logger = logging.getLogger(__name__)
router = APIRouter()

@router.get("/")
async def get_streaming_links(
    tmdb_id: int = Query(..., description="TMDb ID of the movie or TV show"),
    media_type: str = Query("movie", enum=["movie", "tv"], description="Media type: movie or tv"),
    season: int | None = Query(None, description="Season number (required for TV shows)"),
    episode: int | None = Query(None, description="Episode number (required for TV shows)"),
    bypass_cache: bool = Query(False, description="Bypass manager cache and force re-scrape")
):
    """
    Search and return streaming links for a given movie or TV show.
    """
    # 1. Fetch metadata & IMDb ID from TMDB
    if media_type == "movie":
        details = await tmdb_client.get_movie_details(tmdb_id)
        if not details:
            raise HTTPException(status_code=404, detail="Movie not found on TMDB.")
        
        title = details.get("title")
        release_date = details.get("release_date", "")
        year = int(release_date.split("-")[0]) if release_date else 0
        imdb_id = details.get("imdb_id")
        
    else:
        # TV Show
        if season is None or episode is None:
            raise HTTPException(status_code=400, detail="Season and Episode are required for TV shows.")
            
        details = await tmdb_client.get_tv_details(tmdb_id)
        if not details:
            raise HTTPException(status_code=404, detail="TV Show not found on TMDB.")
            
        title = details.get("name")
        first_air_date = details.get("first_air_date", "")
        year = int(first_air_date.split("-")[0]) if first_air_date else 0
        
        # Get external ids for TV show
        external_ids = details.get("external_ids", {})
        imdb_id = external_ids.get("imdb_id")

    # 2. Invoke Scraper Manager to get stream links
    try:
        links = await scraper_manager.get_streams(
            title=title,
            year=year,
            media_type=media_type,
            tmdb_id=tmdb_id,
            imdb_id=imdb_id,
            season=season,
            episode=episode,
            bypass_cache=bypass_cache
        )
    except Exception as e:
        logger.error(f"Error executing scrapers: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal scraper failure occurred.")

    cache_key = f"{tmdb_id}_{season}_{episode}"
    remaining_ttl = scraper_manager._stream_cache.get_remaining_ttl(cache_key)

    return {
        "title": title,
        "year": year,
        "media_type": media_type,
        "tmdb_id": tmdb_id,
        "imdb_id": imdb_id,
        "season": season,
        "episode": episode,
        "cache_expires_in": remaining_ttl,
        "streams": links
    }
