// MDBList Raw Response Types
export interface MdblistRating {
  source: string;
  value: number;
  votes?: number;
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
  score?: number;
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
