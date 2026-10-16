import gzip
import os
import sqlite3
import sys
import time
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent.parent
REVISED_DIR = ROOT_DIR / "backend_revised"
SCHEMA_PATH = REVISED_DIR / "schema.sql"

RATINGS_TSV = ROOT_DIR / "title.ratings.tsv.gz"
BASICS_TSV = ROOT_DIR / "title.basics.tsv.gz"
OLD_CATALOG_DB = ROOT_DIR / "backend" / "data" / "catalog.db"
OUTPUT_DB = ROOT_DIR / "backend" / "data" / "catalog_normalized.db"

MIN_VOTES = 50
BATCH_SIZE = 10000

def seed_database():
    print(f"=== Starting Database Normalization & Seed ===")
    start_time = time.time()

    if not RATINGS_TSV.exists() or not BASICS_TSV.exists():
        print(f"[Error] Missing TSV files: {RATINGS_TSV} or {BASICS_TSV}")
        sys.exit(1)

    if OUTPUT_DB.exists():
        OUTPUT_DB.unlink()

    conn = sqlite3.connect(OUTPUT_DB)
    cur = conn.cursor()

    cur.execute("PRAGMA synchronous = OFF;")
    cur.execute("PRAGMA journal_mode = MEMORY;")

    print(f"[Schema] Initializing schema from {SCHEMA_PATH.name}...")
    with open(SCHEMA_PATH, "r", encoding="utf-8") as f:
        cur.executescript(f.read())

    # 1. Load Ratings (votes >= 50)
    print(f"[Ratings] Reading ratings from {RATINGS_TSV.name} (votes >= {MIN_VOTES})...")
    ratings_map = {}
    with gzip.open(RATINGS_TSV, "rt", encoding="utf-8", errors="replace") as f:
        f.readline() # header
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3:
                try:
                    votes = int(parts[2])
                    if votes >= MIN_VOTES:
                        ratings_map[parts[0]] = (float(parts[1]), votes)
                except ValueError:
                    continue
    print(f"[Ratings] Loaded {len(ratings_map):,} qualified titles.")

    # 2. Stream Basics & Insert into imdb_titles
    print(f"[Basics] Streaming {BASICS_TSV.name} and populating imdb_titles...")
    cur.execute("BEGIN TRANSACTION;")
    insert_sql = "INSERT INTO imdb_titles (imdb_id, rating, votes, year, genres) VALUES (?, ?, ?, ?, ?);"
    batch = []
    inserted_count = 0

    with gzip.open(BASICS_TSV, "rt", encoding="utf-8", errors="replace") as f:
        f.readline() # header
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 9:
                tconst = parts[0]
                if tconst in ratings_map:
                    rating, votes = ratings_map[tconst]
                    year_val = None
                    if parts[5] != "\\N":
                        try:
                            year_val = int(parts[5])
                        except ValueError:
                            pass
                    genres_val = parts[8] if parts[8] != "\\N" else None
                    batch.append((tconst, rating, votes, year_val, genres_val))
                    inserted_count += 1

                    if len(batch) >= BATCH_SIZE:
                        cur.executemany(insert_sql, batch)
                        batch.clear()

    if batch:
        cur.executemany(insert_sql, batch)
        batch.clear()
    conn.commit()
    print(f"[Basics OK] Inserted {inserted_count:,} titles into imdb_titles.")

    # 3. Migrate Catalog Movies & Lane Entries
    if OLD_CATALOG_DB.exists():
        print(f"[Catalog] Migrating existing curated catalog from {OLD_CATALOG_DB.name}...")
        old_conn = sqlite3.connect(OLD_CATALOG_DB)
        old_cur = old_conn.cursor()

        # Check existing movies columns
        old_cols = [c[1] for c in old_cur.execute("PRAGMA table_info(movies);").fetchall()]
        has_release_date = "release_date" in old_cols

        old_movies = old_cur.execute("SELECT * FROM movies;").fetchall()
        movie_rows = []
        for r in old_movies:
            row_dict = dict(zip(old_cols, r))
            imdb_id = row_dict.get("imdb_id")
            tmdb_id = row_dict.get("tmdb_id")
            title = row_dict.get("title")
            year = row_dict.get("year")
            release_date = row_dict.get("release_date") if has_release_date else (f"{year}-01-01" if year else None)
            poster_path = row_dict.get("poster_path")
            backdrop_path = row_dict.get("backdrop_path")
            overview = row_dict.get("overview")
            last_updated = row_dict.get("last_updated") or int(time.time())

            movie_rows.append((imdb_id, tmdb_id, title, release_date, poster_path, backdrop_path, overview, last_updated))

        cur.execute("BEGIN TRANSACTION;")
        cur.executemany(
            """
            INSERT OR REPLACE INTO movies (
                imdb_id, tmdb_id, title, release_date, poster_path, backdrop_path, overview, last_updated
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            movie_rows
        )
        conn.commit()
        print(f"[Catalog OK] Migrated {len(movie_rows):,} curated movies.")

        # Migrate lane_entries
        old_lane_entries = old_cur.execute(
            "SELECT lane_id, imdb_id, today_rank, previous_rank, last_seen FROM lane_entries;"
        ).fetchall()
        cur.execute("BEGIN TRANSACTION;")
        cur.executemany(
            """
            INSERT OR REPLACE INTO lane_entries (
                lane_id, imdb_id, today_rank, previous_rank, last_seen
            ) VALUES (?, ?, ?, ?, ?);
            """,
            old_lane_entries
        )
        conn.commit()
        print(f"[Lanes OK] Migrated {len(old_lane_entries):,} lane entries.")
        old_conn.close()

    print("[Optimize] Running VACUUM and ANALYZE...")
    cur.execute("PRAGMA journal_mode = WAL;")
    cur.execute("VACUUM;")
    cur.execute("ANALYZE;")
    conn.close()

    elapsed = time.time() - start_time
    size_mb = OUTPUT_DB.stat().st_size / (1024 * 1024)
    print(f"=== Database Seed Completed in {elapsed:.1f}s | Final Size: {size_mb:.2f} MB ===")
    print(f"Created: {OUTPUT_DB}")

if __name__ == "__main__":
    seed_database()
