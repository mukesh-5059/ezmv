from fastapi import APIRouter, Query, HTTPException
from backend.services.tmdb import tmdb_client
from backend.services.catalog import catalog_service

router = APIRouter()


def format_catalog_movie(row: dict, default_genre: int | None = None) -> dict:
    year = row.get("year")
    release_date = f"{year}-01-01" if year else ""
    genre_ids = [default_genre] if default_genre else []
    return {
        "tmdb_id": row.get("tmdb_id") or (abs(hash(row.get("imdb_id", "0"))) % 100000000),
        "title": row.get("title", ""),
        "original_title": row.get("title", ""),
        "overview": row.get("overview") or "",
        "release_date": release_date,
        "poster_path": row.get("poster_path") or "",
        "backdrop_path": row.get("backdrop_path") or "",
        "vote_average": float(row.get("rating") or 0.0),
        "original_language": "ta",
        "media_type": "movie",
        "genre_ids": genre_ids,
    }


@router.get("/search")
async def search_movies_or_tv(
    query: str = Query(..., description="The title of the movie or show to search for"),
    media_type: str = Query("movie", enum=["movie", "tv"], description="Media type: movie or tv"),
    year: int | None = Query(None, description="Year of release (or first air date for TV)"),
    page: int = Query(1, ge=1, description="Page number to fetch"),
):
    if media_type == "movie":
        local_results = catalog_service.search_movies(query=query, limit=20, offset=(page - 1) * 20)
        if local_results:
            formatted_local = [format_catalog_movie(m) for m in local_results]
            if len(formatted_local) >= 10:
                return {"results": formatted_local}

            # Supplement with TMDB search if local catalog has few results
            tmdb_results = await tmdb_client.search_movie(query=query, year=year, page=page)
            existing_ids = {m["tmdb_id"] for m in formatted_local}
            formatted_tmdb = []
            for item in tmdb_results:
                if item.get("id") not in existing_ids:
                    formatted_tmdb.append({
                        "tmdb_id": item.get("id"),
                        "title": item.get("title"),
                        "original_title": item.get("original_title"),
                        "overview": item.get("overview"),
                        "release_date": item.get("release_date"),
                        "poster_path": item.get("poster_path"),
                        "backdrop_path": item.get("backdrop_path"),
                        "vote_average": item.get("vote_average"),
                        "media_type": "movie",
                        "genre_ids": item.get("genre_ids", []),
                    })
            return {"results": formatted_local + formatted_tmdb}

        results = await tmdb_client.search_movie(query=query, year=year, page=page)
    else:
        results = await tmdb_client.search_tv(query=query, year=year)

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
            "genre_ids": item.get("genre_ids", []),
        })

    return {"results": formatted_results}


@router.get("/popular")
async def get_popular(
    language: str = Query("en-US", description="ISO-639-1 language code to query (e.g. en-US, ta-IN)"),
    page: int = Query(1, ge=1, description="Page number to fetch"),
):
    # If Tamil requested, serve All-Time Most Watched from local catalog.db
    if language.lower().startswith("ta"):
        limit = 20
        offset = (page - 1) * limit
        local_movies = catalog_service.get_lane_movies("top_rated", limit=limit, offset=offset)
        if local_movies:
            return {"results": [format_catalog_movie(m) for m in local_movies]}

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
            "genre_ids": item.get("genre_ids", []),
        })

    return {"results": formatted_results}


@router.get("/discover")
async def discover(
    language: str = Query("ta-IN", description="Language code to query (e.g. ta-IN, en-US)"),
    year: int | None = Query(None, description="Release year to filter by"),
    genre: int | None = Query(None, description="Genre ID to filter by"),
    page: int = Query(1, ge=1, description="Page number to fetch"),
):
    # If Tamil requested, serve from local catalog.db
    if language.lower().startswith("ta"):
        limit = 20
        offset = (page - 1) * limit

        # Genre 35 is Comedy -> serve curated Comedy lane
        if genre == 35:
            local_movies = catalog_service.get_lane_movies("comedy", limit=limit, offset=offset)
            if local_movies:
                return {"results": [format_catalog_movie(m, default_genre=35) for m in local_movies]}
        else:
            # Main discover -> serve New & Trending Tamil (MOVIEMETER)
            local_movies = catalog_service.get_lane_movies("trending", limit=limit, offset=offset)
            if local_movies:
                return {"results": [format_catalog_movie(m) for m in local_movies]}

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
            "genre_ids": item.get("genre_ids", []),
        })

    return {"results": formatted_results}


@router.get("/{media_type}/{tmdb_id}")
async def get_details(
    media_type: str,
    tmdb_id: int,
):
    if media_type not in ["movie", "tv"]:
        raise HTTPException(status_code=400, detail="Invalid media type. Must be 'movie' or 'tv'.")

    # Check local catalog first
    if media_type == "movie":
        local_movie = catalog_service.get_movie_by_tmdb_id(tmdb_id)
        if local_movie:
            year = local_movie.get("year")
            return {
                "tmdb_id": local_movie["tmdb_id"],
                "title": local_movie["title"],
                "imdb_id": local_movie["imdb_id"],
                "overview": local_movie["overview"] or "",
                "release_date": f"{year}-01-01" if year else "",
                "poster_path": local_movie["poster_path"] or "",
                "external_ids": {"imdb_id": local_movie["imdb_id"]},
            }

    if media_type == "movie":
        details = await tmdb_client.get_movie_details(tmdb_id)
    else:
        details = await tmdb_client.get_tv_details(tmdb_id)

    if not details:
        raise HTTPException(status_code=404, detail="Media not found on TMDB.")

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
    }
