import { buildLaneEntrySql } from "./sql";
import { fetchTraktItems } from "./trakt";
import { CandidateFeedResult, CatalogItem, RawCandidateItem, TraktLaneConfig } from "./types";

export const ENGLISH_LANES_CONFIG: TraktLaneConfig[] = [
  { lane_id: "en_trending", title: "Trending Now", endpoint: "movies/trending", params: { limit: 50 } },
  { lane_id: "en_new_releases", title: "New in Theaters", endpoint: "movies/popular", params: { years: "2025-2026", limit: 50 } },
  { lane_id: "en_top_rated", title: "All-Time Masterpieces", endpoint: "movies/played/all", params: { limit: 50 } },
  { lane_id: "en_animated", title: "Trending Animated Movies", endpoint: "movies/watched/all", params: { genres: "animation", limit: 50 } },
  { lane_id: "en_series", title: "Binge-Worthy Series", endpoint: "shows/trending", params: { limit: 50 } },
];

export async function fetchCandidates(traktClientId: string): Promise<CandidateFeedResult> {
  const feeds: Record<string, RawCandidateItem[]> = {};
  const candidateIds = new Set<string>();

  for (const cfg of ENGLISH_LANES_CONFIG) {
    const lid = cfg.lane_id;
    const movies = await fetchTraktItems(traktClientId, cfg.endpoint, cfg.params);
    feeds[lid] = movies;
    for (const m of movies) {
      const iid = m.imdb_id;
      if (iid && iid.startsWith("tt")) {
        candidateIds.add(iid);
      }
    }
  }

  return { feeds, candidateIds };
}

export function generateLaneSql(
  catalog: Record<string, CatalogItem>,
  feeds: Record<string, RawCandidateItem[]>,
  nowDt: Date = new Date(),
  nowTs: number = Math.floor(nowDt.getTime() / 1000)
): string[] {
  const statements: string[] = [];

  for (const cfg of ENGLISH_LANES_CONFIG) {
    const lid = cfg.lane_id;
    const items = feeds[lid] || [];
    const laneIds: string[] = [];

    for (const it of items) {
      const iid = it.imdb_id;
      if (!iid || !catalog[iid]) continue;
      const m = catalog[iid];
      if (!m.poster) continue;

      const slugs: string[] = m.slugs || [];
      if (slugs.includes("documentary") || slugs.includes("short")) continue;
      if (lid !== "en_animated" && slugs.includes("animation")) continue;

      laneIds.push(iid);
    }

    statements.push(...buildLaneEntrySql(lid, laneIds.slice(0, 100), nowTs));
  }

  return statements;
}
