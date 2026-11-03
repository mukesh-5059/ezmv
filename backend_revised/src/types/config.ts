import { DashboardSummary } from './api';

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

export type DashboardsList = DashboardSummary[];