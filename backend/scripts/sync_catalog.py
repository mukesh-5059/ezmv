import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

import asyncio
import json
import logging
import sqlite3
import time
from backend.config import DB_PATH
from backend.session import init_session, close_session, get_session
from backend.services.catalog import get_connection, init_db
from backend.services.tmdb import tmdb_client

logger = logging.getLogger(__name__)

GRAPHQL_URL = "https://api.graphql.imdb.com/"

GRAPHQL_HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/graphql+json, application/json",
    "Origin": "https://www.imdb.com",
    "Referer": "https://www.imdb.com/",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "x-imdb-client-name": "imdb-web-next",
}

BASE_QUERY = """
query GetMovies($first: Int!, $after: String, $sort: AdvancedTitleSearchSort!, $constraints: AdvancedTitleSearchConstraints!) {
  advancedTitleSearch(
    first: $first
    after: $after
    sort: $sort
    constraints: $constraints
  ) {
    pageInfo {
      hasNextPage
      endCursor
    }
    edges {
      node {
        title {
          id
          titleText { text }
          releaseYear { year }
          ratingsSummary {
            aggregateRating
            voteCount
          }
          meterRanking {
            currentRank
          }
        }
      }
    }
  }
}
"""

LANES_SYNC_CONFIG = {
    "trending": {
        "title": "New & Trending Tamil",
        "sort_by": "POPULARITY",
        "sort_order": "ASC",
        "constraints": {},
        "deep_crawler": False,
        "max_depth": 150,
    },
    "comedy": {
        "title": "Popular Tamil Comedy",
        "sort_by": "POPULARITY",
        "sort_order": "ASC",
        "constraints": {"genreConstraint": {"anyGenreIds": ["Comedy"]}},
        "deep_crawler": True,
        "max_depth": 400,
    },
    "top_rated": {
        "title": "All-Time Most Watched",
        "sort_by": "USER_RATING_COUNT",
        "sort_order": "DESC",
        "constraints": {},
        "deep_crawler": True,
        "max_depth": 500,
    },
    "box_office": {
        "title": "Record-Breaking Box Office",
        "sort_by": "BOX_OFFICE_GROSS_DOMESTIC",
        "sort_order": "DESC",
        "constraints": {},
        "deep_crawler": True,
        "max_depth": 500,
    },
}

async def fetch_graphql_lane(
    sort_by: str,
    sort_order: str,
    extra_constraints: dict,
    limit: int = 50,
    after: str | None = None,
) -> tuple[list[dict], str | None]:
    constraints = {
        "titleTypeConstraint": {"anyTitleTypeIds": ["movie"]},
        "languageConstraint": {"anyPrimaryLanguages": ["ta"]},
    }
    if extra_constraints:
        constraints.update(extra_constraints)

    payload = {
        "query": BASE_QUERY,
        "variables": {
            "first": limit,
            "after": after,
            "sort": {"sortBy": sort_by, "sortOrder": sort_order},
            "constraints": constraints,
        },
    }

    session = get_session()
    resp = await session.post(
        GRAPHQL_URL,
        headers=GRAPHQL_HEADERS,
        data=json.dumps(payload),
        impersonate="chrome",
    )
    resp.raise_for_status()
    data = resp.json()

    search_result = data.get("data", {}).get("advancedTitleSearch", {})
    edges = search_result.get("edges", [])
    page_info = search_result.get("pageInfo", {})
    end_cursor = page_info.get("endCursor")

    movies = []
    for edge in edges:
        node = edge.get("node", {}).get("title", {})
        if not node:
            continue

        imdb_id = node.get("id")
        title_text = node.get("titleText", {}).get("text") if node.get("titleText") else None
        release_year = node.get("releaseYear", {}).get("year") if node.get("releaseYear") else None
        meter_rank = node.get("meterRanking", {}).get("currentRank") if node.get("meterRanking") else None
        ratings_summary = node.get("ratingsSummary", {}) or {}
        rating = ratings_summary.get("aggregateRating")
        votes = ratings_summary.get("voteCount", 0)

        if imdb_id and title_text:
            movies.append({
                "imdb_id": imdb_id,
                "title": title_text,
                "year": release_year,
                "rating": rating,
                "votes": votes,
                "meter_rank": meter_rank,
            })
    return movies, end_cursor

def merge_lane_data(conn: sqlite3.Connection, lane_id: str, items: list[dict], now: int):
    conn.execute(
        "UPDATE lane_entries SET today_rank = NULL WHERE lane_id = ?;",
        (lane_id,),
    )
    for rank_idx, item in enumerate(items, start=1):
        imdb_id = item["imdb_id"]
        conn.execute(
            """
            INSERT INTO movies (imdb_id, title, year, rating, votes, meter_rank, first_seen, last_updated)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(imdb_id) DO UPDATE SET
                title = excluded.title,
                year = COALESCE(excluded.year, movies.year),
                rating = excluded.rating,
                votes = excluded.votes,
                meter_rank = excluded.meter_rank,
                last_updated = excluded.last_updated;
            """,
            (
                imdb_id,
                item["title"],
                item["year"],
                item["rating"],
                item["votes"],
                item["meter_rank"],
                now,
                now,
            ),
        )
        conn.execute(
            """
            INSERT INTO lane_entries (lane_id, imdb_id, today_rank, previous_rank, last_seen)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(lane_id, imdb_id) DO UPDATE SET
                today_rank = excluded.today_rank,
                previous_rank = excluded.previous_rank,
                last_seen = excluded.last_seen;
            """,
            (lane_id, imdb_id, rank_idx, rank_idx, now),
        )
    conn.commit()

def merge_deep_tail(conn: sqlite3.Connection, lane_id: str, items: list[dict], starting_rank: int, now: int):
    for idx, item in enumerate(items, start=1):
        imdb_id = item["imdb_id"]
        assigned_rank = starting_rank + idx
        conn.execute(
            """
            INSERT INTO movies (imdb_id, title, year, rating, votes, meter_rank, first_seen, last_updated)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(imdb_id) DO UPDATE SET
                title = excluded.title,
                year = COALESCE(excluded.year, movies.year),
                rating = excluded.rating,
                votes = excluded.votes,
                meter_rank = excluded.meter_rank,
                last_updated = excluded.last_updated;
            """,
            (
                imdb_id,
                item["title"],
                item["year"],
                item["rating"],
                item["votes"],
                item["meter_rank"],
                now,
                now,
            ),
        )
        conn.execute(
            """
            INSERT INTO lane_entries (lane_id, imdb_id, today_rank, previous_rank, last_seen)
            VALUES (?, ?, NULL, ?, ?)
            ON CONFLICT(lane_id, imdb_id) DO UPDATE SET
                previous_rank = COALESCE(lane_entries.previous_rank, excluded.previous_rank),
                last_seen = excluded.last_seen;
            """,
            (lane_id, imdb_id, assigned_rank, now),
        )
    conn.commit()

async def sync_deep_tail(conn: sqlite3.Connection, lane_id: str, cfg: dict, top50_cursor: str | None, now: int):
    cursor_row = conn.execute(
        "SELECT value FROM sync_meta WHERE key = ?;",
        (f"{lane_id}_tail_cursor",),
    ).fetchone()
    rank_row = conn.execute(
        "SELECT value FROM sync_meta WHERE key = ?;",
        (f"{lane_id}_tail_rank",),
    ).fetchone()

    stored_cursor = cursor_row["value"] if cursor_row else None
    current_tail_rank = int(rank_row["value"]) if rank_row else 50
    active_cursor = stored_cursor or top50_cursor

    max_depth = cfg.get("max_depth", 500)
    if current_tail_rank >= max_depth:
        print(f"  [Tail Cap] Lane '{lane_id}' reached max_depth ({current_tail_rank}/{max_depth}). Skipping deep crawl.")
        return

    if not active_cursor:
        return

    print(f"  [Tail] Lane '{lane_id}' starting at rank {current_tail_rank} (cap: {max_depth})...")
    try:
        items, new_cursor = await fetch_graphql_lane(
            sort_by=cfg["sort_by"],
            sort_order=cfg["sort_order"],
            extra_constraints=cfg["constraints"],
            limit=50,
            after=active_cursor,
        )
    except Exception as e:
        print(f"  [Tail Warn] Resetting to top 50 cursor for '{lane_id}': {e}")
        items, new_cursor = await fetch_graphql_lane(
            sort_by=cfg["sort_by"],
            sort_order=cfg["sort_order"],
            extra_constraints=cfg["constraints"],
            limit=50,
            after=top50_cursor,
        )
        current_tail_rank = 50

    if items:
        merge_deep_tail(conn, lane_id, items, current_tail_rank, now)
        next_rank = current_tail_rank + len(items)
        if new_cursor:
            conn.execute(
                "INSERT INTO sync_meta (key, value, updated_at) VALUES (?, ?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;",
                (f"{lane_id}_tail_cursor", new_cursor, now),
            )
        conn.execute(
            "INSERT INTO sync_meta (key, value, updated_at) VALUES (?, ?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;",
            (f"{lane_id}_tail_rank", str(next_rank), now),
        )
        conn.commit()
        print(f"  [Tail OK] Lane '{lane_id}' expanded from {current_tail_rank} to {next_rank}.")

async def sync_all_lanes():
    print("Starting IMDb catalog synchronization...")
    now = int(time.time())

    with get_connection() as conn:
        init_db(conn)
        for lane_id, cfg in LANES_SYNC_CONFIG.items():
            try:
                print(f"[Lane] Fetching Top 50 for '{lane_id}' ({cfg['title']})...")
                items, end_cursor = await fetch_graphql_lane(
                    sort_by=cfg["sort_by"],
                    sort_order=cfg["sort_order"],
                    extra_constraints=cfg["constraints"],
                    limit=50,
                )
                merge_lane_data(conn, lane_id, items, now)
                print(f"[Lane OK] '{lane_id}' Top 50 merged ({len(items)} items).")

                # For trending: if max_depth > 50, fetch additional pages up to max_depth
                if lane_id == "trending" and cfg.get("max_depth", 50) > 50 and end_cursor:
                    curr_cursor = end_cursor
                    current_count = len(items)
                    target = cfg.get("max_depth", 150)
                    while current_count < target and curr_cursor:
                        more_items, next_cursor = await fetch_graphql_lane(
                            sort_by=cfg["sort_by"],
                            sort_order=cfg["sort_order"],
                            extra_constraints=cfg["constraints"],
                            limit=50,
                            after=curr_cursor,
                        )
                        if not more_items:
                            break
                        merge_deep_tail(conn, lane_id, more_items, current_count, now)
                        current_count += len(more_items)
                        curr_cursor = next_cursor
                    print(f"[Lane OK] '{lane_id}' expanded to {current_count} trending items.")

                if cfg.get("deep_crawler"):
                    await sync_deep_tail(conn, lane_id, cfg, end_cursor, now)
            except Exception as e:
                print(f"[Lane Error] Error syncing '{lane_id}': {e}")

        conn.execute(
            "INSERT INTO sync_meta (key, value, updated_at) VALUES ('last_sync', 'success', ?) "
            "ON CONFLICT(key) DO UPDATE SET updated_at = excluded.updated_at;",
            (now,),
        )
        conn.commit()
    print("IMDb catalog synchronization complete.")

async def enrich_posters():
    with get_connection() as conn:
        rows = conn.execute(
            "SELECT imdb_id FROM movies WHERE poster_path IS NULL OR genre_ids IS NULL LIMIT 250;"
        ).fetchall()

    if not rows:
        return

    print(f"Enriching {len(rows)} movies with TMDB posters/backdrops/genres...")
    sem = asyncio.Semaphore(10)

    async def fetch_one(imdb_id: str):
        async with sem:
            try:
                tmdb_info = await tmdb_client.find_movie_by_imdb_id(imdb_id)
                if tmdb_info:
                    genre_list = tmdb_info.get("genre_ids") or []
                    genres_str = ",".join(str(g) for g in genre_list) if genre_list else ""
                    return (
                        imdb_id,
                        tmdb_info.get("id"),
                        tmdb_info.get("poster_path") or "",
                        tmdb_info.get("backdrop_path") or "",
                        tmdb_info.get("overview") or "",
                        genres_str,
                    )
                else:
                    return (imdb_id, None, "", "", "", "")
            except Exception:
                pass
            return None

    results = await asyncio.gather(*(fetch_one(r["imdb_id"]) for r in rows))
    updates = [u for u in results if u is not None]

    if updates:
        with get_connection() as conn:
            conn.executemany(
                """
                UPDATE movies SET
                    tmdb_id = COALESCE(?, tmdb_id),
                    poster_path = ?,
                    backdrop_path = ?,
                    overview = ?,
                    genre_ids = ?
                WHERE imdb_id = ?;
                """,
                [(u[1], u[2], u[3], u[4], u[5], u[0]) for u in updates],
            )
            conn.commit()
        print(f"Successfully enriched {len(updates)} movies with TMDB metadata.")

async def enrich_actors(output_file: Path) -> list[dict]:
    actors_cfg_path = ROOT_DIR / "config" / "actors.json"
    if not actors_cfg_path.exists():
        actors_cfg_path = ROOT_DIR / "backend" / "data" / "actors.json"
    if not actors_cfg_path.exists():
        print(f"[Actors] Actors config not found at config/actors.json or backend/data/actors.json. Skipping actors export.")
        return []

    with open(actors_cfg_path, "r", encoding="utf-8") as f:
        actors_list = json.load(f)

    print(f"[Actors] Enriching {len(actors_list)} curated actors from TMDb...")
    sem = asyncio.Semaphore(10)

    async def fetch_actor(actor_entry: dict):
        a_id = actor_entry.get("id")
        fallback_name = actor_entry.get("name", "")
        async with sem:
            try:
                details = await tmdb_client.get_person_details(a_id)
                if details:
                    return {
                        "id": details.get("id", a_id),
                        "name": details.get("name") or fallback_name,
                        "profile_path": details.get("profile_path"),
                        "known_for_department": details.get("known_for_department", "Acting"),
                    }
            except Exception as e:
                print(f"[Actors Warn] Failed to fetch actor {a_id}: {e}")
            return {
                "id": a_id,
                "name": fallback_name,
                "profile_path": None,
                "known_for_department": "Acting",
            }

    enriched = await asyncio.gather(*(fetch_actor(a) for a in actors_list))
    valid = [a for a in enriched if a and a.get("name")]

    output_file.parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(valid, f, indent=2, ensure_ascii=False)
    print(f"[Actors OK] Exported {len(valid)} actors to {output_file}.")
    return valid

async def export_catalog_json(output_dir: str = "catalog"):
    out_path = Path(output_dir).resolve()
    out_path.mkdir(parents=True, exist_ok=True)
    now = int(time.time())

    from backend.services.catalog import CatalogService
    catalog_service = CatalogService()

    manifest_lanes = []
    total_exported = 0

    for lane_id, cfg in LANES_SYNC_CONFIG.items():
        max_depth = cfg.get("max_depth", 500)
        movies = catalog_service.get_lane_movies(lane_id, limit=max_depth)

        valid_movies = []
        for idx, m in enumerate(movies, start=1):
            if not m.get("poster_path"):
                continue
            valid_movies.append({
                "imdb_id": m.get("imdb_id"),
                "tmdb_id": m.get("tmdb_id"),
                "title": m.get("title"),
                "year": m.get("year"),
                "rating": m.get("rating"),
                "votes": m.get("votes"),
                "rank": m.get("today_rank") or m.get("previous_rank") or idx,
                "poster_path": m.get("poster_path"),
                "backdrop_path": m.get("backdrop_path"),
                "overview": m.get("overview"),
                "genre_ids": m.get("genre_ids", []),
            })

        lane_file = f"{lane_id}.json"
        lane_json_path = out_path / lane_file
        with open(lane_json_path, "w", encoding="utf-8") as f:
            json.dump(valid_movies, f, separators=(",", ":"), ensure_ascii=False)

        manifest_lanes.append({
            "id": lane_id,
            "title": cfg["title"],
            "file": lane_file,
            "count": len(valid_movies),
        })
        total_exported += len(valid_movies)
        print(f"[Export OK] {lane_id}: {len(valid_movies)} movies -> {lane_file}")

    actors_file = out_path / "actors.json"
    actors_data = await enrich_actors(actors_file)

    manifest = {
        "updated_at": now,
        "total_movies": total_exported,
        "lanes": manifest_lanes,
        "actors_file": "actors.json" if actors_data else None,
    }
    with open(out_path / "manifest.json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    print(f"[Manifest OK] Successfully generated manifest.json in {out_path}")

def print_stats(label: str):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    movies_count = conn.execute("SELECT COUNT(*) AS c FROM movies;").fetchone()["c"]
    lanes = conn.execute("SELECT lane_id, COUNT(*) AS c FROM lane_entries GROUP BY lane_id;").fetchall()
    meta = conn.execute("SELECT key, value FROM sync_meta;").fetchall()
    conn.close()

    print(f"\n--- {label} ---")
    print(f"Total Unique Movies in Master Catalog: {movies_count}")
    print("Lane Counts:", {r["lane_id"]: r["c"] for r in lanes})
    print("Crawler Positions:", {r["key"]: r["value"] for r in meta if "cursor" not in r["key"]})

async def main():
    import argparse
    parser = argparse.ArgumentParser(description="IMDb & TMDb Catalog Sync & JSON Pipeline")
    parser.add_argument("--export-dir", type=str, default="catalog", help="Directory to export JSON files")
    parser.add_argument("--export-only", action="store_true", help="Skip sync and only export JSON from current DB")
    args = parser.parse_args()

    await init_session()

    if not args.export_only:
        print_stats("State BEFORE Sync")

        print("\n[>>] Starting IMDb sync cycle...")
        await sync_all_lanes()
        print("[OK] Sync cycle complete!")

        print("\n[>>] Fetching posters & overviews & genres from TMDb...")
        await enrich_posters()
        print("[OK] Metadata enrichment complete!")

        print_stats("State AFTER Sync")

    print(f"\n[>>] Exporting JSON files to '{args.export_dir}'...")
    await export_catalog_json(args.export_dir)
    print("[OK] Catalog JSON pipeline export complete!")

    await close_session()

if __name__ == "__main__":
    asyncio.run(main())
