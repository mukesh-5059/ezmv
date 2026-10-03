import asyncio
from fastapi import APIRouter, Query, HTTPException
from backend.models import (
    MovieSummary,
    MovieDetails,
    DashboardLane,
    DashboardResponse,
    LaneMoviesResponse,
)
from backend.services.tmdb import tmdb_client
from backend.services.catalog import catalog_service

router = APIRouter()


@router.get("/dashboard", response_model=DashboardResponse)
async def get_dashboard(
    language: str = Query("ta", description="Language code: ta or en"),
):
    safe_lang = language.strip().lower() if isinstance(language, str) else "ta"
    lanes: list[DashboardLane] = []

    if safe_lang.startswith("ta"):
        tamil_configs = [
            ("trending", "New & Trending Tamil"),
            ("box_office", "Record-Breaking Box Office"),
            ("top_rated", "All-Time Most Watched"),
            ("comedy", "Popular Tamil Comedy"),
        ]
        for lane_id, title in tamil_configs:
            raw_items = catalog_service.get_lane_movies(lane_id, limit=20, offset=0)
            items = [MovieSummary.from_catalog(r) for r in raw_items]
            has_more = len(items) == 20
            lanes.append(
                DashboardLane(
                    id=lane_id,
                    title=title,
                    items=items,
                    has_more=has_more,
                    next_page=2 if has_more else None,
                )
            )
    else:
        results = await asyncio.gather(
            tmdb_client.get_popular_movies(language=safe_lang, page=1),
            tmdb_client.get_trending_movies(time_window="week", page=1),
            tmdb_client.discover_movies(language=safe_lang, vote_count_gte=2000, sort_by="vote_average.desc", page=1),
            tmdb_client.discover_movies(language=safe_lang, genre="28,878", vote_count_gte=1000, sort_by="popularity.desc", page=1),
            tmdb_client.discover_movies(language=safe_lang, genre="16", vote_count_gte=500, sort_by="popularity.desc", page=1),
            return_exceptions=True,
        )

        en_configs = [
            ("popular", "Popular Movies"),
            ("trending", "Trending This Week"),
            ("top_rated", "All-Time Fan Favorites"),
            ("action", "Action & Sci-Fi Blockbusters"),
            ("animation", "Top Animation & Family"),
        ]

        for i, (lane_id, title) in enumerate(en_configs):
            res = results[i]
            if isinstance(res, Exception) or not res:
                items = []
            else:
                items = [MovieSummary.from_tmdb(m, media_type="movie") for m in res]
            has_more = len(items) >= 20
            lanes.append(
                DashboardLane(
                    id=lane_id,
                    title=title,
                    items=items,
                    has_more=has_more,
                    next_page=2 if has_more else None,
                )
            )

    return DashboardResponse(language=safe_lang, lanes=lanes)


@router.get("/dashboard/lane", response_model=LaneMoviesResponse)
async def get_dashboard_lane(
    lane_id: str = Query(..., description="The ID of the lane to fetch more items for"),
    language: str = Query("ta", description="Language code: ta or en"),
    page: int = Query(1, ge=1, description="Page number to fetch"),
    limit: int = Query(20, ge=1, le=50, description="Items per page"),
):
    safe_lang = language.strip().lower() if isinstance(language, str) else "ta"
    safe_page = page if isinstance(page, int) and page >= 1 else 1
    safe_limit = limit if isinstance(limit, int) and 1 <= limit <= 50 else 20
    offset = (safe_page - 1) * safe_limit

    if safe_lang.startswith("ta") and lane_id in ["trending", "box_office", "top_rated", "comedy"]:
        raw_items = catalog_service.get_lane_movies(lane_id, limit=safe_limit, offset=offset)
        items = [MovieSummary.from_catalog(r) for r in raw_items]
        has_more = len(items) == safe_limit
        return LaneMoviesResponse(
            id=lane_id,
            page=safe_page,
            has_more=has_more,
            next_page=(safe_page + 1) if has_more else None,
            items=items,
        )

    # English / TMDB fallback
    if lane_id == "popular":
        raw_items = await tmdb_client.get_popular_movies(language=safe_lang, page=safe_page)
    elif lane_id == "trending":
        raw_items = await tmdb_client.get_trending_movies(time_window="week", page=safe_page)
    elif lane_id == "top_rated":
        raw_items = await tmdb_client.discover_movies(
            language=safe_lang, vote_count_gte=2000, sort_by="vote_average.desc", page=safe_page
        )
    elif lane_id == "action":
        raw_items = await tmdb_client.discover_movies(
            language=safe_lang, genre="28,878", vote_count_gte=1000, sort_by="popularity.desc", page=safe_page
        )
    elif lane_id == "animation":
        raw_items = await tmdb_client.discover_movies(
            language=safe_lang, genre="16", vote_count_gte=500, sort_by="popularity.desc", page=safe_page
        )
    else:
        raw_items = await tmdb_client.discover_movies(language=safe_lang, page=safe_page)

    items = [MovieSummary.from_tmdb(m, media_type="movie") for m in raw_items]
    has_more = len(items) >= safe_limit
    return LaneMoviesResponse(
        id=lane_id,
        page=safe_page,
        has_more=has_more,
        next_page=(safe_page + 1) if has_more else None,
        items=items,
    )


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
