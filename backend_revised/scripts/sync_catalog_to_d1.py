import argparse
import json
from pathlib import Path
import time

SCRIPT_DIR = Path(__file__).resolve().parent
REVISED_DIR = SCRIPT_DIR.parent
ROOT_DIR = REVISED_DIR.parent

def escape_sql(value: str | None) -> str:
    if value is None:
        return "NULL"
    escaped = str(value).replace("'", "''")
    return f"'{escaped}'"

def generate_sync_sql(catalog_dir: Path, out_sql_file: Path) -> int:
    manifest_path = catalog_dir / "manifest.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"manifest.json not found in {catalog_dir}")

    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    now = int(time.time())
    statements = []
    seen_movies = set()

    lanes = manifest.get("lanes", [])
    print(f"[Catalog] Found {len(lanes)} lanes in manifest.json")

    for lane in lanes:
        lane_id = lane.get("id")
        lane_file = lane.get("file")
        if not lane_id or not lane_file:
            continue

        file_path = catalog_dir / lane_file
        if not file_path.exists():
            print(f"[Warn] Lane file not found: {file_path}")
            continue

        with open(file_path, "r", encoding="utf-8") as f:
            items = json.load(f)

        print(f"[Lane: {lane_id}] Processing {len(items)} items...")
        if items:
            statements.append(f"DELETE FROM lane_entries WHERE lane_id = '{lane_id}';")

        for rank, item in enumerate(items, start=1):
            imdb_id = item.get("imdb_id")
            if not imdb_id or not imdb_id.startswith("tt"):
                continue

            tmdb_id = item.get("tmdb_id")
            tmdb_id_sql = str(int(tmdb_id)) if tmdb_id else "NULL"
            title = escape_sql(item.get("title", "Unknown"))
            year = item.get("year")
            year_sql = str(int(year)) if year else "NULL"
            release_date = escape_sql(f"{year}-01-01" if year else "")
            
            poster = item.get("poster_path") or ""
            if poster and not poster.startswith("http"):
                poster = f"https://image.tmdb.org/t/p/w500{poster}"
            poster_sql = escape_sql(poster)

            backdrop = item.get("backdrop_path") or ""
            if backdrop and not backdrop.startswith("http"):
                backdrop = f"https://image.tmdb.org/t/p/original{backdrop}"
            backdrop_sql = escape_sql(backdrop)

            overview = escape_sql(item.get("overview", ""))

            genre_ids = item.get("genre_ids", [])
            genres_list = [{"id": g, "name": ""} for g in genre_ids if isinstance(g, int)]
            genres_sql = escape_sql(json.dumps(genres_list))

            # 1. Movies table
            if imdb_id not in seen_movies:
                seen_movies.add(imdb_id)
                movie_stmt = (
                    f"INSERT INTO movies (imdb_id, tmdb_id, media_type, title, year, release_date, poster_path, backdrop_path, overview, runtime, genres, updated_at)\n"
                    f"VALUES ('{imdb_id}', {tmdb_id_sql}, 'movie', {title}, {year_sql}, {release_date}, {poster_sql}, {backdrop_sql}, {overview}, NULL, {genres_sql}, {now})\n"
                    f"ON CONFLICT(imdb_id) DO UPDATE SET\n"
                    f"  tmdb_id = COALESCE(excluded.tmdb_id, movies.tmdb_id),\n"
                    f"  title = excluded.title,\n"
                    f"  year = COALESCE(excluded.year, movies.year),\n"
                    f"  poster_path = CASE WHEN excluded.poster_path != '' THEN excluded.poster_path ELSE movies.poster_path END,\n"
                    f"  backdrop_path = CASE WHEN excluded.backdrop_path != '' THEN excluded.backdrop_path ELSE movies.backdrop_path END,\n"
                    f"  overview = CASE WHEN excluded.overview != '' THEN excluded.overview ELSE movies.overview END,\n"
                    f"  genres = excluded.genres,\n"
                    f"  updated_at = excluded.updated_at;"
                )
                statements.append(movie_stmt)

                # 2. Ratings table
                rating = float(item.get("rating") or 0.0)
                votes = int(item.get("votes") or 0)
                rating_stmt = (
                    f"INSERT INTO ratings (imdb_id, rating, votes, updated_at)\n"
                    f"VALUES ('{imdb_id}', {rating}, {votes}, {now})\n"
                    f"ON CONFLICT(imdb_id) DO UPDATE SET\n"
                    f"  rating = excluded.rating,\n"
                    f"  votes = excluded.votes,\n"
                    f"  updated_at = excluded.updated_at;"
                )
                statements.append(rating_stmt)

            # 3. Lane entries table
            lane_stmt = (
                f"INSERT INTO lane_entries (lane_id, imdb_id, rank, updated_at)\n"
                f"VALUES ('{lane_id}', '{imdb_id}', {rank}, {now})\n"
                f"ON CONFLICT(lane_id, imdb_id) DO UPDATE SET\n"
                f"  rank = excluded.rank,\n"
                f"  updated_at = excluded.updated_at;"
            )
            statements.append(lane_stmt)

    out_sql_file.parent.mkdir(parents=True, exist_ok=True)
    with open(out_sql_file, "w", encoding="utf-8") as f:
        f.write("\n\n".join(statements) + "\n")

    print(f"[Done] Generated {len(statements)} SQL statements for D1 -> {out_sql_file}")
    return len(statements)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert catalog JSONs to Cloudflare D1 SQL")
    parser.add_argument("--catalog-dir", type=Path, default=ROOT_DIR / "catalog", help="Directory containing catalog JSON files")
    parser.add_argument("--output", type=Path, default=REVISED_DIR / "sync_catalog.sql", help="Output .sql file path")
    args = parser.parse_args()

    generate_sync_sql(args.catalog_dir, args.output)
