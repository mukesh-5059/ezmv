import { buildLaneEntrySql } from "./sql";
import { fetchTraktItems } from "./trakt";
import { CandidateFeedResult, CatalogItem, RawCandidateItem, TraktLaneConfig } from "./types";

export const ANIME_LANES_CONFIG: TraktLaneConfig[] = [
  { lane_id: "anime_trending", title: "Trending Anime", endpoint: "shows/trending", params: { genres: "anime", limit: 50 } },
  { lane_id: "anime_top_rated", title: "Top Rated Series", endpoint: "shows/watched/all", params: { genres: "anime", limit: 50 } },
  { lane_id: "anime_movies", title: "Masterpiece Movies", endpoint: "movies/watched/all", params: { genres: "anime", limit: 50 } },
  { lane_id: "anime_comedy", title: "Comedy Anime", endpoint: "shows/watched/all", params: { genres: "anime", extended: "full", limit: 100 } },
];

export async function fetchCandidates(traktClientId: string): Promise<CandidateFeedResult> {
  const feeds: Record<string, RawCandidateItem[]> = {};
  const candidateIds = new Set<string>();

  for (const cfg of ANIME_LANES_CONFIG) {
    const lid = cfg.lane_id;
    const movies = await fetchTraktItems(traktClientId, cfg.endpoint, cfg.params);
    feeds[lid] = movies;
    for (const m of movies) {
      if (!m.language || m.language === "en") m.language = "ja";
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

  for (const cfg of ANIME_LANES_CONFIG) {
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
      const isComedy = slugs.includes("comedy") || (it.genres || []).includes("comedy");
      if (lid === "anime_comedy" && !isComedy) continue;

      laneIds.push(iid);
    }

    statements.push(...buildLaneEntrySql(lid, laneIds.slice(0, 100), nowTs));
  }

  return statements;
}
