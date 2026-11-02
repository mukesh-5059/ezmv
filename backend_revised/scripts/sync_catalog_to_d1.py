#!/usr/bin/env python3
"""
Direct MDBList List -> Cloudflare D1 Sync
Fetches curated lane rankings and full metadata from MDBList list API,
generating D1 SQL statements for lane_entries, movies, and ratings.
Zero web scraping, zero curl_cffi dependency, 100% official REST API.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone, timedelta
import json
import math
import os
from pathlib import Path
import time
import urllib.parse
import urllib.request

MDBLIST_BASE_URL = "https://api.mdblist.com"

ANYTHING_TO_GENRE_SLUGS = {
    "action": ["action"],
    "adventure": ["adventure"],
    "animation": ["animation"],
    "anime": ["anime"],
    "biography": ["biography"],
    "comedy": ["comedy"],
    "crime": ["crime"],
    "documentary": ["documentary"],
    "drama": ["drama"],
    "family": ["family"],
    "fantasy": ["fantasy"],
    "history": ["history"],
    "horror": ["horror"],
    "music": ["music"],
    "musical": ["music"],
    "mystery": ["mystery"],
    "romance": ["romance"],
    "sci-fi": ["sci-fi"],
    "science fiction": ["sci-fi"],
    "science-fiction": ["sci-fi"],
    "sci fi": ["sci-fi"],
    "sport": ["sport"],
    "sports": ["sport"],
    "sporting event": ["sport"],
    "sporting-event": ["sport"],
    "thriller": ["thriller"],
    "suspense": ["thriller"],
    "war": ["war"],
    "western": ["western"],
    # Compound TV genres
    "action & adventure": ["action", "adventure"],
    "action-&-adventure": ["action", "adventure"],
    "sci-fi & fantasy": ["sci-fi", "fantasy"],
    "sci-fi-&-fantasy": ["sci-fi", "fantasy"],
    "war & politics": ["war"],
    "war-&-politics": ["war"],
}

def normalize_genre_slugs(raw: str) -> list[str]:
    key = raw.strip().lower()
    if key in ANYTHING_TO_GENRE_SLUGS:
        return ANYTHING_TO_GENRE_SLUGS[key]
    return [key.replace(" ", "-")]

MIN_VOTES = {
    "imdb": 500,
    "letterboxd": 50,
    "tomatoes": 10,
    "popcorn": 50,
    "tomatoesaudience": 50,
    "tmdb": 20,
    "metacritic": 5,
    "trakt": 20,
}

SOURCE_WEIGHTS = {
    "imdb": 0.30,
    "letterboxd": 0.25,
    "tomatoes": 0.15,
    "popcorn": 0.10,
    "tomatoesaudience": 0.10,
    "tmdb": 0.10,
    "metacritic": 0.05,
    "trakt": 0.05,
}

def compute_composite_rating(item: dict) -> tuple[float, int, str]:
    raw_ratings = item.get("ratings") or []
    weighted_sum = 0.0
    total_weight = 0.0
    total_votes = 0
    cleaned_ratings = []
    qualified_sources = set()

    for r in raw_ratings:
        src = r.get("source")
        if not src:
            continue
        val = r.get("value")
        score = r.get("score")
        votes = int(r.get("votes") or 0)
        cleaned_ratings.append({
            "source": src,
            "value": val,
            "score": score,
            "votes": votes,
        })

        weight = SOURCE_WEIGHTS.get(src)
        if not weight:
            continue

        min_votes = MIN_VOTES.get(src, 0)
        if votes < min_votes:
            continue

        normalized = None
        if score is not None and isinstance(score, (int, float)):
            normalized = score / 10.0

        if normalized is not None:
            weighted_sum += normalized * weight
            total_weight += weight
            total_votes += votes
            qualified_sources.add(src)

    ratings_json = json.dumps(cleaned_ratings)

    if total_weight > 0 and len(qualified_sources) > 0:
        raw_rating = weighted_sum / total_weight
        num_sources = len(qualified_sources)

        if num_sources == 1:
            m = 10000.0
        elif num_sources == 2:
            m = 3000.0
        else:
            m = 1000.0

        # Era modifier
        now = datetime.now(timezone.utc)
        current_year = now.year
        age = None
        rel_date_str = item.get("release_date") or item.get("released")
        if rel_date_str:
            try:
                parts = str(rel_date_str).strip().split("-")
                if len(parts) >= 1 and len(parts[0]) == 4:
                    y = int(parts[0])
                    mth = int(parts[1]) if len(parts) > 1 else 1
                    d = int(parts[2]) if len(parts) > 2 else 1
                    rel_dt = datetime(y, mth, d, tzinfo=timezone.utc)
                    age = (now - rel_dt).days / 365.25
            except Exception:
                pass

        if age is None:
            y = item.get("release_year") or item.get("year")
            if y:
                try:
                    age = float(current_year - int(y))
                except Exception:
                    pass

        if age is not None:
            age = max(0.0, age)
            penalty = 0.5 * math.exp(-age * 1.5)
            boost = 0.5 * max(0.0, min(1.0, (age - 3.0) / 25.0))
            raw_era = max(0.5, min(1.5, 1.0 + penalty - boost))
            era_modifier = 1.0 + (raw_era - 1.0) / num_sources
            m *= era_modifier

        C = 6.8
        rating_score = round(
            (total_votes / (total_votes + m)) * raw_rating + (m / (total_votes + m)) * C,
            1,
        )
        return rating_score, total_votes, ratings_json

    return 0.0, 0, ratings_json


LANES_CONFIG = [
    {
        "lane_id": "trending",
        "title": "Trending Now",
        "list_id": 218335,
        "query": "sort=tmdbpopular&sort_order=desc",
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
        "query": "sort=tmdbpopular&sort_order=desc&filter_genre=comedy",
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
            rating_score, votes, _ = compute_composite_rating(m)
            if min_rating is not None and rating_score < min_rating:
                continue
            if min_votes is not None and votes < min_votes:
                continue
            filtered.append(m)
        movies = filtered

    return movies


def fetch_batch_details(api_key: str, imdb_ids: list[str]) -> dict[str, dict]:
    """Batch-fetches full multi-source ratings (Letterboxd, RT, Trakt, Metacritic) from MDBList."""
    lookup = {}
    if not imdb_ids:
        return lookup

    cache_file = Path("/tmp/mdblist_batch_cache.json")
    if cache_file.exists():
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                lookup = json.load(f)
            missing = [iid for iid in imdb_ids if iid not in lookup]
            print(f"  [Cache] Loaded {len(lookup)} items from {cache_file}. {len(missing)} missing.")
            if not missing:
                return lookup
            imdb_ids = missing
        except Exception as e:
            print(f"  [Cache Warning] Could not load cache: {e}")

    url = f"{MDBLIST_BASE_URL}/imdb/movie/?apikey={api_key}"
    chunk_size = 100
    chunks = [imdb_ids[i:i + chunk_size] for i in range(0, len(imdb_ids), chunk_size)]

    def fetch_chunk(chunk_data):
        idx, chunk = chunk_data
        try:
            req = urllib.request.Request(
                url,
                data=json.dumps({"ids": chunk}).encode("utf-8"),
                headers={"Content-Type": "application/json", "User-Agent": "MDBListSync/1.0"}
            )
            with urllib.request.urlopen(req, timeout=30) as res:
                return json.loads(res.read().decode("utf-8"))
        except Exception as e:
            print(f"  [Warning] Batch ratings fetch failed for chunk {idx + 1}: {e}")
            return []

    print(f"  -> Concurrently fetching {len(chunks)} chunks of batch ratings...")
    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = [executor.submit(fetch_chunk, (i, ch)) for i, ch in enumerate(chunks)]
        for fut in as_completed(futures):
            items = fut.result()
            for item in items:
                iid = item.get("imdbid") or item.get("ids", {}).get("imdb")
                if iid:
                    lookup[iid] = item

    try:
        with open(cache_file, "w", encoding="utf-8") as f:
            json.dump(lookup, f)
        print(f"  [Cache] Saved {len(lookup)} items to {cache_file}.")
    except Exception as e:
        print(f"  [Cache Warning] Could not save cache: {e}")

    return lookup



def generate_sync_sql(api_key: str, out_sql_file: Path) -> int:
    now = int(time.time())
    statements: list[str] = []
    seen_movies: set[str] = set()
    lanes_data: list[tuple[str, list[dict]]] = []
    all_unique_ids: set[str] = set()

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

        lanes_data.append((lane_id, valid_movies))
        for m in valid_movies:
            iid = m.get("imdb_id") or m.get("ids", {}).get("imdb")
            if iid:
                all_unique_ids.add(iid)

    print(f"  -> Fetching full multi-source ratings for {len(all_unique_ids)} unique titles via MDBList batch...")
    batch_details = fetch_batch_details(api_key, list(all_unique_ids))

    now_dt = datetime.now(timezone.utc)
    cutoff_180d = now_dt - timedelta(days=180)
    cutoff_90d = now_dt - timedelta(days=90)

    # 1. Ingest all unique movies and ratings into catalog
    catalog: dict[str, dict] = {}
    for lane_id, valid_movies in lanes_data:
        for item in valid_movies:
            imdb_id = item.get("imdb_id") or item.get("ids", {}).get("imdb")
            if not imdb_id or imdb_id in catalog:
                continue
            full_item = {**item, **batch_details.get(imdb_id, {})}
            rating_score, votes, ratings_json = compute_composite_rating(full_item)
            poster = full_item.get("poster") or item.get("poster") or ""
            runtime = full_item.get("runtime") or item.get("runtime") or 0
            lang = full_item.get("language") or item.get("language") or ""
            rel_str = full_item.get("released") or full_item.get("release_date") or item.get("release_date") or ""

            rel_dt = None
            if rel_str and len(rel_str) >= 10:
                try:
                    rel_dt = datetime.strptime(rel_str[:10], "%Y-%m-%d").replace(tzinfo=timezone.utc)
                except Exception:
                    pass

            raw_genres = item.get("genres", [])
            seen_genres = set()
            slugs = []
            for g in raw_genres:
                raw_str = g if isinstance(g, str) else (g.get("name") or g.get("title") or g.get("slug") or "")
                if not raw_str or not isinstance(raw_str, str):
                    continue
                for slug in normalize_genre_slugs(raw_str):
                    if slug and slug not in seen_genres:
                        seen_genres.add(slug)
                        slugs.append(slug)

            is_excluded_genre = any(s in ("documentary", "short", "animation") for s in slugs)
            imdb_votes = next((int(r.get("votes") or 0) for r in (full_item.get("ratings") or []) if r.get("source") == "imdb"), 0)
            lb_votes = next((int(r.get("votes") or 0) for r in (full_item.get("ratings") or []) if r.get("source") == "letterboxd"), 0)

            catalog[imdb_id] = {
                "imdb_id": imdb_id,
                "full_item": full_item,
                "item": item,
                "rating_score": rating_score,
                "votes": votes,
                "ratings_json": ratings_json,
                "poster": poster,
                "runtime": runtime,
                "lang": lang,
                "rel_str": rel_str,
                "rel_dt": rel_dt,
                "slugs": slugs,
                "is_excluded_genre": is_excluded_genre,
                "imdb_votes": imdb_votes,
                "lb_votes": lb_votes,
            }

            # Generate movie & rating upsert statements
            media_type = "tv" if (item.get("type") == "show" or full_item.get("type") == "show") else "movie"
            tmdb_id = item.get("id") or item.get("ids", {}).get("tmdb")
            tmdb_id_sql = f"'{media_type}:{int(tmdb_id)}'" if tmdb_id else "NULL"
            title = escape_sql(item.get("title", "Unknown"))
            year = item.get("release_year") or full_item.get("year")
            year_sql = str(int(year)) if year else "NULL"
            rel_date_sql = escape_sql(rel_str[:10] if rel_str else (f"{year}-01-01" if year else ""))
            poster_sql = escape_sql(poster)
            backdrop_sql = escape_sql(item.get("backdrop") or full_item.get("backdrop") or "")
            overview_sql = escape_sql(item.get("description") or full_item.get("description") or "")
            runtime_sql = str(int(runtime)) if runtime else "NULL"
            genres_sql = escape_sql(json.dumps(slugs))

            movie_stmt = (
                f"INSERT INTO movies (imdb_id, tmdb_id, media_type, title, year, release_date, poster_path, backdrop_path, overview, runtime, genres, updated_at) "
                f"VALUES ('{imdb_id}', {tmdb_id_sql}, '{media_type}', {title}, {year_sql}, {rel_date_sql}, {poster_sql}, {backdrop_sql}, {overview_sql}, {runtime_sql}, {genres_sql}, {now}) "
                f"ON CONFLICT(imdb_id) DO UPDATE SET "
                f"tmdb_id = COALESCE(excluded.tmdb_id, movies.tmdb_id), "
                f"media_type = excluded.media_type, "
                f"title = excluded.title, "
                f"year = COALESCE(excluded.year, movies.year), "
                f"release_date = CASE WHEN excluded.release_date != '' THEN excluded.release_date ELSE movies.release_date END, "
                f"poster_path = CASE WHEN excluded.poster_path != '' THEN excluded.poster_path ELSE movies.poster_path END, "
                f"overview = CASE WHEN excluded.overview != '' THEN excluded.overview ELSE movies.overview END, "
                f"genres = excluded.genres, "
                f"updated_at = excluded.updated_at;"
            )
            statements.append(movie_stmt)

            ratings_sql = escape_sql(ratings_json)
            rating_stmt = (
                f"INSERT INTO ratings (imdb_id, ratings, rating_score, votes, updated_at) "
                f"VALUES ('{imdb_id}', {ratings_sql}, {rating_score}, {votes}, {now}) "
                f"ON CONFLICT(imdb_id) DO UPDATE SET "
                f"ratings = excluded.ratings, "
                f"rating_score = excluded.rating_score, "
                f"votes = excluded.votes, "
                f"updated_at = excluded.updated_at;"
            )
            statements.append(rating_stmt)

    # 2. Generate Local Rule-Based Dynamic Lanes
    lanes_items: dict[str, list[str]] = {}

    # Trending: Last 180 days, lang=ta, rt>=85, !excluded, votes>=400, sorted by velocity
    trending_cands = []
    for iid, m in catalog.items():
        if m["lang"] != "ta" or not m["poster"] or m["runtime"] < 85 or m["is_excluded_genre"]:
            continue
        if not m["rel_dt"] or m["rel_dt"] < cutoff_180d or m["rel_dt"] > now_dt:
            continue
        if (m["imdb_votes"] + m["lb_votes"]) < 400:
            continue
        age_days = max(1, (now_dt - m["rel_dt"]).days)
        vel = (m["lb_votes"] * 1.5 + m["imdb_votes"]) / (age_days + 21)
        trending_cands.append((vel, iid))
    trending_cands.sort(key=lambda x: x[0], reverse=True)
    lanes_items["trending"] = [c[1] for c in trending_cands[:100]]

    # New Releases: Last 90 days, lang=ta, rt>=85, !excluded, votes>=400 (or lb>=200), sorted by rel_date desc
    nr_cands = []
    for iid, m in catalog.items():
        if m["lang"] != "ta" or not m["poster"] or m["runtime"] < 85 or m["is_excluded_genre"]:
            continue
        if not m["rel_dt"] or m["rel_dt"] < cutoff_90d or m["rel_dt"] > now_dt:
            continue
        if m["imdb_votes"] < 400 and m["lb_votes"] < 200:
            continue
        nr_cands.append((m["rel_dt"], iid))
    nr_cands.sort(key=lambda x: x[0], reverse=True)
    lanes_items["new_releases"] = [c[1] for c in nr_cands[:100]]

    # New on OTT: Preserve MDBList's internal sort=releasedigital order, applying quality gates
    ott_movies = next((vm for lid, vm in lanes_data if lid == "new_ott"), [])
    ott_cands = []
    for item in ott_movies:
        iid = item.get("imdb_id") or item.get("ids", {}).get("imdb")
        m = catalog.get(iid)
        if not m or m["lang"] == "en" or not m["poster"] or m["runtime"] < 85 or m["is_excluded_genre"]:
            continue
        if m["rel_dt"] and m["rel_dt"] > now_dt:
            continue
        if m["votes"] < 400:
            continue
        ott_cands.append(iid)
    lanes_items["new_ott"] = ott_cands[:100]

    # Top Rated: lang!=en, poster, votes>=5000, rating_score>=7.0, sorted by rating_score desc, votes desc
    top_cands = []
    for iid, m in catalog.items():
        if m["lang"] == "en" or not m["poster"] or m["votes"] < 5000 or m["rating_score"] < 7.0:
            continue
        top_cands.append((m["rating_score"], m["votes"], iid))
    top_cands.sort(key=lambda x: (x[0], x[1]), reverse=True)
    lanes_items["top_rated"] = [c[2] for c in top_cands[:100]]

    # Comedy: lang!=en, poster, comedy in genres, votes>=500, sorted by votes desc
    comedy_cands = []
    for iid, m in catalog.items():
        if m["lang"] == "en" or not m["poster"] or "comedy" not in m["slugs"] or m["votes"] < 500:
            continue
        comedy_cands.append((m["votes"], iid))
    comedy_cands.sort(key=lambda x: x[0], reverse=True)
    lanes_items["comedy"] = [c[1] for c in comedy_cands[:100]]

    # Pan India: Blockbusters from list 76398
    pan_india_cands = []
    pan_movies = next((vm for lid, vm in lanes_data if lid == "pan_india"), [])
    for item in pan_movies:
        iid = item.get("imdb_id") or item.get("ids", {}).get("imdb")
        m = catalog.get(iid)
        if m and m["poster"] and m["votes"] >= 5000:
            pan_india_cands.append((m["votes"], iid))
    pan_india_cands.sort(key=lambda x: x[0], reverse=True)
    lanes_items["pan_india"] = [c[1] for c in pan_india_cands[:100]]

    # 3. Write lane_entries statements
    for lane_id, item_ids in lanes_items.items():
        statements.append(f"DELETE FROM lane_entries WHERE lane_id = '{lane_id}';")
        for rank, iid in enumerate(item_ids, start=1):
            lane_stmt = (
                f"INSERT INTO lane_entries (lane_id, imdb_id, rank, updated_at) "
                f"VALUES ('{lane_id}', '{iid}', {rank}, {now}) "
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
