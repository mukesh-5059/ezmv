import json
import sqlite3
import time
import logging
from pathlib import Path
from backend.config import DATA_DIR

logger = logging.getLogger(__name__)

CACHE_DB_PATH = DATA_DIR / "cache.db"


def get_cache_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(CACHE_DB_PATH, timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode = WAL;")
    conn.execute("PRAGMA synchronous = NORMAL;")
    conn.execute("PRAGMA busy_timeout = 5000;")
    return conn


def init_cache_db():
    with get_cache_connection() as conn:
        conn.execute("""
        CREATE TABLE IF NOT EXISTS tmdb_cache (
            key TEXT PRIMARY KEY,
            data_json TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL
        );
        """)
        conn.execute("""
        CREATE TABLE IF NOT EXISTS stream_cache (
            tmdb_id INTEGER NOT NULL,
            scraper_id TEXT NOT NULL,
            provider TEXT NOT NULL,
            quality TEXT NOT NULL,
            url TEXT NOT NULL,
            headers_json TEXT,
            priority INTEGER DEFAULT 100,
            created_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL,
            ttl INTEGER NOT NULL,
            season INTEGER NOT NULL DEFAULT 0,
            episode INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (tmdb_id, scraper_id, quality, season, episode)
        );
        """)
        conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_stream_lookup 
        ON stream_cache(tmdb_id, season, episode, expires_at);
        """)
        conn.commit()


def purge_expired_cache():
    now = int(time.time())
    thirty_days_ago = now - (30 * 86400)
    try:
        with get_cache_connection() as conn:
            cur1 = conn.execute(
                "DELETE FROM tmdb_cache WHERE expires_at < ? OR created_at < ?;",
                (now, thirty_days_ago),
            )
            cur2 = conn.execute(
                "DELETE FROM stream_cache WHERE created_at < ?;",
                (thirty_days_ago,),
            )
            conn.commit()
            logger.info(
                f"[Cache Purge] Purged {cur1.rowcount} expired TMDB entries and {cur2.rowcount} stream entries older than 30 days."
            )
    except Exception as e:
        logger.error(f"Error purging expired cache: {e}")


def get_tmdb_cache(key: str) -> dict | list | None:
    now = int(time.time())
    try:
        with get_cache_connection() as conn:
            row = conn.execute(
                "SELECT data_json FROM tmdb_cache WHERE key = ? AND expires_at >= ?;",
                (key, now),
            ).fetchone()
            if row:
                return json.loads(row["data_json"])
    except Exception as e:
        logger.warning(f"Failed to read TMDB cache for '{key}': {e}")
    return None


def set_tmdb_cache(key: str, data: dict | list, ttl_seconds: int = 86400):  # 1 day default
    now = int(time.time())
    expires_at = now + ttl_seconds
    try:
        with get_cache_connection() as conn:
            conn.execute(
                """
                INSERT INTO tmdb_cache (key, data_json, created_at, expires_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    data_json = excluded.data_json,
                    created_at = excluded.created_at,
                    expires_at = excluded.expires_at;
                """,
                (key, json.dumps(data), now, expires_at),
            )
            conn.commit()
    except Exception as e:
        logger.warning(f"Failed to save TMDB cache for '{key}': {e}")


def get_cached_streams(
    tmdb_id: int,
    season: int | None = None,
    episode: int | None = None,
    scraper_id: str | None = None,
) -> list[dict]:
    now = int(time.time())
    safe_season = season if season is not None else 0
    safe_episode = episode if episode is not None else 0
    try:
        with get_cache_connection() as conn:
            query = """
            SELECT tmdb_id, scraper_id, provider, quality, url, headers_json, priority, created_at, expires_at, ttl, season, episode
            FROM stream_cache
            WHERE tmdb_id = ?
              AND season = ?
              AND episode = ?
              AND expires_at > ?
            """
            params: list = [tmdb_id, safe_season, safe_episode, now]
            if scraper_id:
                query += " AND (scraper_id = ? OR LOWER(provider) LIKE ?)"
                params.extend([scraper_id.lower(), f"%{scraper_id.lower()}%"])

            query += " ORDER BY priority ASC, created_at DESC;"
            rows = conn.execute(query, params).fetchall()

            results = []
            for row in rows:
                headers = json.loads(row["headers_json"]) if row["headers_json"] else {}
                remaining_ttl = max(0, row["expires_at"] - now)
                results.append({
                    "url": row["url"],
                    "scraper_id": row["scraper_id"],
                    "provider": row["provider"],
                    "quality": row["quality"],
                    "headers": headers,
                    "priority": row["priority"],
                    "created_at": row["created_at"],
                    "expires_at": row["expires_at"],
                    "ttl": row["ttl"],
                    "remaining_ttl": remaining_ttl,
                })
            return results
    except Exception as e:
        logger.warning(f"Failed to read cached streams for TMDB {tmdb_id}: {e}")
        return []


def save_cached_streams(
    tmdb_id: int,
    streams: list[dict],
    season: int | None = None,
    episode: int | None = None,
):
    now = int(time.time())
    safe_season = season if season is not None else 0
    safe_episode = episode if episode is not None else 0
    try:
        with get_cache_connection() as conn:
            for s in streams:
                ttl = s.get("ttl") or 86400
                expires_at = s.get("expires_at") or (now + ttl)
                headers_json = json.dumps(s.get("headers", {}))
                raw_prov = s.get("provider", "direct")
                scraper_id = (s.get("scraper_id") or raw_prov.split(" ")[0]).lower().strip("()")
                conn.execute(
                    """
                    INSERT INTO stream_cache (
                        tmdb_id, scraper_id, provider, quality, url, headers_json, priority, created_at, expires_at, ttl, season, episode
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(tmdb_id, scraper_id, quality, season, episode) DO UPDATE SET
                        provider = excluded.provider,
                        url = excluded.url,
                        headers_json = excluded.headers_json,
                        priority = excluded.priority,
                        created_at = excluded.created_at,
                        expires_at = excluded.expires_at,
                        ttl = excluded.ttl;
                    """,
                    (
                        tmdb_id,
                        scraper_id,
                        raw_prov,
                        s.get("quality", "HD"),
                        s.get("url", ""),
                        headers_json,
                        s.get("priority", 100),
                        now,
                        expires_at,
                        ttl,
                        safe_season,
                        safe_episode,
                    ),
                )
            conn.commit()
    except Exception as e:
        logger.warning(f"Failed to save cached streams for TMDB {tmdb_id}: {e}")


def delete_cached_streams(
    tmdb_id: int,
    scraper_id: str | None = None,
    season: int | None = None,
    episode: int | None = None,
):
    safe_season = season if season is not None else 0
    safe_episode = episode if episode is not None else 0
    try:
        with get_cache_connection() as conn:
            if scraper_id:
                clean_scraper = scraper_id.lower().split(" ")[0].strip("()")
                conn.execute(
                    """
                    DELETE FROM stream_cache
                    WHERE tmdb_id = ?
                      AND (scraper_id = ? OR LOWER(provider) LIKE ?)
                      AND season = ?
                      AND episode = ?;
                    """,
                    (tmdb_id, clean_scraper, f"%{clean_scraper}%", safe_season, safe_episode),
                )
            else:
                conn.execute(
                    """
                    DELETE FROM stream_cache
                    WHERE tmdb_id = ?
                      AND season = ?
                      AND episode = ?;
                    """,
                    (tmdb_id, safe_season, safe_episode),
                )
            conn.commit()
    except Exception as e:
        logger.warning(f"Failed to delete cached streams for TMDB {tmdb_id}: {e}")
