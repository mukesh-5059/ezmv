export type Bindings = {
  DB: D1Database;
  ApiKey?: string;
  ReadAccessToken?: string;
  TMDB_API_KEY?: string;
  TMDB_READ_ACCESS_TOKEN?: string;
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
}

export interface MovieSummaryResponse {
  tmdb_id: number;
  imdb_id?: string | null;
  title: string;
  overview: string;
  release_date: string;
  poster_path: string;
  backdrop_path: string;
  rating: number;
  vote_count: number;
  media_type: 'movie' | 'tv';
  genre_ids?: number[];
}

export interface MovieDetailsResponse extends MovieSummaryResponse {
  runtime?: number | null;
  tagline?: string | null;
  number_of_seasons?: number;
  number_of_episodes?: number;
  genres: GenreItem[];
  cast: CastMember[];
  seasons?: TvSeasonItem[];
}

export interface TvEpisode {
  id: number;
  episode_number: number;
  name: string;
  overview: string;
  still_path?: string | null;
  air_date?: string | null;
  rating: number;
  runtime?: number | null;
  upcoming?: boolean;
}

export interface TvSeasonDetailsResponse {
  season_number: number;
  episodes: TvEpisode[];
}
