import { loadRatingRules } from "./config";
import { CompositeRatingResult, RatingRules, RawCandidateItem, RawRating } from "./types";

const RULES = loadRatingRules();

export function computeCompositeRating(
  item: RawCandidateItem,
  rules: RatingRules = RULES
): CompositeRatingResult {
  const minVotesCfg = rules.min_votes || {};
  const sourceWeightsCfg = rules.source_weights || {};
  const rawRatings: RawRating[] = item.ratings || [];

  let weightedSum = 0.0;
  let totalWeight = 0.0;
  let totalVotes = 0;
  const cleanedRatings: RawRating[] = [];
  const qualifiedSources = new Set<string>();

  for (const r of rawRatings) {
    const src = r.source;
    if (!src) continue;
    const val = r.value;
    const score = r.score;
    const votes = Number(r.votes || 0);

    cleanedRatings.push({
      source: src,
      value: val,
      score: score,
      votes: votes,
    });

    const weight = Number(sourceWeightsCfg[src] || 0);
    if (!weight) continue;

    const minVotes = Number(minVotesCfg[src] || 0);
    if (votes < minVotes) continue;

    let normalized: number | null = null;
    if (score !== null && score !== undefined && typeof score === "number") {
      normalized = score / 10.0;
    }

    if (normalized !== null) {
      weightedSum += normalized * weight;
      totalWeight += weight;
      totalVotes += votes;
      qualifiedSources.add(src);
    }
  }

  const ratingsJson = JSON.stringify(cleanedRatings);

  if (totalWeight > 0 && qualifiedSources.size > 0) {
    const rawRating = weightedSum / totalWeight;
    const numSources = qualifiedSources.size;

    const bayesianM = rules.bayesian_m;
    let m =
      numSources === 1
        ? Number(bayesianM?.single_source ?? 10000)
        : numSources === 2
        ? Number(bayesianM?.two_sources ?? 3000)
        : Number(bayesianM?.three_plus_sources ?? 1000);

    const now = new Date();
    const currentYear = now.getUTCFullYear();
    let age: number | null = null;
    const relDateStr = item.release_date || item.released;

    if (relDateStr) {
      try {
        const parts = String(relDateStr).trim().split("-");
        if (parts.length >= 1 && parts[0].length === 4) {
          const y = parseInt(parts[0], 10);
          const mth = parts.length > 1 ? parseInt(parts[1], 10) - 1 : 0;
          const d = parts.length > 2 ? parseInt(parts[2], 10) : 1;
          const relDt = new Date(Date.UTC(y, mth, d));
          age = (now.getTime() - relDt.getTime()) / (1000 * 60 * 60 * 24 * 365.25);
        }
      } catch {}
    }

    if (age === null) {
      const y = item.release_year || item.year;
      if (y) {
        try {
          age = currentYear - Number(y);
        } catch {}
      }
    }

    const eraCfg = rules.era_curve;
    if (age !== null && eraCfg) {
      age = Math.max(0, age);
      const decayRate = Number(eraCfg.decay_rate ?? 1.386);
      const recencyPenaltyMax = Number(eraCfg.recency_penalty_max ?? 0.5);
      const penalty = recencyPenaltyMax * Math.exp(-age * decayRate);

      const classicStartAge = Number(eraCfg.classic_start_age ?? 3.0);
      const classicRampYears = Number(eraCfg.classic_ramp_years ?? 25.0);
      const classicBoostMax = Number(eraCfg.classic_boost_max ?? 0.5);
      const boost =
        classicBoostMax * Math.max(0.0, Math.min(1.0, (age - classicStartAge) / classicRampYears));

      const bounds = eraCfg.era_bounds || [0.5, 1.5];
      const rawEra = Math.max(Number(bounds[0]), Math.min(Number(bounds[1]), 1.0 + penalty - boost));
      const eraModifier = 1.0 + (rawEra - 1.0) / numSources;
      m *= eraModifier;
    }

    const C = Number(rules.prior_mean || 6.8);
    const scoreCalc = (totalVotes / (totalVotes + m)) * rawRating + (m / (totalVotes + m)) * C;
    const ratingScore = Math.round(scoreCalc * 10) / 10;

    return { ratingScore, votes: totalVotes, ratingsJson };
  }

  return { ratingScore: 0.0, votes: 0, ratingsJson };
}
