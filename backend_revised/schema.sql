CREATE TABLE IF NOT EXISTS imdb_ratings (
    imdb_id TEXT PRIMARY KEY,
    rating REAL NOT NULL,
    votes INTEGER NOT NULL
);

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
    last_updated INTEGER,
    genre_ids TEXT
);

CREATE TABLE IF NOT EXISTS lane_entries (
    lane_id TEXT,
    imdb_id TEXT,
    today_rank INTEGER,
    previous_rank INTEGER,
    last_seen INTEGER,
    PRIMARY KEY (lane_id, imdb_id)
);

CREATE INDEX IF NOT EXISTS idx_lane_ordering 
ON lane_entries(lane_id, today_rank, last_seen, previous_rank);
