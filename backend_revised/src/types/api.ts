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

export interface Genre {
  slug: string;
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
  rating_score: number;
  vote_count: number;
  media_type: 'movie' | 'tv';
  genres: Genre[];
}

export interface MovieDetails extends MovieSummary {
  runtime?: number | null;
  cast?: CastMember[];
  seasons?: any[];
}

export interface LaneFilters {
  media_type?: 'all' | 'movie' | 'tv';
  genre?: string;
  year?: number;
  min_rating?: number;
  sort_by?: 'popular' | 'top_rated' | 'newest' | 'oldest' | 'title';
}

export interface SearchFilters {
  media_type?: 'all' | 'movie' | 'tv';
  year?: number;
  min_rating?: number;
  genre?: string;
}

export interface ListFilters {
  media_type?: 'all' | 'movie' | 'tv';
  sort_by?: 'rank' | 'added' | 'title' | 'released' | 'popularity' | 'votes';
  sort_order?: 'asc' | 'desc';
  genre?: string;
  year?: number;
  min_rating?: number;
}

export interface TraktListSummary {
  id: string | number;
  name: string;
  item_count: number;
  likes: number;
}

export interface PaginatedResponse<T> {
  items: T[];
  page: number;
  total_pages: number;
  total_items: number;
  has_more: boolean;
  next_page: number | null;
}

export type PaginatedMoviesResponse = PaginatedResponse<MovieSummary>;
export type PaginatedListsResponse = PaginatedResponse<TraktListSummary>;

export interface PaginatedLaneResponse extends PaginatedMoviesResponse {
  id: string;
  title: string;
}

export interface DashboardResponse {
  id: string;
  title: string;
  lanes: PaginatedLaneResponse[];
}

export interface SubtitleTrack {
  name: string;
  language: string;
  url: string;
  popularity: number;
}

export interface LaneConfig {
  id: string;
  title: string;
}

export interface DashboardConfig {
  id: string;
  title: string;
  lanes: LaneConfig[];
}
