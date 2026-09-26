import asyncio
import json
import logging
import sqlite3
import time
from pathlib import Path

from backend.config import DATA_DIR
from backend.session import get_session
from backend.services.tmdb import tmdb_client

logger = logging.getLogger(__name__)

DB_PATH = DATA_DIR / "catalog.db"

GRAPHQL_URL = "https://api.graphql.imdb.com/"

GRAPHQL_HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/graphql+json, application/json",
    "Origin": "https://www.imdb.com",
    "Referer": "https://www.imdb.com/",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "x-imdb-client-name": "imdb-web-next",
}

BASE_QUERY = """
query GetMovies($first: Int!, $after: String, $sort: AdvancedTitleSearchSort!, $constraints: AdvancedTitleSearchConstraints!) {
  advancedTitleSearch(
    first: $first
    after: $after
    sort: $sort
    constraints: $constraints
  ) {
    pageInfo {
      hasNextPage
      endCursor
    }
    edges {
      node {
        title {
          id
          titleText { text }
          releaseYear { year }
          ratingsSummary {
            aggregateRating
            voteCount
          }
          meterRanking {
            currentRank
          }
        }
      }
    }
  }
}
"""

LANES_CONFIG = {
    "trending": {
        "title": "New & Trending Tamil",
        "sort_by": "POPULARITY",
        "sort_order": "ASC",
        "constraints": {},
        "deep_crawler": False,
        "tail_order": "le.last_seen DESC, le.previous_rank ASC",
    },
    "comedy": {
        "title": "Popular Tamil Comedy",
        "sort_by": "POPULARITY",
        "sort_order": "ASC",
        "constraints": {"genreConstraint": {"anyGenreIds": ["Comedy"]}},
        "deep_crawler": False,
        "tail_order": "le.last_seen DESC, le.previous_rank ASC",
    },
    "top_rated": {
        "title": "All-Time Most Watched",
        "sort_by": "USER_RATING_COUNT",
        "sort_order": "DESC",
        "constraints": {},
        "deep_crawler": True,
        "tail_order": "le.previous_rank ASC",
    },
    "box_office": {
        "title": "Record-Breaking Box Office",
        "sort_by": "BOX_OFFICE_GROSS_DOMESTIC",
        "sort_order": "DESC",
        "constraints": {},
        "deep_crawler": True,
        "tail_order": "le.previous_rank ASC",
    },
}


class CatalogService:
    def __init__(self, db_path: Path = DB_PATH):
        self.db_path = db_path
        self._init_db()

    def _get_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode = WAL;")
        conn.execute("PRAGMA synchronous = NORMAL;")
        return conn

    def _init_db(self):
        with self._get_connection() as conn:
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
                first_seen INTEGER,
                last_updated INTEGER
            );
            """)

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

    async def _fetch_graphql_lane(
        self,
        sort_by: str,
        sort_order: str,
        extra_constraints: dict,
        limit: int = 50,
        after: str | None = None,
    ) -> tuple[list[dict], str | None]:
        constraints = {
            "titleTypeConstraint": {"anyTitleTypeIds": ["movie"]},
            "languageConstraint": {"anyPrimaryLanguages": ["ta"]},
        }
        if extra_constraints:
            constraints.update(extra_constraints)

        payload = {
            "query": BASE_QUERY,
            "variables": {
                "first": limit,
                "after": after,
                "sort": {"sortBy": sort_by, "sortOrder": sort_order},
                "constraints": constraints,
            },
        }

        session = get_session()
        resp = await session.post(
            GRAPHQL_URL,
            headers=GRAPHQL_HEADERS,
            data=json.dumps(payload),
            impersonate="chrome",
        )
        resp.raise_for_status()
        data = resp.json()

        search_result = data.get("data", {}).get("advancedTitleSearch", {})
        edges = search_result.get("edges", [])
        page_info = search_result.get("pageInfo", {})
        end_cursor = page_info.get("endCursor")

        movies = []
        for edge in edges:
            node = edge.get("node", {}).get("title", {})
            if not node:
                continue

            imdb_id = node.get("id")
            title_text = node.get("titleText", {}).get("text") if node.get("titleText") else None
            release_year = node.get("releaseYear", {}).get("year") if node.get("releaseYear") else None
            meter_rank = node.get("meterRanking", {}).get("currentRank") if node.get("meterRanking") else None
            ratings_summary = node.get("ratingsSummary", {}) or {}
            rating = ratings_summary.get("aggregateRating")
            votes = ratings_summary.get("voteCount", 0)

            if imdb_id and title_text:
                movies.append({
                    "imdb_id": imdb_id,
                    "title": title_text,
                    "year": release_year,
                    "rating": rating,
                    "votes": votes,
                    "meter_rank": meter_rank,
                })
        return movies, end_cursor

    async def sync_all_lanes(self):
        logger.info("Starting IMDb catalog synchronization...")
        now = int(time.time())

        for lane_id, cfg in LANES_CONFIG.items():
            try:
                logger.info(f"Fetching Top 50 for lane '{lane_id}' ({cfg['title']})...")
                items, end_cursor = await self._fetch_graphql_lane(
                    sort_by=cfg["sort_by"],
                    sort_order=cfg["sort_order"],
                    extra_constraints=cfg["constraints"],
                    limit=50,
                )
                self._merge_lane_data(lane_id, items, now)
                logger.info(f"Lane '{lane_id}' Top 50 merged ({len(items)} items).")

                if cfg.get("deep_crawler"):
                    await self._sync_deep_tail(lane_id, cfg, end_cursor, now)
            except Exception as e:
                logger.error(f"Error syncing lane '{lane_id}': {e}", exc_info=True)

        with self._get_connection() as conn:
            conn.execute(
                "INSERT INTO sync_meta (key, value, updated_at) VALUES ('last_sync', 'success', ?) "
                "ON CONFLICT(key) DO UPDATE SET updated_at = excluded.updated_at;",
                (now,),
            )
            conn.commit()

        asyncio.create_task(self._enrich_posters())
        logger.info("IMDb catalog synchronization complete.")

    async def _sync_deep_tail(self, lane_id: str, cfg: dict, top50_cursor: str | None, now: int):
        with self._get_connection() as conn:
            cursor_row = conn.execute(
                "SELECT value FROM sync_meta WHERE key = ?;",
                (f"{lane_id}_tail_cursor",),
            ).fetchone()
            rank_row = conn.execute(
                "SELECT value FROM sync_meta WHERE key = ?;",
                (f"{lane_id}_tail_rank",),
            ).fetchone()

        stored_cursor = cursor_row["value"] if cursor_row else None
        current_tail_rank = int(rank_row["value"]) if rank_row else 50
        active_cursor = stored_cursor or top50_cursor

        if not active_cursor:
            return

        logger.info(f"Lane '{lane_id}' crawling deep tail starting at rank {current_tail_rank}...")
        try:
            items, new_cursor = await self._fetch_graphql_lane(
                sort_by=cfg["sort_by"],
                sort_order=cfg["sort_order"],
                extra_constraints=cfg["constraints"],
                limit=50,
                after=active_cursor,
            )
        except Exception as e:
            logger.warning(f"Stored cursor failed for lane '{lane_id}', resetting to top 50 cursor: {e}")
            items, new_cursor = await self._fetch_graphql_lane(
                sort_by=cfg["sort_by"],
                sort_order=cfg["sort_order"],
                extra_constraints=cfg["constraints"],
                limit=50,
                after=top50_cursor,
            )
            current_tail_rank = 50

        if items:
            self._merge_deep_tail(lane_id, items, current_tail_rank, now)
            next_rank = current_tail_rank + len(items)
            with self._get_connection() as conn:
                if new_cursor:
                    conn.execute(
                        "INSERT INTO sync_meta (key, value, updated_at) VALUES (?, ?, ?) "
                        "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;",
                        (f"{lane_id}_tail_cursor", new_cursor, now),
                    )
                conn.execute(
                    "INSERT INTO sync_meta (key, value, updated_at) VALUES (?, ?, ?) "
                    "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;",
                    (f"{lane_id}_tail_rank", str(next_rank), now),
                )
                conn.commit()
            logger.info(f"Lane '{lane_id}' deep tail expanded from {current_tail_rank} to {next_rank}.")

    def _merge_lane_data(self, lane_id: str, items: list[dict], now: int):
        with self._get_connection() as conn:
            conn.execute(
                "UPDATE lane_entries SET today_rank = NULL WHERE lane_id = ?;",
                (lane_id,),
            )

            for rank_idx, item in enumerate(items, start=1):
                imdb_id = item["imdb_id"]

                conn.execute(
                    """
                    INSERT INTO movies (imdb_id, title, year, rating, votes, meter_rank, first_seen, last_updated)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(imdb_id) DO UPDATE SET
                        title = excluded.title,
                        year = COALESCE(excluded.year, movies.year),
                        rating = excluded.rating,
                        votes = excluded.votes,
                        meter_rank = excluded.meter_rank,
                        last_updated = excluded.last_updated;
                    """,
                    (
                        imdb_id,
                        item["title"],
                        item["year"],
                        item["rating"],
                        item["votes"],
                        item["meter_rank"],
                        now,
                        now,
                    ),
                )

                conn.execute(
                    """
                    INSERT INTO lane_entries (lane_id, imdb_id, today_rank, previous_rank, last_seen)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(lane_id, imdb_id) DO UPDATE SET
                        today_rank = excluded.today_rank,
                        previous_rank = excluded.previous_rank,
                        last_seen = excluded.last_seen;
                    """,
                    (lane_id, imdb_id, rank_idx, rank_idx, now),
                )

            conn.commit()

    def _merge_deep_tail(self, lane_id: str, items: list[dict], starting_rank: int, now: int):
        with self._get_connection() as conn:
            for idx, item in enumerate(items, start=1):
                imdb_id = item["imdb_id"]
                assigned_rank = starting_rank + idx

                conn.execute(
                    """
                    INSERT INTO movies (imdb_id, title, year, rating, votes, meter_rank, first_seen, last_updated)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(imdb_id) DO UPDATE SET
                        title = excluded.title,
                        year = COALESCE(excluded.year, movies.year),
                        rating = excluded.rating,
                        votes = excluded.votes,
                        meter_rank = excluded.meter_rank,
                        last_updated = excluded.last_updated;
                    """,
                    (
                        imdb_id,
                        item["title"],
                        item["year"],
                        item["rating"],
                        item["votes"],
                        item["meter_rank"],
                        now,
                        now,
                    ),
                )

                conn.execute(
                    """
                    INSERT INTO lane_entries (lane_id, imdb_id, today_rank, previous_rank, last_seen)
                    VALUES (?, ?, NULL, ?, ?)
                    ON CONFLICT(lane_id, imdb_id) DO UPDATE SET
                        previous_rank = COALESCE(lane_entries.previous_rank, excluded.previous_rank),
                        last_seen = excluded.last_seen;
                    """,
                    (lane_id, imdb_id, assigned_rank, now),
                )
            conn.commit()

    async def _enrich_posters(self):
        with self._get_connection() as conn:
            rows = conn.execute(
                "SELECT imdb_id FROM movies WHERE poster_path IS NULL LIMIT 250;"
            ).fetchall()

        if not rows:
            return

        logger.info(f"Enriching {len(rows)} movies with TMDB posters/backdrops...")
        sem = asyncio.Semaphore(10)

        async def fetch_one(imdb_id: str):
            async with sem:
                try:
                    tmdb_info = await tmdb_client.find_movie_by_imdb_id(imdb_id)
                    if tmdb_info:
                        return (
                            imdb_id,
                            tmdb_info.get("id"),
                            tmdb_info.get("poster_path") or "",
                            tmdb_info.get("backdrop_path") or "",
                            tmdb_info.get("overview") or "",
                        )
                    else:
                        return (imdb_id, None, "", "", "")
                except Exception as e:
                    logger.debug(f"Poster enrichment failed for {imdb_id}: {e}")
                return None

        results = await asyncio.gather(*(fetch_one(r["imdb_id"]) for r in rows))
        updates = [r for r in results if r is not None]

        if updates:
            with self._get_connection() as conn:
                conn.executemany(
                    """
                    UPDATE movies SET
                        tmdb_id = COALESCE(?, tmdb_id),
                        poster_path = ?,
                        backdrop_path = ?,
                        overview = ?
                    WHERE imdb_id = ?;
                    """,
                    [(u[1], u[2], u[3], u[4], u[0]) for u in updates],
                )
                conn.commit()
            logger.info(f"Successfully enriched {len(updates)} movies with TMDB posters.")

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
            return [dict(row) for row in cursor.fetchall()]

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


catalog_service = CatalogService()
