export type Bindings = {
  DB: D1Database;
  MDBLIST_API_KEY?: string;
  TRAKT_CLIENT_ID?: string;
  TMDB_API_KEY?: string;
  TMDB_READ_ACCESS_TOKEN?: string;
};

export interface RequestTrace {
  steps: string[];
  add: (step: string) => void;
}

export type Variables = {
  trace: RequestTrace;
};

export interface GenreItem {
  mdb_id: number;
  name: string;
}

export interface CastMember {
  tmdb_id: number;
  name: string;
  character: string;
  profile_path?: string | null;
  order?: number;
}

export interface MovieSummary {
  imdb_id: string;
  tmdb_id: number;
  title: string;
  overview: string;
  release_date: string;
  poster_path: string;
  backdrop_path: string;
  rating: number;
  vote_count: number;
  media_type: 'movie' | 'tv';
  genre_ids: number[];
}

export interface MovieDetails extends MovieSummary {
  runtime?: number | null;
  genres: GenreItem[];
  cast?: CastMember[];
  seasons?: any[];
}

export interface SubtitleTrack {
  name: string;
  language: string;
  url: string;
  popularity: number;
}

// MDBList Raw Response Types
export interface MdblistRating {
  source: string;
  value: number;
  votes?: number;
}

export interface MdblistGenre {
  id: number;
  title: string;
}

export interface MdblistItem {
  id?: number;
  imdbid?: string;
  tmdbid?: number;
  ids?: {
    imdb?: string;
    tmdb?: number;
    trakt?: number;
  };
  title?: string;
  year?: number;
  released?: string;
  released_digital?: string;
  description?: string;
  runtime?: number;
  score?: number;
  type?: 'movie' | 'show';
  poster?: string;
  backdrop?: string;
  ratings?: MdblistRating[];
  genres?: MdblistGenre[];
}

// Trakt Search Types
export interface TraktSearchItem {
  type: string;
  score?: number;
  movie?: {
    title: string;
    year?: number;
    ids: {
      trakt?: number;
      slug?: string;
      imdb?: string;
      tmdb?: number;
    };
  };
  show?: {
    title: string;
    year?: number;
    ids: {
      trakt?: number;
      slug?: string;
      imdb?: string;
      tmdb?: number;
    };
  };
}

export interface TraktSearchResponse {
  imdb_ids: string[];
  page: number;
  total_pages: number;
  total_items: number;
}

export interface LaneConfig {
  id: string;
  title: string;
}
