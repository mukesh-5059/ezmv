-- Fresh Slate Schema

-- 1. Drop old views and conflicting tables if migrating
DROP VIEW IF EXISTS v_catalog;
DROP VIEW IF EXISTS v_movies;
DROP TABLE IF EXISTS lane_entries;
DROP TABLE IF EXISTS ratings;
DROP TABLE IF EXISTS movies;
DROP TABLE IF EXISTS imdb_titles;

-- 2. Static Movie Metadata (TTL: ~7 days)
CREATE TABLE IF NOT EXISTS movies (
    imdb_id TEXT PRIMARY KEY,
    tmdb_id INTEGER,
    media_type TEXT NOT NULL DEFAULT 'movie',
    title TEXT NOT NULL,
    year INTEGER,
    release_date TEXT,
    poster_path TEXT,
    backdrop_path TEXT,
    overview TEXT,
    runtime INTEGER,
    genres TEXT,
    updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_movies_tmdb_id ON movies(tmdb_id);

-- 3. Dynamic Ratings (TTL: 24–48 hours)
CREATE TABLE IF NOT EXISTS ratings (
    imdb_id TEXT PRIMARY KEY,
    rating REAL NOT NULL DEFAULT 0,
    votes INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL
);

-- 4. Unified View for single-query reads
CREATE VIEW IF NOT EXISTS v_movies AS
SELECT 
    m.imdb_id,
    m.tmdb_id,
    m.media_type,
    m.title,
    m.year,
    m.release_date,
    COALESCE(r.rating, 0) AS rating,
    COALESCE(r.votes, 0) AS votes,
    m.poster_path,
    m.backdrop_path,
    m.overview,
    m.runtime,
    m.genres,
    m.updated_at AS metadata_updated_at,
    r.updated_at AS ratings_updated_at
FROM movies m
LEFT JOIN ratings r ON m.imdb_id = r.imdb_id;

-- 5. Lane Entries for Homepage
CREATE TABLE IF NOT EXISTS lane_entries (
    lane_id TEXT NOT NULL,
    imdb_id TEXT NOT NULL,
    rank INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (lane_id, imdb_id)
);
CREATE INDEX IF NOT EXISTS idx_lane_rank ON lane_entries(lane_id, rank);
