// MDBList Raw Response Types
export interface MdblistRating {
  source: string;
  value?: number; //raw rating
  score?: number; //normalized rating
  votes?: number;
}

export interface CompositeRating {
  rating_score: number;
  votes: number;
  ratingsJson: string;
}

export interface MdblistGenre {
  id?: number;
  title?: string;
  name?: string;
  slug?: string;
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
  score_average?: number;
  type?: 'movie' | 'show';
  poster?: string;
  backdrop?: string;
  ratings?: MdblistRating[];
  genres?: Array<string | MdblistGenre>;
}

// Trakt Raw Response Types
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

export interface TmdbCredit {
  id: number;
  media_type: 'movie' | 'tv';
  title?: string;
  name?: string;
  release_date?: string;
  first_air_date?: string;
  popularity?: number;
  vote_count?: number;
  vote_average?: number;
  genre_ids?: number[];
  character?: string;
  order?: number;
  episode_count?: number;
}
