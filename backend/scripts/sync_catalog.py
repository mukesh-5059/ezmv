import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

import asyncio
import sqlite3
from backend.session import init_session, close_session
from backend.services.catalog import catalog_service, DB_PATH


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
    await init_session()
    print_stats("State BEFORE Sync")

    print("\n[>>] Starting IMDb sync cycle...")
    await catalog_service.sync_all_lanes()
    print("[OK] Sync cycle complete!")

    print("\n[>>] Fetching posters & overviews from TMDb...")
    await catalog_service._enrich_posters()
    print("[OK] Poster enrichment complete!")

    print_stats("State AFTER Sync")

    # Display latest tail entries for top_rated
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    latest_tail = conn.execute("""
        SELECT le.previous_rank, m.title, m.year, m.rating, m.votes, m.poster_path
        FROM lane_entries le
        JOIN movies m ON le.imdb_id = m.imdb_id
        WHERE le.lane_id = 'top_rated'
        ORDER BY le.previous_rank DESC
        LIMIT 5;
    """).fetchall()
    conn.close()

    print("\nLatest 5 crawled titles in 'top_rated' tail:")
    for item in reversed(latest_tail):
        print(f"  #{item['previous_rank']} | {item['title']} ({item['year']}) | Poster: {item['poster_path']}")

    await close_session()


if __name__ == "__main__":
    asyncio.run(main())
