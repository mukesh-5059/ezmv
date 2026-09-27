from fastapi import APIRouter, Query, HTTPException
from backend.models import MovieSummary, MovieDetails
from backend.services.tmdb import tmdb_client
from backend.services.catalog import catalog_service

router = APIRouter()


@router.get("/search")
async def search_movies_or_tv(
    query: str = Query(..., description="The title of the movie or show to search for"),
    media_type: str = Query("movie", enum=["movie", "tv"], description="Media type: movie or tv"),
    year: int | None = Query(None, description="Year of release (or first air date for TV)"),
    page: int = Query(1, ge=1, description="Page number to fetch"),
):
    if media_type == "movie":
        results = await catalog_service.search_catalog_with_fallback(query=query, year=year, page=page)
    else:
        raw_tv = await tmdb_client.search_tv(query=query, year=year)
        results = [MovieSummary.from_tmdb(item, media_type="tv") for item in raw_tv]
    return {"results": results}


@router.get("/popular")
async def get_popular(
    language: str = Query("en-US", description="ISO-639-1 language code to query (e.g. en-US, ta-IN)"),
    page: int = Query(1, ge=1, description="Page number to fetch"),
):
    safe_page = page if isinstance(page, int) else 1
    if isinstance(language, str) and language.lower().startswith("ta"):
        return {"results": catalog_service.get_category_movies("popular", page=safe_page)}
    
    raw_popular = await tmdb_client.get_popular_movies(language=language, page=safe_page)
    return {"results": [MovieSummary.from_tmdb(item, media_type="movie") for item in raw_popular]}


@router.get("/discover")
async def discover(
    language: str = Query("ta-IN", description="Language code to query (e.g. ta-IN, en-US)"),
    year: int | None = Query(None, description="Release year to filter by"),
    genre: int | None = Query(None, description="Genre ID to filter by"),
    category: str | None = Query(None, description="Category filter: latest, popular, box_office, comedy"),
    page: int = Query(1, ge=1, description="Page number to fetch"),
):
    safe_page = page if isinstance(page, int) else 1
    safe_year = year if isinstance(year, int) else None
    safe_genre = genre if isinstance(genre, int) else None
    safe_category = category if isinstance(category, str) else None

    if isinstance(language, str) and language.lower().startswith("ta"):
        local = catalog_service.get_tamil_category_movies(
            category=safe_category, genre=safe_genre, year=safe_year, page=safe_page
        )
        if local is not None:
            return {"results": local}

    raw_discovered = await tmdb_client.discover_movies(
        language=language, year=safe_year, genre=safe_genre, page=safe_page
    )
    return {"results": [MovieSummary.from_tmdb(item, media_type="movie") for item in raw_discovered]}


@router.get("/{media_type}/{tmdb_id}", response_model=MovieDetails)
async def get_details(
    media_type: str,
    tmdb_id: int,
):
    if media_type not in ["movie", "tv"]:
        raise HTTPException(status_code=400, detail="Invalid media type. Must be 'movie' or 'tv'.")

    details = await (tmdb_client.get_movie_details(tmdb_id) if media_type == "movie" else tmdb_client.get_tv_details(tmdb_id))
    if not details:
        raise HTTPException(status_code=404, detail="Media not found on TMDB.")

    return MovieDetails.from_tmdb(details, media_type=media_type)
