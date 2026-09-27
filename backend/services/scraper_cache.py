import json
import logging
import sqlite3
from datetime import datetime
from backend.config import DATA_DIR, DB_PATH

logger = logging.getLogger(__name__)

DOMAIN_CACHE_FILE = DATA_DIR / "domain_cache.json"
PATH_CACHE_FILE = DATA_DIR / "movie_path_cache.json"
FILE_ID_LOG_FILE = DATA_DIR / "file_id_log.json"

_initialized = False

def _get_connection() -> sqlite3.Connection:
    global _initialized
    conn = sqlite3.connect(DB_PATH, timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode = WAL;")
    conn.execute("PRAGMA busy_timeout = 5000;")
    if not _initialized:
        _init_cache_tables(conn)
        _initialized = True
    return conn

def _init_cache_tables(conn: sqlite3.Connection):
    conn.execute("""
    CREATE TABLE IF NOT EXISTS domain_cache (
        key TEXT PRIMARY KEY,
        domain TEXT NOT NULL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    """)
    conn.execute("""
    CREATE TABLE IF NOT EXISTS movie_path_cache (
        tmdb_id INTEGER PRIMARY KEY,
        path TEXT NOT NULL,
        page INTEGER DEFAULT 1,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    """)
    conn.execute("""
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
    conn.commit()
    _migrate_json_files(conn)

def _migrate_json_files(conn: sqlite3.Connection):
    try:
        if DOMAIN_CACHE_FILE.exists():
            with open(DOMAIN_CACHE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            for key, domain in data.items():
                conn.execute(
                    "INSERT OR REPLACE INTO domain_cache (key, domain) VALUES (?, ?)",
                    (key, domain)
                )
            conn.commit()
            DOMAIN_CACHE_FILE.unlink()
            logger.info("Migrated domain_cache.json into SQLite")
    except Exception as e:
        logger.warning(f"Error migrating domain_cache.json: {e}")

    try:
        if PATH_CACHE_FILE.exists():
            with open(PATH_CACHE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            for tmdb_id_str, val in data.items():
                tmdb_id = int(tmdb_id_str)
                path = val.get("path") if isinstance(val, dict) else val
                page = val.get("page", 1) if isinstance(val, dict) else 1
                if path:
                    conn.execute(
                        "INSERT OR REPLACE INTO movie_path_cache (tmdb_id, path, page) VALUES (?, ?, ?)",
                        (tmdb_id, path, page)
                    )
            conn.commit()
            PATH_CACHE_FILE.unlink()
            logger.info("Migrated movie_path_cache.json into SQLite")
    except Exception as e:
        logger.warning(f"Error migrating movie_path_cache.json: {e}")

    try:
        if FILE_ID_LOG_FILE.exists():
            with open(FILE_ID_LOG_FILE, "r", encoding="utf-8") as f:
                logs = json.load(f)
            for item in logs:
                conn.execute(
                    """
                    INSERT OR IGNORE INTO file_id_log (tmdb_id, title, file_id, quality, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (
                        item.get("tmdb_id"),
                        item.get("title", ""),
                        item.get("file_id", ""),
                        item.get("quality", ""),
                        item.get("timestamp", datetime.now().isoformat())
                    )
                )
            conn.commit()
            FILE_ID_LOG_FILE.unlink()
            logger.info("Migrated file_id_log.json into SQLite")
    except Exception as e:
        logger.warning(f"Error migrating file_id_log.json: {e}")

def get_cached_domain(key: str) -> str | None:
    try:
        with _get_connection() as conn:
            row = conn.execute("SELECT domain FROM domain_cache WHERE key = ?", (key,)).fetchone()
            if row:
                return row["domain"]
    except Exception as e:
        logger.warning(f"Error reading domain cache: {e}")
    return None

def save_cached_domain(key: str, domain: str):
    try:
        with _get_connection() as conn:
            conn.execute(
                """
                INSERT INTO domain_cache (key, domain, updated_at)
                VALUES (?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(key) DO UPDATE SET domain = excluded.domain, updated_at = CURRENT_TIMESTAMP
                """,
                (key, domain)
            )
            conn.commit()
        logger.info(f"Updated domain cache for '{key}': {domain}")
    except Exception as e:
        logger.warning(f"Error writing domain cache: {e}")

def get_cached_movie_path(tmdb_id: int) -> dict | None:
    try:
        with _get_connection() as conn:
            row = conn.execute(
                "SELECT path, page FROM movie_path_cache WHERE tmdb_id = ?",
                (tmdb_id,)
            ).fetchone()
            if row:
                return {"path": row["path"], "page": row["page"]}
    except Exception as e:
        logger.warning(f"Error reading movie path cache: {e}")
    return None

def save_cached_movie_path(tmdb_id: int, movie_path: str, page: int = 1):
    try:
        with _get_connection() as conn:
            conn.execute(
                """
                INSERT INTO movie_path_cache (tmdb_id, path, page, updated_at)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(tmdb_id) DO UPDATE SET path = excluded.path, page = excluded.page, updated_at = CURRENT_TIMESTAMP
                """,
                (tmdb_id, movie_path, page)
            )
            conn.commit()
        logger.info(f"Permanently cached movie path for TMDB {tmdb_id}: {movie_path} (Page {page})")
    except Exception as e:
        logger.warning(f"Error writing movie path cache: {e}")

def log_file_id(tmdb_id: int, title: str, file_id: str, quality: str):
    try:
        with _get_connection() as conn:
            conn.execute(
                """
                INSERT OR IGNORE INTO file_id_log (tmdb_id, title, file_id, quality, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (tmdb_id, title, file_id, quality, datetime.now().isoformat())
            )
            conn.commit()
        logger.debug(f"Logged file ID: TMDB {tmdb_id} | File ID: {file_id} | Quality: {quality}")
    except Exception as e:
        logger.warning(f"Error logging file ID: {e}")
