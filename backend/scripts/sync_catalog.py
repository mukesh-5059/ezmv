import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

import asyncio
import json
import logging
import time
from backend.session import init_session, close_session, get_session
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

LANES_CONFIG = {
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

def load_existing_catalog(output_dir: Path) -> tuple[dict[str, dict], dict[str, list[dict]], dict[str, str]]:
    """Loads existing master movie cache, lane movies, and cursors from disk if available."""
    master_movies: dict[str, dict] = {}
    lanes_data: dict[str, list[dict]] = {}
    cursors: dict[str, str] = {}

    manifest_path = output_dir / "manifest.json"
    if manifest_path.exists():
        try:
            with open(manifest_path, "r", encoding="utf-8") as f:
                manifest = json.load(f)
                cursors = manifest.get("cursors", {})
        except Exception as e:
            print(f"[Cache Warn] Error reading manifest.json: {e}")

    for lane_id in LANES_CONFIG:
        lane_file = output_dir / f"{lane_id}.json"
        if lane_file.exists():
            try:
                with open(lane_file, "r", encoding="utf-8") as f:
                    items = json.load(f)
                    lanes_data[lane_id] = items
                    for item in items:
                        imdb_id = item.get("imdb_id")
                        if imdb_id:
                            master_movies[imdb_id] = item
            except Exception as e:
                print(f"[Cache Warn] Error reading {lane_file}: {e}")

    print(f"[Cache OK] Loaded {len(master_movies)} existing enriched movies from {output_dir}")
    return master_movies, lanes_data, cursors

async def enrich_missing_metadata(movies_list: list[dict], master_movies: dict[str, dict]):
    """Enriches movies missing poster/genre info from TMDb in parallel."""
    to_enrich = []
    for m in movies_list:
        imdb_id = m["imdb_id"]
        cached = master_movies.get(imdb_id)
        if not cached or not cached.get("poster_path") or not cached.get("genre_ids"):
            to_enrich.append(m)

    if not to_enrich:
        print("[TMDb OK] All movies in lane already enriched with poster and genre metadata.")
        return

    print(f"[TMDb] Enriching {len(to_enrich)} movies missing TMDb metadata...")
    sem = asyncio.Semaphore(10)

    async def fetch_tmdb(movie: dict):
        imdb_id = movie["imdb_id"]
        async with sem:
            try:
                tmdb_info = await tmdb_client.find_movie_by_imdb_id(imdb_id)
                if tmdb_info:
                    movie["tmdb_id"] = tmdb_info.get("id")
                    movie["poster_path"] = tmdb_info.get("poster_path")
                    movie["backdrop_path"] = tmdb_info.get("backdrop_path")
                    movie["overview"] = tmdb_info.get("overview") or ""
                    movie["genre_ids"] = tmdb_info.get("genre_ids") or []
            except Exception:
                pass

    await asyncio.gather(*(fetch_tmdb(m) for m in to_enrich))
    for m in to_enrich:
        master_movies[m["imdb_id"]] = m
    print(f"[TMDb OK] Enrichment complete.")

async def enrich_actors(output_file: Path) -> list[dict]:
    """Enriches curated actor list with TMDb HD profile avatars."""
    actors_cfg_path = ROOT_DIR / "config" / "actors.json"
    if not actors_cfg_path.exists():
        actors_cfg_path = ROOT_DIR / "backend" / "data" / "actors.json"
    if not actors_cfg_path.exists():
        print(f"[Actors] Actors config not found at config/actors.json. Skipping.")
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

async def sync_catalog_json(output_dir: str = "catalog"):
    out_path = Path(output_dir).resolve()
    out_path.mkdir(parents=True, exist_ok=True)
    now = int(time.time())

    master_movies, existing_lanes, saved_cursors = load_existing_catalog(out_path)
    new_cursors: dict[str, str] = dict(saved_cursors)
    manifest_lanes = []
    total_unique_movies = set()

    for lane_id, cfg in LANES_CONFIG.items():
        print(f"\n[Lane] Syncing '{lane_id}' ({cfg['title']})...")
        max_depth = cfg.get("max_depth", 500)

        # 1. Fetch Top 50 from IMDb GraphQL
        top50, top_cursor = await fetch_graphql_lane(
            sort_by=cfg["sort_by"],
            sort_order=cfg["sort_order"],
            extra_constraints=cfg["constraints"],
            limit=50,
        )

        lane_items: list[dict] = []
        seen_imdb_ids: set[str] = set()

        for idx, item in enumerate(top50, start=1):
            imdb_id = item["imdb_id"]
            seen_imdb_ids.add(imdb_id)
            cached = master_movies.get(imdb_id, {})
            merged = {
                "imdb_id": imdb_id,
                "tmdb_id": cached.get("tmdb_id"),
                "title": item["title"],
                "year": item["year"] or cached.get("year"),
                "rating": item["rating"] or cached.get("rating"),
                "votes": item["votes"] or cached.get("votes"),
                "rank": idx,
                "poster_path": cached.get("poster_path"),
                "backdrop_path": cached.get("backdrop_path"),
                "overview": cached.get("overview", ""),
                "genre_ids": cached.get("genre_ids", []),
            }
            lane_items.append(merged)

        # 2. Deep Crawler / Pagination up to max_depth
        if lane_id == "trending" and max_depth > 50 and top_cursor:
            curr_cursor = top_cursor
            while len(lane_items) < max_depth and curr_cursor:
                more_items, next_cursor = await fetch_graphql_lane(
                    sort_by=cfg["sort_by"],
                    sort_order=cfg["sort_order"],
                    extra_constraints=cfg["constraints"],
                    limit=50,
                    after=curr_cursor,
                )
                if not more_items:
                    break
                for m in more_items:
                    if m["imdb_id"] not in seen_imdb_ids:
                        seen_imdb_ids.add(m["imdb_id"])
                        c = master_movies.get(m["imdb_id"], {})
                        lane_items.append({
                            "imdb_id": m["imdb_id"],
                            "tmdb_id": c.get("tmdb_id"),
                            "title": m["title"],
                            "year": m["year"] or c.get("year"),
                            "rating": m["rating"] or c.get("rating"),
                            "votes": m["votes"] or c.get("votes"),
                            "rank": len(lane_items) + 1,
                            "poster_path": c.get("poster_path"),
                            "backdrop_path": c.get("backdrop_path"),
                            "overview": c.get("overview", ""),
                            "genre_ids": c.get("genre_ids", []),
                        })
                curr_cursor = next_cursor
        elif cfg.get("deep_crawler"):
            # Merge existing historical tail
            existing_lane = existing_lanes.get(lane_id, [])
            for old_item in existing_lane[50:]:
                if old_item["imdb_id"] not in seen_imdb_ids and len(lane_items) < max_depth:
                    seen_imdb_ids.add(old_item["imdb_id"])
                    old_item["rank"] = len(lane_items) + 1
                    lane_items.append(old_item)

            active_cursor = saved_cursors.get(lane_id) or top_cursor
            if len(lane_items) < max_depth and active_cursor:
                try:
                    more_items, new_cursor = await fetch_graphql_lane(
                        sort_by=cfg["sort_by"],
                        sort_order=cfg["sort_order"],
                        extra_constraints=cfg["constraints"],
                        limit=50,
                        after=active_cursor,
                    )
                    if more_items:
                        for m in more_items:
                            if m["imdb_id"] not in seen_imdb_ids and len(lane_items) < max_depth:
                                seen_imdb_ids.add(m["imdb_id"])
                                c = master_movies.get(m["imdb_id"], {})
                                lane_items.append({
                                    "imdb_id": m["imdb_id"],
                                    "tmdb_id": c.get("tmdb_id"),
                                    "title": m["title"],
                                    "year": m["year"] or c.get("year"),
                                    "rating": m["rating"] or c.get("rating"),
                                    "votes": m["votes"] or c.get("votes"),
                                    "rank": len(lane_items) + 1,
                                    "poster_path": c.get("poster_path"),
                                    "backdrop_path": c.get("backdrop_path"),
                                    "overview": c.get("overview", ""),
                                    "genre_ids": c.get("genre_ids", []),
                                })
                        if new_cursor:
                            new_cursors[lane_id] = new_cursor
                except Exception as e:
                    print(f"  [Tail Warn] Error expanding '{lane_id}': {e}")

        # 3. Enrich missing posters & genres with TMDb
        await enrich_missing_metadata(lane_items, master_movies)

        # 4. Filter only movies with valid poster_path and write lane file
        valid_lane_movies = [m for m in lane_items if m.get("poster_path")]
        for m in valid_lane_movies:
            total_unique_movies.add(m["imdb_id"])

        lane_file = f"{lane_id}.json"
        with open(out_path / lane_file, "w", encoding="utf-8") as f:
            json.dump(valid_lane_movies, f, separators=(",", ":"), ensure_ascii=False)

        manifest_lanes.append({
            "id": lane_id,
            "title": cfg["title"],
            "file": lane_file,
            "count": len(valid_lane_movies),
        })
        print(f"[Lane OK] Exported {len(valid_lane_movies)} movies -> {lane_file}")

    # 5. Enrich & Export Actors
    actors_data = await enrich_actors(out_path / "actors.json")

    # 6. Export manifest.json
    manifest = {
        "updated_at": now,
        "total_unique_movies": len(total_unique_movies),
        "cursors": new_cursors,
        "lanes": manifest_lanes,
        "actors_file": "actors.json" if actors_data else None,
    }
    with open(out_path / "manifest.json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    print(f"\n[Manifest OK] Successfully generated catalog manifest in {out_path} ({len(total_unique_movies)} total movies)")

async def main():
    import argparse
    parser = argparse.ArgumentParser(description="IMDb & TMDb 100% JSON Catalog Pipeline")
    parser.add_argument("--export-dir", type=str, default="catalog", help="Directory to export JSON files")
    args = parser.parse_args()

    await init_session()
    print(f"=== Starting 100% JSON Catalog Pipeline (Output: {args.export_dir}) ===")
    await sync_catalog_json(args.export_dir)
    print("=== Catalog Pipeline Finished Successfully ===")
    await close_session()

if __name__ == "__main__":
    asyncio.run(main())
