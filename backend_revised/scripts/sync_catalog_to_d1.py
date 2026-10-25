#!/usr/bin/env python3
"""
Direct MDBList List -> Cloudflare D1 Sync
Fetches curated lane rankings and full metadata from MDBList list API,
generating D1 SQL statements for lane_entries, movies, and ratings.
Zero web scraping, zero curl_cffi dependency, 100% official REST API.
"""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import time
import urllib.parse
import urllib.request

MDBLIST_BASE_URL = "https://api.mdblist.com"

LANES_CONFIG = [
    {
        "lane_id": "trending",
        "title": "Trending Now",
        "list_id": 218335,
        "query": "sort=imdbpopular&sort_order=asc",
        "exclude_lang": "en",
    },
    {
        "lane_id": "new_releases",
        "title": "New in Theaters",
        "list_id": 218335,
        "query": "sort=released&sort_order=desc&released_to={today}",
        "lang": "ta",
    },
    {
        "lane_id": "new_ott",
        "title": "New on OTT",
        "list_id": 218335,
        "query": "sort=releasedigital&sort_order=desc",
        "exclude_lang": "en",
    },
    {
        "lane_id": "top_rated",
        "title": "All-Time Masterpieces",
        "list_id": 218335,
        "query": "sort=letterrating&sort_order=desc",
        "exclude_lang": "en",
        "min_rating": 7.0,
        "min_votes": 5000,
    },
    {
        "lane_id": "comedy",
        "title": "Popular Comedy",
        "list_id": 218335,
        "query": "sort=imdbpopular&sort_order=asc&filter_genre=comedy",
        "exclude_lang": "en",
    },
    {
        "lane_id": "pan_india",
        "title": "South Indian Blockbusters",
        "list_id": 76398,
        "query": "sort=imdbvotes&sort_order=desc",
    },
]


def resolve_api_key(cli_key: str | None) -> str:
    if cli_key:
        return cli_key
    env_key = os.getenv("MDBLIST_API_KEY")
    if env_key:
        return env_key

    # Check .env or .dev.vars
    for env_path in [Path(".env"), Path("backend_revised/.dev.vars"), Path("../.env")]:
        if env_path.exists():
            try:
                for line in env_path.read_text(encoding="utf-8").splitlines():
                    if line.startswith("MDBLIST_API_KEY="):
                        val = line.split("=", 1)[1].strip().strip('"').strip("'")
                        if val:
                            return val
            except Exception:
                pass

    raise ValueError(
        "MDBLIST_API_KEY not found. Set it in environment variables, pass --api-key, or define it in .env / backend_revised/.dev.vars."
    )


def escape_sql(val: str | None) -> str:
    if val is None:
        return "NULL"
    cleaned = str(val).replace("'", "''")
    return f"'{cleaned}'"


def fetch_lane_movies(api_key: str, cfg: dict) -> list[dict]:
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    query_str = cfg.get("query", "").format(today=today)
    url = (
        f"{MDBLIST_BASE_URL}/lists/{cfg['list_id']}/items"
        f"?limit=1000&append_to_response=genres,poster,description,ratings&apikey={api_key}"
    )
    if query_str:
        url += f"&{query_str}"

    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko)",
            "Accept": "application/json",
        },
    )

    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    movies = data.get("movies", [])
    required_lang = cfg.get("lang")
    if required_lang:
        movies = [m for m in movies if m.get("language") == required_lang]

    exclude_lang = cfg.get("exclude_lang")
    if exclude_lang:
        movies = [m for m in movies if m.get("language") != exclude_lang]

    min_rating = cfg.get("min_rating")
    min_votes = cfg.get("min_votes")
    if min_rating is not None or min_votes is not None:
        filtered = []
        for m in movies:
            lr = next((r.get("value") for r in m.get("ratings", []) if r.get("source") == "letterboxd" and r.get("value")), None)
            ir = next((r.get("value") for r in m.get("ratings", []) if r.get("source") == "imdb" and r.get("value")), None)
            val = lr if lr is not None else ir
            votes = next((r.get("votes") for r in m.get("ratings", []) if r.get("source") == "imdb" and r.get("votes")), 0)
            if min_rating is not None and (val is None or val < min_rating):
                continue
            if min_votes is not None and (votes is None or votes < min_votes):
                continue
            filtered.append(m)
        movies = filtered

    return movies


def generate_sync_sql(api_key: str, out_sql_file: Path) -> int:
    now = int(time.time())
    statements: list[str] = []
    seen_movies: set[str] = set()

    print(f"[MDBList Sync] Syncing {len(LANES_CONFIG)} lanes to D1 SQL...")

    for cfg in LANES_CONFIG:
        lane_id = cfg["lane_id"]
        print(f"  -> Fetching lane '{lane_id}' ({cfg['title']}) from list {cfg['list_id']}...")

        try:
            movies = fetch_lane_movies(api_key, cfg)
        except Exception as e:
            print(f"  [Error] Failed to fetch lane '{lane_id}': {e}")
            continue

        print(f"  -> Found {len(movies)} qualified movies for '{lane_id}'.")
        valid_movies = [
            m for m in movies
            if (m.get("imdb_id") or m.get("ids", {}).get("imdb") or "").startswith("tt")
        ]
        if not valid_movies:
            continue

        statements.append(f"DELETE FROM lane_entries WHERE lane_id = '{lane_id}';")

        for rank, item in enumerate(valid_movies, start=1):
            imdb_id = item.get("imdb_id") or item.get("ids", {}).get("imdb")

            # 1. Movie & Ratings metadata (upsert once per unique movie)
            if imdb_id not in seen_movies:
                seen_movies.add(imdb_id)

                tmdb_id = item.get("id") or item.get("ids", {}).get("tmdb")
                tmdb_id_sql = str(int(tmdb_id)) if tmdb_id else "NULL"
                title = escape_sql(item.get("title", "Unknown"))
                year = item.get("release_year")
                year_sql = str(int(year)) if year else "NULL"
                rel_date = item.get("release_date") or (f"{year}-01-01" if year else "")
                release_date_sql = escape_sql(rel_date)
                poster_sql = escape_sql(item.get("poster") or "")
                backdrop_sql = escape_sql("")
                overview_sql = escape_sql(item.get("description") or "")
                runtime = item.get("runtime")
                runtime_sql = str(int(runtime)) if runtime else "NULL"

                raw_genres = item.get("genres", [])
                genres_list = [{"id": 0, "name": g} for g in raw_genres if isinstance(g, str)]
                genres_sql = escape_sql(json.dumps(genres_list))

                movie_stmt = (
                    f"INSERT INTO movies (imdb_id, tmdb_id, media_type, title, year, release_date, poster_path, backdrop_path, overview, runtime, genres, updated_at) "
                    f"VALUES ('{imdb_id}', {tmdb_id_sql}, 'movie', {title}, {year_sql}, {release_date_sql}, {poster_sql}, {backdrop_sql}, {overview_sql}, {runtime_sql}, {genres_sql}, {now}) "
                    f"ON CONFLICT(imdb_id) DO UPDATE SET "
                    f"tmdb_id = COALESCE(excluded.tmdb_id, movies.tmdb_id), "
                    f"title = excluded.title, "
                    f"year = COALESCE(excluded.year, movies.year), "
                    f"release_date = CASE WHEN excluded.release_date != '' THEN excluded.release_date ELSE movies.release_date END, "
                    f"poster_path = CASE WHEN excluded.poster_path != '' THEN excluded.poster_path ELSE movies.poster_path END, "
                    f"overview = CASE WHEN excluded.overview != '' THEN excluded.overview ELSE movies.overview END, "
                    f"genres = excluded.genres, "
                    f"updated_at = excluded.updated_at;"
                )
                statements.append(movie_stmt)

                # Primary IMDb rating & votes (fallback to TMDb if absent)
                imdb_r = next((r for r in item.get("ratings", []) if r.get("source") == "imdb"), {})
                tmdb_r = next((r for r in item.get("ratings", []) if r.get("source") == "tmdb"), {})
                rating = float(imdb_r.get("value") or (tmdb_r.get("value") / 10.0 if tmdb_r.get("value") else 0.0))
                votes = int(imdb_r.get("votes") or tmdb_r.get("votes") or 0)

                rating_stmt = (
                    f"INSERT INTO ratings (imdb_id, rating, votes, updated_at) "
                    f"VALUES ('{imdb_id}', {rating}, {votes}, {now}) "
                    f"ON CONFLICT(imdb_id) DO UPDATE SET "
                    f"rating = excluded.rating, "
                    f"votes = excluded.votes, "
                    f"updated_at = excluded.updated_at;"
                )
                statements.append(rating_stmt)

            # 2. Lane entry rank
            lane_stmt = (
                f"INSERT INTO lane_entries (lane_id, imdb_id, rank, updated_at) "
                f"VALUES ('{lane_id}', '{imdb_id}', {rank}, {now}) "
                f"ON CONFLICT(lane_id, imdb_id) DO UPDATE SET "
                f"rank = excluded.rank, "
                f"updated_at = excluded.updated_at;"
            )
            statements.append(lane_stmt)

    out_sql_file.parent.mkdir(parents=True, exist_ok=True)
    with open(out_sql_file, "w", encoding="utf-8") as f:
        f.write("\n\n".join(statements) + "\n")

    print(f"[Done] Generated {len(statements)} SQL statements for D1 -> {out_sql_file}")
    return len(statements)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fetch MDBList lanes directly into D1 SQL")
    parser.add_argument("--api-key", type=str, default=None, help="MDBList API Key")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "sync_catalog.sql",
        help="Output .sql file path",
    )
    args = parser.parse_args()

    api_key = resolve_api_key(args.api_key)
    generate_sync_sql(api_key, args.output)
