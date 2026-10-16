import argparse
import gzip
import os
import shutil
import sqlite3
import sys
import tempfile
import urllib.request
from pathlib import Path

RATINGS_URL = "https://datasets.imdbws.com/title.ratings.tsv.gz"
BASICS_URL = "https://datasets.imdbws.com/title.basics.tsv.gz"

CACHE_DIR = Path(".cache/imdb")
CURRENT_RATINGS_FILE = CACHE_DIR / "title.ratings.current.tsv.gz"
BASELINE_RATINGS_FILE = CACHE_DIR / "title.ratings.baseline.tsv.gz"

MIN_VOTES = 50
BATCH_SIZE = 100

def download_file(url: str, dest: Path):
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"[Download] Fetching {url} -> {dest}...")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (compatible; RatingsSync/1.0)"})
    with urllib.request.urlopen(req, timeout=120) as resp, open(dest, "wb") as out:
        shutil.copyfileobj(resp, out)
    print(f"[Download] Completed ({dest.stat().st_size / (1024 * 1024):.2f} MB)")

def load_ratings(file_path: Path) -> dict[str, tuple[float, int]]:
    ratings = {}
    if not file_path.exists():
        return ratings
    with gzip.open(file_path, "rt", encoding="utf-8", errors="replace") as f:
        header = f.readline()
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3:
                try:
                    votes = int(parts[2])
                    if votes >= MIN_VOTES:
                        ratings[parts[0]] = (float(parts[1]), votes)
                except ValueError:
                    continue
    return ratings

def lookup_basics(new_ids: set[str], basics_file: Path | None = None) -> dict[str, tuple[int | None, str | None]]:
    result = {}
    if not new_ids:
        return result
    
    temp_download = False
    if basics_file is None or not basics_file.exists():
        basics_file = CACHE_DIR / "title.basics.tsv.gz"
        download_file(BASICS_URL, basics_file)
        temp_download = True

    print(f"[Basics] Looking up {len(new_ids)} new titles in {basics_file}...")
    with gzip.open(basics_file, "rt", encoding="utf-8", errors="replace") as f:
        header = f.readline()
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 9:
                tconst = parts[0]
                if tconst in new_ids:
                    year_val = None
                    if parts[5] != "\\N":
                        try:
                            year_val = int(parts[5])
                        except ValueError:
                            pass
                    genres_val = parts[8] if parts[8] != "\\N" else None
                    result[tconst] = (year_val, genres_val)
                    if len(result) == len(new_ids):
                        break

    if temp_download and basics_file.exists():
        basics_file.unlink(missing_ok=True)
    return result

def push_to_turso(statements: list[str], url: str, token: str):
    import json
    import urllib.request

    http_url = url.replace("libsql://", "https://").rstrip("/") + "/v2/pipeline"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    for i in range(0, len(statements), BATCH_SIZE):
        batch = statements[i:i + BATCH_SIZE]
        requests_payload = [{"type": "execute", "stmt": {"sql": sql}} for sql in batch]
        payload = json.dumps({"requests": requests_payload}).encode("utf-8")
        req = urllib.request.Request(http_url, data=payload, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=30) as resp:
            if resp.status >= 400:
                print(f"[Turso ERROR] Batch failed with status {resp.status}")

def apply_local_sqlite(statements: list[str], db_path: Path):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("BEGIN TRANSACTION;")
    for stmt in statements:
        cur.execute(stmt)
    conn.commit()
    conn.close()

def sync_diff(db_path: Path | None = None):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    download_file(RATINGS_URL, CURRENT_RATINGS_FILE)

    print("[Diff] Loading baseline ratings...")
    baseline = load_ratings(BASELINE_RATINGS_FILE)
    print(f"[Diff] Baseline contains {len(baseline)} titles (>= {MIN_VOTES} votes)")

    print("[Diff] Loading current ratings...")
    current = load_ratings(CURRENT_RATINGS_FILE)
    print(f"[Diff] Current contains {len(current)} titles (>= {MIN_VOTES} votes)")

    if not baseline:
        print("[Diff] Baseline is empty (first run). Establishing baseline cache without generating diff.")
        shutil.copyfile(CURRENT_RATINGS_FILE, BASELINE_RATINGS_FILE)
        print("[Baseline] Baseline saved for next run.")
        return

    updates = []
    new_ids = set()

    for tconst, (rating, votes) in current.items():
        if tconst not in baseline:
            new_ids.add(tconst)
        else:
            old_rating, old_votes = baseline[tconst]
            if abs(rating - old_rating) >= 0.1 or (votes - old_votes) >= 50 or votes >= old_votes * 1.05:
                updates.append((tconst, rating, votes))

    print(f"[Diff] Found {len(updates)} rating updates and {len(new_ids)} new titles.")

    basics_info = lookup_basics(new_ids) if new_ids else {}

    sql_statements = []
    for tconst, rating, votes in updates:
        sql_statements.append(
            f"UPDATE imdb_titles SET rating = {rating}, votes = {votes} WHERE imdb_id = '{tconst}';"
        )

    for tconst in new_ids:
        rating, votes = current[tconst]
        year, genres = basics_info.get(tconst, (None, None))
        year_str = str(year) if year is not None else "NULL"
        genres_str = f"'{genres.replace(\"'\", \"''\")}'" if genres else "NULL"
        sql_statements.append(
            f"INSERT INTO imdb_titles (imdb_id, rating, votes, year, genres) "
            f"VALUES ('{tconst}', {rating}, {votes}, {year_str}, {genres_str}) "
            f"ON CONFLICT(imdb_id) DO UPDATE SET rating = {rating}, votes = {votes};"
        )

    print(f"[Sync] Generated {len(sql_statements)} total SQL statements.")

    turso_url = os.environ.get("TURSO_DATABASE_URL")
    turso_token = os.environ.get("TURSO_AUTH_TOKEN")

    if turso_url and turso_token:
        print(f"[Turso] Pushing {len(sql_statements)} statements to Turso...")
        push_to_turso(sql_statements, turso_url, turso_token)
        print("[Turso OK] Database sync completed successfully.")
    elif db_path and db_path.exists():
        print(f"[SQLite] Applying {len(sql_statements)} statements to {db_path}...")
        apply_local_sqlite(sql_statements, db_path)
        print("[SQLite OK] Local SQLite sync completed successfully.")
    else:
        out_sql = CACHE_DIR / "diff.sql"
        with open(out_sql, "w", encoding="utf-8") as f:
            f.write("\n".join(sql_statements))
        print(f"[Output] Neither Turso credentials nor local DB found. Wrote statements to {out_sql}")

    # Rotate baseline
    shutil.copyfile(CURRENT_RATINGS_FILE, BASELINE_RATINGS_FILE)
    print(f"[Baseline] Baseline rotated for next run.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Sync IMDb ratings daily diff")
    parser.add_argument("--db-path", type=Path, default=None, help="Path to local SQLite database")
    args = parser.parse_args()
    sync_diff(args.db_path)
