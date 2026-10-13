export type Bindings = {
  DB: D1Database;
  ApiKey?: string;
  ReadAccessToken?: string;
  TMDB_API_KEY?: string;
  TMDB_READ_ACCESS_TOKEN?: string;
  TRAKT_CLIENT_ID?: string;
  PENGUPLAY_MANIFEST_URL?: string;
};

export interface GenreItem {
  id: number;
  name: string;
}

export interface CastMember {
  id: number;
  name: string;
  character: string;
  profile_path?: string | null;
}

export interface TvSeasonItem {
  id: number;
  season_number: number;
  name: string;
  episode_count: number;
  poster_path?: string | null;
  air_date?: string | null;
  overview?: string | null;
}

export interface MovieDetailsResponse {
  tmdb_id: number;
  imdb_id?: string | null;
  title: string;
  name?: string;
  overview: string;
  release_date: string;
  first_air_date?: string;
  poster_path: string;
  backdrop_path: string;
  vote_average: number;
  vote_count: number;
  rating?: number;
  runtime?: number | null;
  tagline?: string | null;
  media_type: 'movie' | 'tv';
  number_of_seasons?: number;
  number_of_episodes?: number;
  genres: GenreItem[];
  cast: CastMember[];
  seasons?: TvSeasonItem[];
}
