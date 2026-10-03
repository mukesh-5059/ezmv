import asyncio
from datetime import datetime
from fastapi import APIRouter, Query, HTTPException
from backend.models import (
    MovieSummary,
    MovieDetails,
    DashboardLane,
    DashboardResponse,
    LaneMoviesResponse,
    FilterOption,
    FiltersResponse,
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


@router.get("/filters", response_model=FiltersResponse)
async def get_filters():
    raw_genres = await tmdb_client.get_genres()
    genres = [FilterOption(id=None, label="All Genres")] + [
        FilterOption(id=g.get("id"), label=g.get("name", "")) for g in raw_genres if g.get("id")
    ]

    raw_langs = await tmdb_client.get_languages()
    lang_map = {l.get("iso_639_1"): l.get("english_name", l.get("name", "")) for l in raw_langs if l.get("iso_639_1")}
    priority_codes = ["ta", "en", "ml", "te", "hi", "kn", "ko", "ja"]

    languages = [FilterOption(id="all", label="All Languages")]
    for code in priority_codes:
        if code in lang_map:
            languages.append(FilterOption(id=code, label=lang_map[code]))

    current_year = datetime.now().year
    years = [
        FilterOption(id="all", label="All Years"),
        FilterOption(id=str(current_year), label=str(current_year), year_min=current_year, year_max=current_year),
        FilterOption(id=str(current_year - 1), label=str(current_year - 1), year_min=current_year - 1, year_max=current_year - 1),
        FilterOption(id=str(current_year - 2), label=str(current_year - 2), year_min=current_year - 2, year_max=current_year - 2),
        FilterOption(id=str(current_year - 3), label=str(current_year - 3), year_min=current_year - 3, year_max=current_year - 3),
        FilterOption(id="2020s", label="2020s (2020–2029)", year_min=2020, year_max=2029),
        FilterOption(id="2010s", label="2010s (2010–2019)", year_min=2010, year_max=2019),
        FilterOption(id="2000s", label="2000s (2000–2009)", year_min=2000, year_max=2009),
        FilterOption(id="1990s", label="90s (1990–1999)", year_min=1990, year_max=1999),
        FilterOption(id="1980s", label="80s (1980–1989)", year_min=1980, year_max=1989),
        FilterOption(id="classic", label="Classic (<1980)", year_min=1900, year_max=1979),
    ]

    sort_options = [
        FilterOption(id="popularity.desc", label="Most Popular"),
        FilterOption(id="primary_release_date.desc", label="Newest Release"),
        FilterOption(id="primary_release_date.asc", label="Oldest First"),
        FilterOption(id="vote_average.desc", label="Top Rated"),
        FilterOption(id="revenue.desc", label="Box Office Hits"),
        FilterOption(id="title.asc", label="A - Z"),
    ]

    return FiltersResponse(
        languages=languages,
        genres=genres,
        years=years,
        sort_options=sort_options,
    )


@router.get("/search")
@router.get("/discover")
async def search_or_discover(
    query: str | None = Query(None, description="The title of the movie to search for (optional)"),
    language: str | None = Query(None, description="Language code to filter by"),
    year: int | None = Query(None, description="Release year to filter by"),
    year_min: int | None = Query(None, description="Minimum release year"),
    year_max: int | None = Query(None, description="Maximum release year"),
    genre: int | str | None = Query(None, description="Genre ID to filter by"),
    sort_by: str | None = Query("popularity.desc", description="Sort order"),
    page: int = Query(1, ge=1, description="Page number to fetch"),
):
    safe_query = query.strip() if isinstance(query, str) and query.strip() else None
    safe_lang = language.strip() if isinstance(language, str) and language.strip() and language != "all" else None
    safe_year = year if isinstance(year, int) else None
    safe_year_min = year_min if isinstance(year_min, int) else None
    safe_year_max = year_max if isinstance(year_max, int) else None
    safe_genre = genre if isinstance(genre, (int, str)) and str(genre).lower() != "all" and str(genre) != "0" else None
    safe_sort_by = sort_by if isinstance(sort_by, str) and sort_by.strip() else "popularity.desc"
    safe_page = page if isinstance(page, int) and page >= 1 else 1

    if safe_query:
        results = await tmdb_client.search_movie(
            query=safe_query,
            year=safe_year,
            language=safe_lang,
            page=safe_page,
        )
    else:
        results = await tmdb_client.discover_movies(
            language=safe_lang,
            year=safe_year,
            year_min=safe_year_min,
            year_max=safe_year_max,
            genre=safe_genre,
            sort_by=safe_sort_by,
            page=safe_page,
        )
    return {"results": [MovieSummary.from_tmdb(item, media_type="movie") for item in results]}


@router.get("/{tmdb_id}", response_model=MovieDetails)
@router.get("/{media_type}/{tmdb_id}", response_model=MovieDetails)
async def get_details(
    tmdb_id: int,
    media_type: str = "movie",
):
    details = await tmdb_client.get_movie_details(tmdb_id)
    if not details:
        raise HTTPException(status_code=404, detail="Movie not found on TMDB.")

    return MovieDetails.from_tmdb(details, media_type="movie")
