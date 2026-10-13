import asyncio
from datetime import datetime
from pathlib import Path
from fastapi import APIRouter, Query, HTTPException
from backend.models import (
    MovieSummary,
    MovieDetails,
    DashboardLane,
    DashboardResponse,
    LaneMoviesResponse,
    PaginatedMovieResponse,
    FilterOption,
    FiltersResponse,
    TraktListSummary,
    TvSeason,
    TvEpisode,
    ActorSummary,
    PersonDetailsResponse,
)
from backend.services.tmdb import tmdb_client
from backend.services.catalog import catalog_service
from backend.services.trakt import trakt_client

router = APIRouter()


def _load_lanes_en_config() -> list[dict]:
    for p in [Path("config/lanes_en.json"), Path("backend/data/lanes_en.json")]:
        if p.exists():
            try:
                import json
                with open(p, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
    return [
        {"id": "trending", "title": "Trending Right Now", "type": "trakt_trending"},
        {"id": "watched_weekly", "title": "Most Watched This Week", "type": "trakt_watched", "period": "weekly"},
        {"id": "box_office", "title": "Current Box Office Hits", "type": "trakt_box_office"},
        {"id": "imdb_top", "title": "IMDb: Top Rated", "type": "trakt_list", "list_id": "2142753"},
        {"id": "mindfucks", "title": "Best Mindfucks & Thrillers", "type": "trakt_list", "list_id": "800238"},
        {"id": "mcu", "title": "Marvel Cinematic Universe", "type": "trakt_list", "list_id": "1248149"},
        {"id": "anticipated", "title": "Most Anticipated", "type": "trakt_anticipated"},
    ]


async def _fetch_trakt_lane_items(lane_cfg: dict, page: int = 1, limit: int = 20) -> list:
    l_type = lane_cfg.get("type", "")
    if l_type == "trakt_trending":
        return await trakt_client.get_trending(page=page, limit=limit)
    elif l_type == "trakt_watched":
        period = lane_cfg.get("period", "weekly")
        return await trakt_client.get_watched(period=period, page=page, limit=limit)
    elif l_type == "trakt_box_office":
        return await trakt_client.get_box_office()
    elif l_type == "trakt_anticipated":
        return await trakt_client.get_anticipated(page=page, limit=limit)
    elif l_type == "trakt_list":
        list_id = lane_cfg.get("list_id", "")
        return await trakt_client.get_list_items(list_id, page=page, limit=limit)
    return []


@router.get("/dashboard", response_model=DashboardResponse)
async def get_dashboard(
    language: str = Query("ta", description="Language code: ta or en"),
):
    safe_lang = language.strip().lower() if isinstance(language, str) else "ta"
    lanes: list[DashboardLane] = []

    if safe_lang.startswith("ta"):
        raw_new = await tmdb_client.discover_movies(
            language="ta",
            sort_by="primary_release_date.desc",
            page=1,
        )
        new_items = [MovieSummary.from_tmdb(m, media_type="movie") for m in raw_new]
        has_more_new = len(new_items) >= 20
        lanes.append(
            DashboardLane(
                id="new",
                title="New Releases",
                items=new_items,
                has_more=has_more_new,
                next_page=2 if has_more_new else None,
            )
        )

        tamil_configs = [
            ("trending", "Trending Tamil"),
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
        en_configs = _load_lanes_en_config()
        results = await asyncio.gather(
            *[_fetch_trakt_lane_items(cfg, page=1, limit=20) for cfg in en_configs],
            return_exceptions=True,
        )

        for i, cfg in enumerate(en_configs):
            lane_id = cfg.get("id", f"lane_{i}")
            title = cfg.get("title", "Popular")
            res = results[i]
            if isinstance(res, Exception) or not res:
                items = []
            elif isinstance(res, list) and len(res) > 0 and isinstance(res[0], MovieSummary):
                items = res
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
    genre: int | str | None = Query(None, description="Genre ID to filter by"),
    year: int | None = Query(None, description="Release year to filter by"),
):
    safe_lang = language.strip().lower() if isinstance(language, str) else "ta"
    safe_page = page if isinstance(page, int) and page >= 1 else 1
    safe_limit = limit if isinstance(limit, int) and 1 <= limit <= 50 else 20
    safe_genre = genre if isinstance(genre, (int, str)) and str(genre).lower() != "all" and str(genre) != "0" else None
    safe_year = year if isinstance(year, int) else None
    offset = (safe_page - 1) * safe_limit

    if safe_lang.startswith("ta") and lane_id == "new":
        raw_items = await tmdb_client.discover_movies(
            language="ta",
            genre=safe_genre,
            year=safe_year,
            sort_by="primary_release_date.desc",
            page=safe_page,
        )
        items = [MovieSummary.from_tmdb(m, media_type="movie") for m in raw_items]
        has_more = len(items) >= safe_limit
        return LaneMoviesResponse(
            id=lane_id,
            page=safe_page,
            has_more=has_more,
            next_page=(safe_page + 1) if has_more else None,
            total_pages=None,
            items=items,
            results=items,
        )

    if safe_lang.startswith("ta") and lane_id in ["trending", "box_office", "top_rated", "comedy"]:
        if safe_genre is not None or safe_year is not None:
            sort_map = {
                "trending": "popularity.desc",
                "top_rated": "vote_average.desc",
                "box_office": "revenue.desc",
                "comedy": "popularity.desc",
            }
            sort_by = sort_map.get(lane_id, "popularity.desc")
            target_genre = safe_genre
            if lane_id == "comedy" and not target_genre:
                target_genre = 35
            raw_items = await tmdb_client.discover_movies(
                language="ta",
                genre=target_genre,
                year=safe_year,
                sort_by=sort_by,
                page=safe_page,
            )
            items = [MovieSummary.from_tmdb(m, media_type="movie") for m in raw_items]
            has_more = len(items) >= safe_limit
            return LaneMoviesResponse(
                id=lane_id,
                page=safe_page,
                has_more=has_more,
                next_page=(safe_page + 1) if has_more else None,
                total_pages=None,
                items=items,
                results=items,
            )

        raw_items = catalog_service.get_lane_movies(lane_id, limit=safe_limit, offset=offset)
        items = [MovieSummary.from_catalog(r) for r in raw_items]
        total = catalog_service.get_lane_count(lane_id)
        total_pages = (total + safe_limit - 1) // safe_limit if total > 0 else 1
        has_more = safe_page < total_pages and len(items) == safe_limit
        return LaneMoviesResponse(
            id=lane_id,
            page=safe_page,
            has_more=has_more,
            next_page=(safe_page + 1) if has_more else None,
            total_pages=total_pages,
            items=items,
            results=items,
        )

    en_configs = _load_lanes_en_config()
    matched_cfg = next((c for c in en_configs if c.get("id") == lane_id), None)
    if matched_cfg and safe_genre is None and safe_year is None:
        items = await _fetch_trakt_lane_items(matched_cfg, page=safe_page, limit=safe_limit)
    else:
        raw_items = await tmdb_client.discover_movies(
            language=safe_lang,
            genre=safe_genre,
            year=safe_year,
            page=safe_page,
        )
        items = [MovieSummary.from_tmdb(m, media_type="movie") for m in raw_items]

    has_more = len(items) >= safe_limit
    return LaneMoviesResponse(
        id=lane_id,
        page=safe_page,
        has_more=has_more,
        next_page=(safe_page + 1) if has_more else None,
        total_pages=None,
        items=items,
        results=items,
    )


@router.get("/filters", response_model=FiltersResponse)
async def get_filters():
    raw_genres = await tmdb_client.get_genres()
    genres = [FilterOption(id=None, label="All Genres")] + [
        FilterOption(id=g.get("id"), label=g.get("name", "")) for g in raw_genres if g.get("id")
    ]

    languages = [
        FilterOption(id="all", label="All"),
        FilterOption(id="ta", label="Tamil"),
        FilterOption(id="en", label="English"),
        FilterOption(id="anime", label="Anime (Japanese)"),
    ]

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


@router.get("/search", response_model=PaginatedMovieResponse)
@router.get("/discover", response_model=PaginatedMovieResponse)
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
        trakt_results = await trakt_client.search_movies(
            query=safe_query,
            year=safe_year,
            language=safe_lang,
            page=safe_page,
            limit=20,
        )
        if trakt_results:
            items = trakt_results
        else:
            results = await tmdb_client.search_movie(
                query=safe_query,
                year=safe_year,
                language=safe_lang,
                page=safe_page,
            )
            items = [MovieSummary.from_tmdb(item, media_type="movie") for item in results]
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
        items = [MovieSummary.from_tmdb(item, media_type="movie") for item in results]

    has_more = len(items) >= 20
    return PaginatedMovieResponse(
        page=safe_page,
        has_more=has_more,
        next_page=(safe_page + 1) if has_more else None,
        total_pages=None,
        items=items,
        results=items,
    )


@router.get("/search/lists")
async def search_lists_endpoint(
    query: str | None = Query(None, description="The query to search for curated lists (optional)"),
    page: int = Query(1, ge=1, description="Page number to fetch"),
    limit: int = Query(20, ge=1, le=50, description="Items per page"),
):
    safe_query = query.strip() if isinstance(query, str) and query.strip() else None
    safe_page = page if isinstance(page, int) and page >= 1 else 1
    safe_limit = limit if isinstance(limit, int) and 1 <= limit <= 50 else 20

    if safe_query:
        lists = await trakt_client.search_lists(query=safe_query, page=safe_page, limit=safe_limit)
    else:
        lists = await trakt_client.get_popular_lists(page=safe_page, limit=safe_limit)
    return {"results": lists}


@router.get("/lists/{list_id}/items", response_model=PaginatedMovieResponse)
async def get_list_items_endpoint(
    list_id: str,
    page: int = Query(1, ge=1, description="Page number to fetch"),
    limit: int = Query(20, ge=1, le=50, description="Items per page"),
):
    safe_page = page if isinstance(page, int) and page >= 1 else 1
    safe_limit = limit if isinstance(limit, int) and 1 <= limit <= 50 else 20

    items = await trakt_client.get_list_items(list_id=list_id, page=safe_page, limit=safe_limit)
    has_more = len(items) >= safe_limit
    return PaginatedMovieResponse(
        page=safe_page,
        has_more=has_more,
        next_page=(safe_page + 1) if has_more else None,
        total_pages=None,
        items=items,
        results=items,
    )


@router.get("/tv/{tmdb_id}/season/{season_number}", response_model=TvSeason)
async def get_tv_season_endpoint(
    tmdb_id: int,
    season_number: int,
):
    details = await tmdb_client.get_tv_season(tmdb_id, season_number)
    if not details:
        raise HTTPException(status_code=404, detail=f"Season {season_number} not found on TMDB.")

    raw_episodes = details.get("episodes", [])
    episodes = [
        TvEpisode(
            id=ep.get("id", 0),
            episode_number=ep.get("episode_number", 0),
            season_number=ep.get("season_number", season_number),
            name=ep.get("name", ""),
            overview=ep.get("overview", ""),
            still_path=ep.get("still_path"),
            air_date=ep.get("air_date"),
            vote_average=float(ep.get("vote_average") or 0.0),
            runtime=ep.get("runtime"),
        )
        for ep in raw_episodes
        if isinstance(ep, dict)
    ]
    return TvSeason(
        id=details.get("id", 0),
        season_number=details.get("season_number", season_number),
        name=details.get("name", f"Season {season_number}"),
        overview=details.get("overview", ""),
        poster_path=details.get("poster_path"),
        episode_count=len(episodes),
        air_date=details.get("air_date"),
        episodes=episodes,
    )


@router.get("/actors/curated", response_model=list[ActorSummary])
async def get_curated_actors(
    language: str = Query("ta", description="Language code: ta or en"),
):
    safe_lang = language.strip().lower() if isinstance(language, str) else "ta"
    raw_actors = await tmdb_client.get_curated_actors(language=safe_lang)
    return [
        ActorSummary(
            id=a.get("id", 0),
            name=a.get("name", ""),
            profile_path=a.get("profile_path"),
            known_for_department=a.get("known_for_department", "Acting"),
        )
        for a in raw_actors
    ]


@router.get("/person/{person_id}", response_model=PersonDetailsResponse)
async def get_person_filmography(
    person_id: int,
):
    data = await tmdb_client.get_person_filmography(person_id)
    if not data:
        raise HTTPException(status_code=404, detail="Person not found on TMDB.")

    popular_items = [
        MovieSummary.from_tmdb(m, media_type=m.get("media_type", "movie"))
        for m in data.get("popular", [])
    ]
    recent_items = [
        MovieSummary.from_tmdb(m, media_type=m.get("media_type", "movie"))
        for m in data.get("recent", [])
    ]

    return PersonDetailsResponse(
        id=data.get("id", person_id),
        name=data.get("name", ""),
        biography=data.get("biography", ""),
        profile_path=data.get("profile_path"),
        known_for_department=data.get("known_for_department", "Acting"),
        birthday=data.get("birthday"),
        place_of_birth=data.get("place_of_birth"),
        popular=popular_items,
        recent=recent_items,
    )


@router.get("/{tmdb_id}", response_model=MovieDetails)
@router.get("/{media_type}/{tmdb_id}", response_model=MovieDetails)
async def get_details(
    tmdb_id: int,
    media_type: str = "movie",
):
    clean_type = (media_type or "movie").strip().lower()
    details = None
    if clean_type == "tv":
        details = await tmdb_client.get_tv_details(tmdb_id)
        if not details:
            details = await tmdb_client.get_movie_details(tmdb_id)
            clean_type = "movie"
    else:
        details = await tmdb_client.get_movie_details(tmdb_id)
        if not details:
            details = await tmdb_client.get_tv_details(tmdb_id)
            clean_type = "tv"

    if not details:
        raise HTTPException(status_code=404, detail="Media not found on TMDB.")

    model = MovieDetails.from_tmdb(details, media_type=clean_type)
    if model.imdb_id:
        from backend.services.imdb_ratings import get_imdb_rating
        rating_tuple = get_imdb_rating(model.imdb_id)
        if rating_tuple:
            model.vote_average = rating_tuple[0]
            model.vote_count = rating_tuple[1]
    return model
