CREATE TABLE IF NOT EXISTS imdb_titles (
    imdb_id TEXT PRIMARY KEY,
    rating REAL NOT NULL,
    votes INTEGER NOT NULL,
    year INTEGER,
    genres TEXT
);

CREATE TABLE IF NOT EXISTS movies (
    imdb_id TEXT PRIMARY KEY,
    tmdb_id INTEGER,
    title TEXT NOT NULL,
    release_date TEXT,
    poster_path TEXT,
    backdrop_path TEXT,
    overview TEXT,
    last_updated INTEGER
);

CREATE INDEX IF NOT EXISTS idx_movies_tmdb_id ON movies(tmdb_id);

CREATE TABLE IF NOT EXISTS lane_entries (
    lane_id TEXT,
    imdb_id TEXT,
    today_rank INTEGER,
    previous_rank INTEGER,
    last_seen INTEGER,
    PRIMARY KEY (lane_id, imdb_id)
);

CREATE INDEX IF NOT EXISTS idx_lane_decay 
ON lane_entries(lane_id, today_rank, last_seen, previous_rank);

CREATE VIEW IF NOT EXISTS v_catalog AS
SELECT 
    m.imdb_id,
    m.tmdb_id,
    m.title,
    m.release_date,
    t.year,
    t.rating,
    t.votes,
    t.genres,
    m.poster_path,
    m.backdrop_path,
    m.overview,
    m.last_updated
FROM movies m
LEFT JOIN imdb_titles t ON m.imdb_id = t.imdb_id;
