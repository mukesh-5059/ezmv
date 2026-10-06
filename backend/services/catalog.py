import sqlite3
from pathlib import Path
from backend.config import DATA_DIR, DB_PATH
from backend.models import MovieSummary

LANES_CONFIG = {
    "trending": {
        "title": "New & Trending Tamil",
        "tail_order": "le.last_seen DESC, le.previous_rank ASC",
    },
    "comedy": {
        "title": "Popular Tamil Comedy",
        "tail_order": "le.last_seen DESC, le.previous_rank ASC",
    },
    "top_rated": {
        "title": "All-Time Most Watched",
        "tail_order": "le.previous_rank ASC",
    },
    "box_office": {
        "title": "Record-Breaking Box Office",
        "tail_order": "le.previous_rank ASC",
    },
}

def get_connection(db_path: Path = DB_PATH) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path, timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode = WAL;")
    conn.execute("PRAGMA synchronous = NORMAL;")
    conn.execute("PRAGMA busy_timeout = 5000;")
    return conn

def init_db(conn: sqlite3.Connection):
    conn.execute("""
    CREATE TABLE IF NOT EXISTS movies (
        imdb_id TEXT PRIMARY KEY,
        tmdb_id INTEGER,
        title TEXT NOT NULL,
        year INTEGER,
        rating REAL,
        votes INTEGER,
        meter_rank INTEGER,
        poster_path TEXT,
        backdrop_path TEXT,
        overview TEXT,
        genre_ids TEXT,
        first_seen INTEGER,
        last_updated INTEGER
    );
    """)

    # Ensure genre_ids column exists if migrating existing DB
    cols = [r[1] for r in conn.execute("PRAGMA table_info(movies);").fetchall()]
    if "genre_ids" not in cols:
        conn.execute("ALTER TABLE movies ADD COLUMN genre_ids TEXT;")

    conn.execute("""
    CREATE TABLE IF NOT EXISTS lane_entries (
        lane_id TEXT,
        imdb_id TEXT,
        today_rank INTEGER,
        previous_rank INTEGER,
        last_seen INTEGER,
        PRIMARY KEY (lane_id, imdb_id)
    );
    """)

    conn.execute("""
    CREATE TABLE IF NOT EXISTS sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at INTEGER
    );
    """)

    conn.execute("""
    CREATE INDEX IF NOT EXISTS idx_lane_ordering 
    ON lane_entries(lane_id, today_rank, last_seen, previous_rank);
    """)
    conn.commit()

class CatalogService:
    def __init__(self, db_path: Path = DB_PATH):
        self.db_path = db_path
        with self._get_connection() as conn:
            init_db(conn)

    def _get_connection(self) -> sqlite3.Connection:
        return get_connection(self.db_path)

    def get_lane_movies(self, lane_id: str, limit: int = 50, offset: int = 0) -> list[dict]:
        cfg = LANES_CONFIG.get(lane_id, {})
        tail_order = cfg.get("tail_order", "le.last_seen DESC, le.previous_rank ASC")

        query = f"""
        SELECT 
            m.imdb_id,
            m.tmdb_id,
            m.title,
            m.year,
            m.rating,
            m.votes,
            m.poster_path,
            m.backdrop_path,
            m.overview,
            m.genre_ids,
            le.today_rank,
            le.previous_rank,
            le.last_seen
        FROM lane_entries le
        JOIN movies m ON le.imdb_id = m.imdb_id
        WHERE le.lane_id = ?
        ORDER BY 
            CASE WHEN le.today_rank IS NOT NULL THEN 0 ELSE 1 END ASC,
            le.today_rank ASC,
            {tail_order}
        LIMIT ? OFFSET ?;
        """
        with self._get_connection() as conn:
            cursor = conn.execute(query, (lane_id, limit, offset))
            items = []
            for row in cursor.fetchall():
                d = dict(row)
                raw_genres = d.get("genre_ids")
                if raw_genres:
                    try:
                        d["genre_ids"] = [int(g.strip()) for g in raw_genres.split(",") if g.strip()]
                    except Exception:
                        d["genre_ids"] = []
                else:
                    d["genre_ids"] = []
                items.append(d)
            return items

    def get_available_lanes(self) -> list[dict]:
        lanes = []
        with self._get_connection() as conn:
            for lane_id, cfg in LANES_CONFIG.items():
                count_row = conn.execute(
                    "SELECT COUNT(*) AS total FROM lane_entries WHERE lane_id = ?;",
                    (lane_id,),
                ).fetchone()
                total = count_row["total"] if count_row else 0
                lanes.append({
                    "lane_id": lane_id,
                    "title": cfg["title"],
                    "total_movies": total,
                })
        return lanes

    def get_last_sync_time(self) -> int | None:
        with self._get_connection() as conn:
            row = conn.execute("SELECT updated_at FROM sync_meta WHERE key = 'last_sync';").fetchone()
            return row["updated_at"] if row else None

    def search_movies(self, query: str, limit: int = 20, offset: int = 0) -> list[dict]:
        with self._get_connection() as conn:
            cursor = conn.execute(
                """
                SELECT * FROM movies 
                WHERE title LIKE ? OR imdb_id = ?
                ORDER BY votes DESC 
                LIMIT ? OFFSET ?;
                """,
                (f"%{query}%", query, limit, offset),
            )
            return [dict(row) for row in cursor.fetchall()]

    def get_movie_by_tmdb_id(self, tmdb_id: int) -> dict | None:
        with self._get_connection() as conn:
            row = conn.execute("SELECT * FROM movies WHERE tmdb_id = ?;", (tmdb_id,)).fetchone()
            return dict(row) if row else None

    def get_tamil_category_movies(
        self,
        category: str | None = None,
        genre: int | None = None,
        year: int | None = None,
        page: int = 1,
        limit: int = 20
    ) -> list[MovieSummary] | None:
        lane_id = None
        default_genre = None
        if category in ["box_office", "box_office_hit"]:
            lane_id = "box_office"
        elif category in ["popular", "top_rated"]:
            lane_id = "top_rated"
        elif (category in ["comedy", "latest_comedy"] or genre == 35) and year is None:
            lane_id = "comedy"
            default_genre = 35
        elif category in ["latest", "trending"] or (category is None and genre is None and year is None):
            lane_id = "trending"

        if lane_id:
            offset = (page - 1) * limit
            movies = self.get_lane_movies(lane_id, limit=limit, offset=offset)
            return [MovieSummary.from_catalog(m, default_genre=default_genre) for m in movies]
        return None

    async def search_catalog_with_fallback(
        self,
        query: str,
        year: int | None = None,
        page: int = 1,
        limit: int = 20
    ) -> list[MovieSummary]:
        offset = (page - 1) * limit
        local_results = self.search_movies(query=query, limit=limit, offset=offset)
        formatted_local = [MovieSummary.from_catalog(m) for m in local_results]
        if len(formatted_local) >= 10:
            return formatted_local

        from backend.services.tmdb import tmdb_client
        tmdb_results = await tmdb_client.search_movie(query=query, year=year, page=page)
        existing_ids = {m.tmdb_id for m in formatted_local}
        formatted_tmdb = [
            MovieSummary.from_tmdb(item, media_type="movie")
            for item in tmdb_results
            if item.get("id") not in existing_ids
        ]
        return formatted_local + formatted_tmdb

catalog_service = CatalogService()
