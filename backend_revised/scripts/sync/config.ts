import fs from "node:fs";
import path from "node:path";
import { RatingRules } from "./types";

export const ANYTHING_TO_GENRE_SLUGS: Record<string, string[]> = {
  action: ["action"],
  adventure: ["adventure"],
  animation: ["animation"],
  anime: ["anime"],
  biography: ["biography"],
  comedy: ["comedy"],
  crime: ["crime"],
  documentary: ["documentary"],
  drama: ["drama"],
  family: ["family"],
  fantasy: ["fantasy"],
  history: ["history"],
  horror: ["horror"],
  music: ["music"],
  musical: ["music"],
  mystery: ["mystery"],
  romance: ["romance"],
  "sci-fi": ["sci-fi"],
  "science fiction": ["sci-fi"],
  "science-fiction": ["sci-fi"],
  "sci fi": ["sci-fi"],
  sport: ["sport"],
  sports: ["sport"],
  "sporting event": ["sport"],
  "sporting-event": ["sport"],
  thriller: ["thriller"],
  suspense: ["thriller"],
  war: ["war"],
};

export function getEnvOrDevVar(name: string): string {
  const envVal = process.env[name];
  if (envVal) return envVal;

  const candidatePaths = [
    path.resolve(process.cwd(), ".env"),
    path.resolve(process.cwd(), ".dev.vars"),
    path.resolve(process.cwd(), "backend_revised/.dev.vars"),
    path.resolve(__dirname, "../../.dev.vars"),
    path.resolve(__dirname, "../../../.dev.vars"),
  ];

  for (const p of candidatePaths) {
    if (fs.existsSync(p)) {
      try {
        const lines = fs.readFileSync(p, "utf-8").split("\n");
        for (const line of lines) {
          if (line.trim().startsWith(`${name}=`)) {
            const raw = line.trim().slice(name.length + 1).trim();
            return raw.replace(/^["']|["']$/g, "");
          }
        }
      } catch {}
    }
  }
  return "";
}

export function resolveCfAccountId(): string {
  return getEnvOrDevVar("CLOUDFLARE_ACCOUNT_ID");
}

export function normalizeGenreSlugs(raw: string): string[] {
  const key = raw.trim().toLowerCase();
  if (ANYTHING_TO_GENRE_SLUGS[key]) {
    return ANYTHING_TO_GENRE_SLUGS[key];
  }
  return [key.replace(/\s+/g, "-")];
}

export function loadRatingRules(): RatingRules {
  const rulesPath = path.resolve(__dirname, "../../src/config/rating_rules.json");
  if (fs.existsSync(rulesPath)) {
    try {
      return JSON.parse(fs.readFileSync(rulesPath, "utf-8"));
    } catch {}
  }
  return {
    prior_mean: 6.8,
    min_votes: { imdb: 500, letterboxd: 50, myanimelist: 100, popcorn: 500, tomatoes: 10, tomatoesaudience: 50, tmdb: 20, metacritic: 5, trakt: 20 },
    source_weights: { myanimelist: 0.45, letterboxd: 0.40, imdb: 0.30, tomatoes: 0.05, popcorn: 0.05, tomatoesaudience: 0.05, tmdb: 0.10, metacritic: 0.025, trakt: 0.025 },
    bayesian_m: { single_source: 10000, two_sources: 3000, three_plus_sources: 1000 },
    era_curve: { decay_rate: 1.386, recency_penalty_max: 0.5, classic_start_age: 3.0, classic_ramp_years: 25.0, classic_boost_max: 0.5, era_bounds: [0.5, 1.5] },
  };
}

export function resolveApiKey(cliKey?: string): string {
  const key = cliKey || getEnvOrDevVar("MDBLIST_API_KEY");
  if (!key) throw new Error("MDBList API Key not provided via --api-key, MDBLIST_API_KEY env, or .dev.vars/.env");
  return key;
}

export function resolveTraktClientId(cliId?: string): string {
  const tid = cliId || getEnvOrDevVar("TRAKT_CLIENT_ID");
  if (!tid) throw new Error("TRAKT_CLIENT_ID not provided via --trakt-client-id, env, or .dev.vars/.env");
  return tid;
}
