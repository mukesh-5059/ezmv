import { fetchListItems } from "./mdblist";
import { buildLaneEntrySql } from "./sql";
import { CandidateFeedResult, CatalogItem, RawCandidateItem, TamilLaneConfig } from "./types";

export const TAMIL_LANES_CONFIG: TamilLaneConfig[] = [
  { lane_id: "ta_trending", title: "Trending Now", list_id: 218335, query: "sort=tmdbpopular&sort_order=desc", exclude_lang: "en" },
  { lane_id: "ta_new_releases", title: "New in Theaters", list_id: 218335, query: "sort=released&sort_order=desc&released_to={today}", lang: "ta" },
  { lane_id: "ta_new_ott", title: "New on OTT", list_id: 218335, query: "sort=releasedigital&sort_order=desc", exclude_lang: "en" },
  { lane_id: "ta_top_rated", title: "All-Time Masterpieces", list_id: 218335, query: "sort=letterrating&sort_order=desc", exclude_lang: "en", min_rating: 7.0, min_votes: 5000 },
  { lane_id: "ta_comedy", title: "Popular Comedy", list_id: 218335, query: "sort=tmdbpopular&sort_order=desc&filter_genre=comedy", exclude_lang: "en" },
  { lane_id: "ta_pan_india", title: "South Indian Blockbusters", list_id: 76398, query: "sort=imdbvotes&sort_order=desc" },
];

export async function fetchCandidates(apiKey: string): Promise<CandidateFeedResult> {
  const today = new Date().toISOString().slice(0, 10);
  const feeds: Record<string, RawCandidateItem[]> = {};
  const candidateIds = new Set<string>();

  for (const cfg of TAMIL_LANES_CONFIG) {
    const lid = cfg.lane_id;
    const q = cfg.query.replace("{today}", today);
    let movies = await fetchListItems(apiKey, cfg.list_id, q);

    if (cfg.lang) {
      movies = movies.filter((m) => m.language === cfg.lang);
    }
    if (cfg.exclude_lang) {
      movies = movies.filter((m) => m.language !== cfg.exclude_lang);
    }

    feeds[lid] = movies;
    for (const m of movies) {
      const iid = m.imdb_id || m.ids?.imdb || m.imdbid;
      if (iid && String(iid).startsWith("tt")) {
        candidateIds.add(String(iid));
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
  const cutoff180d = new Date(nowDt.getTime() - 180 * 24 * 60 * 60 * 1000);
  const cutoff90d = new Date(nowDt.getTime() - 90 * 24 * 60 * 60 * 1000);
  const statements: string[] = [];

  const getFeed = (lid: string) => feeds[lid] || [];

  // 1. Trending Now (velocity based)
  const trendingCands: [number, string][] = [];
  for (const [iid, m] of Object.entries(catalog)) {
    if (m.lang !== "ta" || !m.poster || m.runtime < 85 || m.is_excluded_genre) continue;
    if (!m.rel_dt || m.rel_dt < cutoff180d || m.rel_dt > nowDt) continue;
    if (m.imdb_votes + m.lb_votes < 400) continue;

    const ageDays = Math.max(1, Math.floor((nowDt.getTime() - m.rel_dt.getTime()) / (1000 * 60 * 60 * 24)));
    const vel = (m.lb_votes * 1.5 + m.imdb_votes) / (ageDays + 21);
    trendingCands.push([vel, iid]);
  }
  trendingCands.sort((a, b) => b[0] - a[0]);
  statements.push(...buildLaneEntrySql("ta_trending", trendingCands.slice(0, 100).map((c) => c[1]), nowTs));

  // 2. New in Theaters
  const nrCands: [Date, string][] = [];
  for (const [iid, m] of Object.entries(catalog)) {
    if (m.lang !== "ta" || !m.poster || m.runtime < 85 || m.is_excluded_genre) continue;
    if (!m.rel_dt || m.rel_dt < cutoff90d || m.rel_dt > nowDt) continue;
    if (m.imdb_votes < 400 && m.lb_votes < 200) continue;
    nrCands.push([m.rel_dt, iid]);
  }
  nrCands.sort((a, b) => b[0].getTime() - a[0].getTime());
  statements.push(...buildLaneEntrySql("ta_new_releases", nrCands.slice(0, 100).map((c) => c[1]), nowTs));

  // 3. New on OTT
  const ottCands: string[] = [];
  for (const item of getFeed("ta_new_ott")) {
    const iid = item.imdb_id || item.ids?.imdb || item.imdbid;
    const m = catalog[iid];
    if (!m || m.lang === "en" || !m.poster || m.runtime < 85 || m.is_excluded_genre) continue;
    if (m.rel_dt && m.rel_dt > nowDt) continue;
    if (m.votes < 400) continue;
    ottCands.push(iid);
  }
  statements.push(...buildLaneEntrySql("ta_new_ott", ottCands.slice(0, 100), nowTs));

  // 4. All-Time Masterpieces
  const topCands: [number, number, string][] = [];
  for (const item of getFeed("ta_top_rated")) {
    const iid = item.imdb_id || item.ids?.imdb || item.imdbid;
    const m = catalog[iid];
    if (!m || m.lang === "en" || !m.poster || m.votes < 5000 || m.rating_score < 7.0) continue;
    topCands.push([m.rating_score, m.votes, iid]);
  }
  topCands.sort((a, b) => {
    if (b[0] !== a[0]) return b[0] - a[0];
    return b[1] - a[1];
  });
  statements.push(...buildLaneEntrySql("ta_top_rated", topCands.slice(0, 100).map((c) => c[2]), nowTs));

  // 5. Popular Comedy
  const comedyCands: [number, string][] = [];
  for (const item of getFeed("ta_comedy")) {
    const iid = item.imdb_id || item.ids?.imdb || item.imdbid;
    const m = catalog[iid];
    if (!m || m.lang === "en" || !m.poster || !m.slugs?.includes("comedy") || m.votes < 500) continue;
    comedyCands.push([m.votes, iid]);
  }
  comedyCands.sort((a, b) => b[0] - a[0]);
  statements.push(...buildLaneEntrySql("ta_comedy", comedyCands.slice(0, 100).map((c) => c[1]), nowTs));

  // 6. South Indian Blockbusters
  const panCands: [number, string][] = [];
  for (const item of getFeed("ta_pan_india")) {
    const iid = item.imdb_id || item.ids?.imdb || item.imdbid;
    const m = catalog[iid];
    if (m && m.poster && m.votes >= 5000) {
      panCands.push([m.votes, iid]);
    }
  }
  panCands.sort((a, b) => b[0] - a[0]);
  statements.push(...buildLaneEntrySql("ta_pan_india", panCands.slice(0, 100).map((c) => c[1]), nowTs));

  return statements;
}
