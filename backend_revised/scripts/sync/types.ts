export interface RawRating {
  source: string;
  value?: number | null;
  score?: number | null;
  votes?: number | null;
}

export interface CompositeRatingResult {
  ratingScore: number;
  votes: number;
  ratingsJson: string;
}

export interface RatingRules {
  prior_mean: number;
  min_votes: Record<string, number>;
  source_weights: Record<string, number>;
  bayesian_m: {
    single_source: number;
    two_sources: number;
    three_plus_sources: number;
  };
  era_curve: {
    decay_rate: number;
    recency_penalty_max: number;
    classic_start_age: number;
    classic_ramp_years: number;
    classic_boost_max: number;
    era_bounds: [number, number] | number[];
  };
}

export interface GenreItem {
  id?: number;
  name?: string;
  title?: string;
  slug?: string;
}

export interface RawCandidateItem {
  imdb_id?: string;
  imdbid?: string;
  ids?: {
    imdb?: string;
    tmdb?: number;
    trakt?: number;
    tvdb?: number;
    mal?: number;
  };
  id?: number;
  title?: string;
  year?: number;
  release_year?: number;
  release_date?: string;
  released?: string;
  type?: string;
  language?: string;
  runtime?: number;
  poster?: string;
  backdrop?: string;
  description?: string;
  genres?: Array<string | GenreItem>;
  ratings?: RawRating[];
  score_average?: number;
  aired_episodes?: number;
  movie?: any;
  show?: any;
}

export interface CandidateFeedResult {
  feeds: Record<string, RawCandidateItem[]>;
  candidateIds: Set<string>;
}

export interface CatalogItem {
  imdb_id: string;
  full_item: RawCandidateItem;
  item: RawCandidateItem;
  rating_score: number;
  votes: number;
  ratings_json: string;
  poster: string;
  runtime: number;
  lang: string;
  rel_str: string;
  rel_dt: Date | null;
  slugs: string[];
  is_excluded_genre: boolean;
  imdb_votes: number;
  lb_votes: number;
}

export interface TamilLaneConfig {
  lane_id: string;
  title: string;
  list_id: number;
  query: string;
  lang?: string;
  exclude_lang?: string;
  min_rating?: number;
  min_votes?: number;
}

export interface TraktLaneConfig {
  lane_id: string;
  title: string;
  endpoint: string;
  params?: Record<string, string | number>;
}
