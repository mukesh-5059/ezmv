import json
import sqlite3
import time
import urllib.request
from pathlib import Path

BASE_CDN_URL = "https://mukesh-5059.github.io/ezmv/catalog"
REVISED_DIR = Path(__file__).resolve().parent.parent

def find_d1_db_path() -> Path:
    d1_dir = REVISED_DIR / ".wrangler" / "state" / "v3" / "d1" / "miniflare-D1DatabaseObject"
    if not d1_dir.exists():
        raise FileNotFoundError(f"D1 state directory not found at {d1_dir}")
    
    candidates = [p for p in d1_dir.glob("*.sqlite") if p.name != "metadata.sqlite"]
    if not candidates:
        raise FileNotFoundError("No local D1 sqlite database file found. Run 'npx wrangler d1 execute' first.")
    return candidates[0]

def fetch_json(url: str):
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (compatible; CatalogSeeder/1.0)"}
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))

def seed_catalog():
    db_path = find_d1_db_path()
    print(f"Connecting to local D1 SQLite: {db_path.name}")
    
    conn = sqlite3.connect(db_path)
    now = int(time.time())

    manifest_url = f"{BASE_CDN_URL}/manifest.json"
    print(f"Fetching manifest from {manifest_url}...")
    manifest = fetch_json(manifest_url)
    
    total_unique_movies = set()
    lanes = manifest.get("lanes", [])

    for lane_info in lanes:
        lane_id = lane_info["id"]
        lane_file = lane_info["file"]
        lane_url = f"{BASE_CDN_URL}/{lane_file}"
        print(f"\n[Lane: {lane_id}] Downloading {lane_url}...")
        
        items = fetch_json(lane_url)
        print(f"[Lane: {lane_id}] Processing {len(items)} movies...")

        conn.execute("UPDATE lane_entries SET today_rank = NULL WHERE lane_id = ?;", (lane_id,))

        for rank_idx, item in enumerate(items, start=1):
            imdb_id = item["imdb_id"]
            total_unique_movies.add(imdb_id)
            genre_ids_json = json.dumps(item.get("genre_ids") or [])

            conn.execute(
                """
                INSERT INTO movies (
                    imdb_id, tmdb_id, title, year, rating, votes, meter_rank,
                    poster_path, backdrop_path, overview, genre_ids, first_seen, last_updated
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(imdb_id) DO UPDATE SET
                    tmdb_id = COALESCE(excluded.tmdb_id, movies.tmdb_id),
                    title = excluded.title,
                    year = COALESCE(excluded.year, movies.year),
                    rating = excluded.rating,
                    votes = excluded.votes,
                    meter_rank = excluded.meter_rank,
                    poster_path = COALESCE(excluded.poster_path, movies.poster_path),
                    backdrop_path = COALESCE(excluded.backdrop_path, movies.backdrop_path),
                    overview = COALESCE(excluded.overview, movies.overview),
                    genre_ids = excluded.genre_ids,
                    last_updated = excluded.last_updated;
                """,
                (
                    imdb_id,
                    item.get("tmdb_id"),
                    item.get("title", ""),
                    item.get("year"),
                    item.get("rating"),
                    item.get("votes", 0),
                    item.get("rank"),
                    item.get("poster_path"),
                    item.get("backdrop_path"),
                    item.get("overview", ""),
                    genre_ids_json,
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
        print(f"[Lane: {lane_id}] Successfully seeded {len(items)} items.")

    # Record manifest meta
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS sync_meta (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at INTEGER
        );
        """
    )
    conn.execute(
        """
        INSERT INTO sync_meta (key, value, updated_at) VALUES ('manifest_updated_at', ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
        """,
        (str(manifest.get("updated_at", now)), now),
    )
    conn.commit()

    # Print summary statistics
    movies_count = conn.execute("SELECT count(*) FROM movies;").fetchone()[0]
    lane_counts = conn.execute("SELECT lane_id, count(*) FROM lane_entries WHERE today_rank IS NOT NULL GROUP BY lane_id;").fetchall()
    conn.close()

    print("\n================== SEED SUMMARY ==================")
    print(f"Total Unique Movies in Catalog: {movies_count}")
    for lid, cnt in lane_counts:
        print(f"  - Lane '{lid}': {cnt} active titles")
    print("==================================================")

if __name__ == "__main__":
    seed_catalog()
