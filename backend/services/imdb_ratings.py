import sqlite3
from pathlib import Path
from backend.config import DB_PATH
from backend.services.catalog import get_connection

def calculate_weighted_score(
    rating: float,
    votes: int,
    min_votes: int = 1000,
    mean_rating: float = 6.5
) -> float:
    if votes <= 0 or rating <= 0:
        return 0.0
    return (votes / (votes + min_votes)) * rating + (min_votes / (votes + min_votes)) * mean_rating

def get_imdb_rating(imdb_id: str, db_path: Path = DB_PATH) -> tuple[float, int] | None:
    if not imdb_id:
        return None
    try:
        conn = get_connection(db_path)
        row = conn.execute(
            "SELECT rating, votes FROM imdb_ratings WHERE imdb_id = ? LIMIT 1;",
            (imdb_id,)
        ).fetchone()
        conn.close()
        if row:
            return float(row["rating"]), int(row["votes"])
    except Exception:
        pass
    return None

def get_imdb_ratings_batch(imdb_ids: list[str], db_path: Path = DB_PATH) -> dict[str, tuple[float, int]]:
    cleaned = [i for i in imdb_ids if i]
    if not cleaned:
        return {}
    results = {}
    try:
        conn = get_connection(db_path)
        placeholders = ",".join("?" for _ in cleaned)
        query = f"SELECT imdb_id, rating, votes FROM imdb_ratings WHERE imdb_id IN ({placeholders});"
        rows = conn.execute(query, cleaned).fetchall()
        for r in rows:
            results[r["imdb_id"]] = (float(r["rating"]), int(r["votes"]))
        conn.close()
    except Exception:
        pass
    return results
