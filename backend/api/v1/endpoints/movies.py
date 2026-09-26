from fastapi import APIRouter, Query, HTTPException
from app.services.tmdb import tmdb_client

router = APIRouter()

@router.get("/search")
async def search_movies_or_tv(
    query: str = Query(..., description="The title of the movie or show to search for"),
    media_type: str = Query("movie", enum=["movie", "tv"], description="Media type: movie or tv"),
    year: int | None = Query(None, description="Year of release (or first air date for TV)"),
    page: int = Query(1, ge=1, description="Page number to fetch")
):
    """
    Search for movies or TV shows on TMDB.
    """
    if media_type == "movie":
        results = await tmdb_client.search_movie(query=query, year=year, page=page)
    else:
        results = await tmdb_client.search_tv(query=query, year=year)
    
    # Format and return simplified representation
    formatted_results = []
    for item in results:
        formatted_results.append({
            "tmdb_id": item.get("id"),
            "title": item.get("title") if media_type == "movie" else item.get("name"),
            "original_title": item.get("original_title") if media_type == "movie" else item.get("original_name"),
            "overview": item.get("overview"),
            "release_date": item.get("release_date") if media_type == "movie" else item.get("first_air_date"),
            "poster_path": item.get("poster_path"),
            "backdrop_path": item.get("backdrop_path"),
            "vote_average": item.get("vote_average"),
            "media_type": media_type,
            "genre_ids": item.get("genre_ids", [])
        })
        
    return {"results": formatted_results}

@router.get("/popular")
async def get_popular(
    language: str = Query("en-US", description="ISO-639-1 language code to query (e.g. en-US, hi-IN, es-ES)"),
    page: int = Query(1, ge=1, description="Page number to fetch")
):
    """
    Get popular movies from TMDB, filterable by language.
    """
    results = await tmdb_client.get_popular_movies(language=language, page=page)
    
    formatted_results = []
    for item in results:
        formatted_results.append({
            "tmdb_id": item.get("id"),
            "title": item.get("title"),
            "original_title": item.get("original_title"),
            "overview": item.get("overview"),
            "release_date": item.get("release_date"),
            "poster_path": item.get("poster_path"),
            "backdrop_path": item.get("backdrop_path"),
            "vote_average": item.get("vote_average"),
            "original_language": item.get("original_language"),
            "media_type": "movie",
            "genre_ids": item.get("genre_ids", [])
        })
        
    return {"results": formatted_results}

@router.get("/discover")
async def discover(
    language: str = Query("ta-IN", description="Language code to query (e.g. ta-IN, hi-IN, en-US)"),
    year: int | None = Query(None, description="Release year to filter by"),
    genre: int | None = Query(None, description="Genre ID to filter by"),
    page: int = Query(1, ge=1, description="Page number to fetch")
):
    """
    Discover movies from TMDB, filterable by original language, release year, and genre.
    Returns latest movies if year is not provided.
    """
    results = await tmdb_client.discover_movies(language=language, year=year, genre=genre, page=page)
    
    formatted_results = []
    for item in results:
        formatted_results.append({
            "tmdb_id": item.get("id"),
            "title": item.get("title"),
            "original_title": item.get("original_title"),
            "overview": item.get("overview"),
            "release_date": item.get("release_date"),
            "poster_path": item.get("poster_path"),
            "backdrop_path": item.get("backdrop_path"),
            "vote_average": item.get("vote_average"),
            "original_language": item.get("original_language"),
            "media_type": "movie",
            "genre_ids": item.get("genre_ids", [])
        })
        
    return {"results": formatted_results}

@router.get("/{media_type}/{tmdb_id}")
async def get_details(
    media_type: str,
    tmdb_id: int
):
    """
    Retrieve full details (including external IDs for IMDb resolution) of a movie or TV show.
    """
    if media_type not in ["movie", "tv"]:
        raise HTTPException(status_code=400, detail="Invalid media type. Must be 'movie' or 'tv'.")
        
    if media_type == "movie":
        details = await tmdb_client.get_movie_details(tmdb_id)
    else:
        details = await tmdb_client.get_tv_details(tmdb_id)
        
    if not details:
        raise HTTPException(status_code=404, detail="Media not found on TMDB.")
        
    # Extract IMDb ID
    external_ids = details.get("external_ids", {})
    imdb_id = details.get("imdb_id") or external_ids.get("imdb_id")
    
    return {
        "tmdb_id": details.get("id"),
        "title": details.get("title") if media_type == "movie" else details.get("name"),
        "imdb_id": imdb_id,
        "overview": details.get("overview"),
        "release_date": details.get("release_date") if media_type == "movie" else details.get("first_air_date"),
        "poster_path": details.get("poster_path"),
        "external_ids": external_ids,
        "raw_details": details
    }
