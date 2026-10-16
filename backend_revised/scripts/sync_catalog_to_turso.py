import argparse
import json
import os
import sqlite3
import sys
import time
import urllib.request
from pathlib import Path

BATCH_SIZE = 100

def escape_sql(value: str | None) -> str:
    if value is None:
        return "NULL"
    escaped = value.replace("'", "''")
    return f"'{escaped}'"

def push_to_turso(statements: list[str], url: str, token: str):
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

def sync_catalog(catalog_dir: Path, db_path: Path | None = None):
    manifest_path = catalog_dir / "manifest.json"
    if not manifest_path.exists():
        print(f"[Skip] No manifest.json found at {manifest_path}.")
        return

    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    lanes = manifest.get("lanes", [])
    now = int(time.time())
    statements = []
    seen_movies = set()

    for lane_info in lanes:
        lane_id = lane_info.get("id")
        lane_file = lane_info.get("file")
        if not lane_id or not lane_file:
            continue

        lane_path = catalog_dir / lane_file
        if not lane_path.exists():
            continue

        with open(lane_path, "r", encoding="utf-8") as f:
            items = json.load(f)

        statements.append(f"UPDATE lane_entries SET today_rank = NULL WHERE lane_id = '{lane_id}';")

        for rank_idx, item in enumerate(items, start=1):
            imdb_id = item.get("imdb_id")
            if not imdb_id:
                continue

            tmdb_id = item.get("tmdb_id")
            tmdb_id_str = str(tmdb_id) if tmdb_id else "NULL"
            title = escape_sql(item.get("title", ""))
            
            release_date = item.get("release_date")
            if not release_date and item.get("year"):
                release_date = f"{item['year']}-01-01"
            release_date_str = escape_sql(release_date)

            poster_path = escape_sql(item.get("poster_path"))
            backdrop_path = escape_sql(item.get("backdrop_path"))
            overview = escape_sql(item.get("overview", ""))

            if imdb_id not in seen_movies:
                seen_movies.add(imdb_id)
                statements.append(
                    f"INSERT INTO movies (imdb_id, tmdb_id, title, release_date, poster_path, backdrop_path, overview, last_updated) "
                    f"VALUES ('{imdb_id}', {tmdb_id_str}, {title}, {release_date_str}, {poster_path}, {backdrop_path}, {overview}, {now}) "
                    f"ON CONFLICT(imdb_id) DO UPDATE SET "
                    f"poster_path = COALESCE(excluded.poster_path, movies.poster_path), "
                    f"backdrop_path = COALESCE(excluded.backdrop_path, movies.backdrop_path), "
                    f"overview = COALESCE(excluded.overview, movies.overview), "
                    f"last_updated = excluded.last_updated;"
                )

                rating = item.get("rating")
                votes = item.get("votes")
                year = item.get("year")
                if rating is not None and votes is not None:
                    year_str = str(year) if year else "NULL"
                    statements.append(
                        f"INSERT INTO imdb_titles (imdb_id, rating, votes, year, genres) "
                        f"VALUES ('{imdb_id}', {rating}, {votes}, {year_str}, NULL) "
                        f"ON CONFLICT(imdb_id) DO UPDATE SET rating = excluded.rating, votes = excluded.votes;"
                    )

            statements.append(
                f"INSERT INTO lane_entries (lane_id, imdb_id, today_rank, previous_rank, last_seen) "
                f"VALUES ('{lane_id}', '{imdb_id}', {rank_idx}, {rank_idx}, {now}) "
                f"ON CONFLICT(lane_id, imdb_id) DO UPDATE SET "
                f"previous_rank = CASE WHEN lane_entries.today_rank IS NOT NULL THEN lane_entries.today_rank ELSE lane_entries.previous_rank END, "
                f"today_rank = excluded.today_rank, "
                f"last_seen = excluded.last_seen;"
            )

    print(f"[Catalog Sync] Generated {len(statements)} SQL statements for {len(lanes)} lanes and {len(seen_movies)} movies.")

    turso_url = os.environ.get("TURSO_DATABASE_URL")
    turso_token = os.environ.get("TURSO_AUTH_TOKEN")

    if turso_url and turso_token:
        print(f"[Turso] Pushing {len(statements)} statements to Turso...")
        push_to_turso(statements, turso_url, turso_token)
        print("[Turso OK] Catalog synced to Turso successfully.")
    elif db_path and db_path.exists():
        print(f"[SQLite] Applying {len(statements)} statements to {db_path}...")
        apply_local_sqlite(statements, db_path)
        print("[SQLite OK] Catalog synced to local SQLite successfully.")
    else:
        out_sql = catalog_dir / "catalog_sync.sql"
        with open(out_sql, "w", encoding="utf-8") as f:
            f.write("\n".join(statements))
        print(f"[Output] Neither Turso nor local DB configured. Wrote to {out_sql}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Sync generated catalog JSONs to Turso")
    parser.add_argument("--catalog-dir", type=Path, default=Path("catalog"), help="Path to catalog JSON folder")
    parser.add_argument("--db-path", type=Path, default=None, help="Path to local SQLite database")
    args = parser.parse_args()
    sync_catalog(args.catalog_dir, args.db_path)
