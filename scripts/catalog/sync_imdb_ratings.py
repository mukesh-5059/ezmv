import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

import gzip
import time
import urllib.request
import sqlite3
from backend.config import DB_PATH
from backend.services.catalog import get_connection

IMDB_RATINGS_URL = "https://datasets.imdbws.com/title.ratings.tsv.gz"

def sync_imdb_ratings(db_path: Path = DB_PATH, chunk_size: int = 50000):
    start_time = time.time()
    print(f"Connecting to database at {db_path}...")
    conn = sqlite3.connect(db_path, timeout=30.0)
    
    conn.execute("PRAGMA journal_mode = WAL;")
    conn.execute("PRAGMA synchronous = NORMAL;")
    
    conn.execute("""
    CREATE TABLE IF NOT EXISTS imdb_ratings (
        imdb_id TEXT PRIMARY KEY,
        rating REAL NOT NULL,
        votes INTEGER NOT NULL
    );
    """)
    conn.commit()
    
    print(f"Downloading and streaming ratings from {IMDB_RATINGS_URL}...")
    req = urllib.request.Request(
        IMDB_RATINGS_URL,
        headers={"User-Agent": "Mozilla/5.0 (compatible; EzMV/1.0)"}
    )
    
    conn.execute("CREATE TEMP TABLE temp_ratings (imdb_id TEXT PRIMARY KEY, rating REAL, votes INTEGER);")
    
    count = 0
    batch = []
    
    with urllib.request.urlopen(req, timeout=60) as resp:
        with gzip.GzipFile(fileobj=resp) as gz:
            header = gz.readline()
            for line in gz:
                parts = line.decode("utf-8", errors="ignore").rstrip("\r\n").split("\t")
                if len(parts) >= 3:
                    try:
                        batch.append((parts[0], float(parts[1]), int(parts[2])))
                        count += 1
                    except ValueError:
                        continue
                
                if len(batch) >= chunk_size:
                    conn.executemany(
                        "INSERT INTO temp_ratings (imdb_id, rating, votes) VALUES (?, ?, ?);",
                        batch
                    )
                    batch.clear()
                    print(f"Ingested {count:,} ratings...", end="\r", flush=True)
            
            if batch:
                conn.executemany(
                    "INSERT INTO temp_ratings (imdb_id, rating, votes) VALUES (?, ?, ?);",
                    batch
                )
                batch.clear()
    
    print(f"\nFinalizing {count:,} rows into imdb_ratings...")
    conn.execute("DELETE FROM imdb_ratings;")
    conn.execute("INSERT INTO imdb_ratings (imdb_id, rating, votes) SELECT imdb_id, rating, votes FROM temp_ratings;")
    conn.execute("DROP TABLE temp_ratings;")
    
    conn.execute("""
    INSERT OR REPLACE INTO sync_meta (key, value)
    VALUES ('imdb_ratings_synced_at', ?);
    """, (str(int(time.time())),))
    
    conn.commit()
    conn.close()
    
    elapsed = time.time() - start_time
    print(f"Successfully synced {count:,} IMDb ratings in {elapsed:.2f}s.")

if __name__ == "__main__":
    sync_imdb_ratings()
