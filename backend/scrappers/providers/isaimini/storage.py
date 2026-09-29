import os
import json
import sqlite3
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

DATA_DIR = Path(__file__).resolve().parents[3] / "data"
DB_PATH = DATA_DIR / "isaimini.db"
JSON_PATH = DATA_DIR / "isaimini.json"

def _get_connection() -> sqlite3.Connection:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH), timeout=15.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    _init_tables(conn)
    return conn

def _init_tables(conn: sqlite3.Connection):
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS catalog_entries (
        path TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        year INTEGER NOT NULL,
        page INTEGER DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE INDEX IF NOT EXISTS idx_cat_year ON catalog_entries(year);

    CREATE TABLE IF NOT EXISTS movie_path_cache (
        tmdb_id INTEGER PRIMARY KEY,
        path TEXT NOT NULL,
        page INTEGER DEFAULT 1,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS file_id_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tmdb_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        file_id TEXT NOT NULL,
        quality TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(tmdb_id, file_id, quality)
    );
    """)

def get_cached_domain() -> str | None:
    if not JSON_PATH.exists():
        return None
    try:
        with open(JSON_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data.get("domain")
    except Exception as e:
        logger.warning(f"[IsaiminiStorage] Error reading domain JSON: {e}")
        return None

def save_cached_domain(domain: str):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    try:
        data = {}
        if JSON_PATH.exists():
            with open(JSON_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
        data["domain"] = domain
        with open(JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        logger.warning(f"[IsaiminiStorage] Error saving domain JSON: {e}")

def get_cached_movie_path(tmdb_id: int) -> dict | None:
    try:
        with _get_connection() as conn:
            row = conn.execute(
                "SELECT path, page FROM movie_path_cache WHERE tmdb_id = ?", (tmdb_id,)
            ).fetchone()
            if row:
                return {"path": row["path"], "page": row["page"]}
    except Exception as e:
        logger.warning(f"[IsaiminiStorage] Error reading movie path for {tmdb_id}: {e}")
    return None

def save_cached_movie_path(tmdb_id: int, movie_path: str, page: int = 1):
    try:
        with _get_connection() as conn:
            conn.execute("""
                INSERT INTO movie_path_cache (tmdb_id, path, page, updated_at)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(tmdb_id) DO UPDATE SET
                    path = excluded.path,
                    page = excluded.page,
                    updated_at = CURRENT_TIMESTAMP
            """, (tmdb_id, movie_path, page))
            conn.commit()
    except Exception as e:
        logger.warning(f"[IsaiminiStorage] Error saving movie path for {tmdb_id}: {e}")

def log_file_id(tmdb_id: int, title: str, file_id: str, quality: str):
    try:
        with _get_connection() as conn:
            conn.execute("""
                INSERT OR IGNORE INTO file_id_log (tmdb_id, title, file_id, quality)
                VALUES (?, ?, ?, ?)
            """, (tmdb_id, title, file_id, quality))
            conn.commit()
    except Exception as e:
        logger.warning(f"[IsaiminiStorage] Error logging file ID: {e}")

def save_catalog_entries(entries: list[dict]):
    if not entries:
        return
    try:
        with _get_connection() as conn:
            conn.executemany("""
                INSERT INTO catalog_entries (path, title, year, page)
                VALUES (:path, :title, :year, :page)
                ON CONFLICT(path) DO UPDATE SET
                    title = excluded.title,
                    year = excluded.year,
                    page = excluded.page
            """, entries)
            conn.commit()
    except Exception as e:
        logger.warning(f"[IsaiminiStorage] Error saving catalog entries: {e}")

def get_catalog_by_year(year: int) -> list[dict]:
    try:
        with _get_connection() as conn:
            rows = conn.execute(
                "SELECT path, title, year, page FROM catalog_entries WHERE year = ?",
                (year,)
            ).fetchall()
            return [{"path": r["path"], "title": r["title"], "year": r["year"], "page": r["page"]} for r in rows]
    except Exception as e:
        logger.warning(f"[IsaiminiStorage] Error reading catalog for year {year}: {e}")
    return []
