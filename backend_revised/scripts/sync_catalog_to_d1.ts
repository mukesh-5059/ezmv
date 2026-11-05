#!/usr/bin/env npx tsx
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import {
  normalizeGenreSlugs,
  resolveApiKey,
  resolveCfAccountId,
  resolveTraktClientId,
} from "./sync/config";
import { fetchBatchDetails } from "./sync/mdblist";
import { computeCompositeRating } from "./sync/rating";
import { buildMovieSql, buildRatingSql } from "./sync/sql";
import { CatalogItem, RawCandidateItem } from "./sync/types";
import * as tamil from "./sync/tamil";
import * as english from "./sync/english";
import * as anime from "./sync/anime";

export function executeSeed(sqlFile: string, isLocal: boolean): boolean {
  if (!fs.existsSync(sqlFile)) {
    console.error(`[D1 Execution Error] SQL file not found: ${sqlFile}`);
    return false;
  }

  const backendDir = path.resolve(__dirname, "..");
  const targetName = isLocal ? "Local D1" : "Remote Production D1";
  const targetFlag = isLocal ? "--local" : "--remote";
  const fileName = path.basename(sqlFile);

  console.log(`\n[D1 Execution] Seeding data to ${targetName} (${targetFlag})...`);
  const cmd = `npx wrangler d1 execute movies-catalog ${targetFlag} --file=${fileName} --yes`;

  const env = { ...process.env };
  if (!isLocal) {
    const accountId = resolveCfAccountId();
    if (accountId && !env.CLOUDFLARE_ACCOUNT_ID) {
      env.CLOUDFLARE_ACCOUNT_ID = accountId;
    }
  }

  try {
    execSync(cmd, { cwd: backendDir, env, stdio: "inherit" });
    console.log(`[D1 Execution] Successfully seeded data to ${targetName}!`);
    return true;
  } catch (e: any) {
    console.error(`[D1 Execution Error] Failed to seed data to ${targetName}: ${e.message}`);
    return false;
  }
}

export async function generateSyncSql(
  apiKey: string,
  traktClientId: string,
  outSqlFile: string
): Promise<number> {
  const nowDt = new Date();
  const nowTs = Math.floor(nowDt.getTime() / 1000);
  const statements: string[] = [];

  // 1. Gather candidate feeds & IDs across all dashboards
  console.log("[1/4] Fetching candidate items from dashboards...");

  console.log("  -> Fetching Tamil candidate feeds (MDBList)...");
  const { feeds: tamilFeeds, candidateIds: tamilIds } = await tamil.fetchCandidates(apiKey);
  console.log(`     Found ${tamilIds.size} unique Tamil candidates.`);

  console.log("  -> Fetching English candidate feeds (Trakt)...");
  const { feeds: englishFeeds, candidateIds: englishIds } = await english.fetchCandidates(traktClientId);
  console.log(`     Found ${englishIds.size} unique English candidates.`);

  console.log("  -> Fetching Anime candidate feeds (Trakt anime)...");
  const { feeds: animeFeeds, candidateIds: animeIds } = await anime.fetchCandidates(traktClientId);
  console.log(`     Found ${animeIds.size} unique Anime candidates.`);

  const allUniqueIds = new Set<string>([...tamilIds, ...englishIds, ...animeIds]);
  console.log(`[2/4] Total unique candidate IDs across all dashboards: ${allUniqueIds.size}`);

  // Index candidates for fallback metadata
  const itemLookup: Record<string, RawCandidateItem> = {};
  for (const feeds of [tamilFeeds, englishFeeds, animeFeeds]) {
    for (const feed of Object.values(feeds)) {
      for (const m of feed) {
        const iid = m.imdb_id || m.ids?.imdb || m.imdbid;
        if (iid && !itemLookup[iid]) {
          itemLookup[iid] = m;
        }
      }
    }
  }

  // 2. Batch enrich metadata and multi-source ratings
  console.log(`  -> Batch fetching metadata from MDBList for ${allUniqueIds.size} titles...`);
  const batchDetails = await fetchBatchDetails(apiKey, Array.from(allUniqueIds));

  // 3. Build enriched catalog & SQL for movies and ratings
  console.log("[3/4] Building enriched catalog and generating movies/ratings SQL...");
  const catalog: Record<string, CatalogItem> = {};

  for (const imdbId of allUniqueIds) {
    const item = itemLookup[imdbId] || {};
    const fullItem = { ...item, ...(batchDetails[imdbId] || {}) };

    const { ratingScore, votes, ratingsJson } = computeCompositeRating(fullItem);
    const poster = fullItem.poster || item.poster || "";
    const runtime = Number(fullItem.runtime || item.runtime || 0);
    const lang = fullItem.language || item.language || "";
    const relStr = fullItem.released || fullItem.release_date || item.release_date || "";

    let relDt: Date | null = null;
    if (relStr && relStr.length >= 10) {
      try {
        const [y, m, d] = relStr.slice(0, 10).split("-").map(Number);
        relDt = new Date(Date.UTC(y, m - 1, d));
      } catch {}
    }

    const rawGenres: any[] = [...(item.genres || []), ...(fullItem.genres || [])];
    const seenGenres = new Set<string>();
    const slugs: string[] = [];
    for (const g of rawGenres) {
      const rawStr = typeof g === "string" ? g : g?.name || g?.title || g?.slug || "";
      if (!rawStr) continue;
      for (const slug of normalizeGenreSlugs(rawStr)) {
        if (slug && !seenGenres.has(slug)) {
          seenGenres.add(slug);
          slugs.push(slug);
        }
      }
    }

    const isExcludedGenre = slugs.some((s) => ["documentary", "short", "animation"].includes(s));
    const imdbVotes = Number(
      (fullItem.ratings || []).find((r: any) => r.source === "imdb")?.votes || 0
    );
    const lbVotes = Number(
      (fullItem.ratings || []).find((r: any) => r.source === "letterboxd")?.votes || 0
    );

    catalog[imdbId] = {
      imdb_id: imdbId,
      full_item: fullItem,
      item,
      rating_score: ratingScore,
      votes,
      ratings_json: ratingsJson,
      poster,
      runtime,
      lang,
      rel_str: relStr,
      rel_dt: relDt,
      slugs,
      is_excluded_genre: isExcludedGenre,
      imdb_votes: imdbVotes,
      lb_votes: lbVotes,
    };

    statements.push(buildMovieSql(imdbId, item, fullItem, poster, runtime, relStr, slugs, nowTs, lang));
    statements.push(buildRatingSql(imdbId, ratingsJson, ratingScore, votes, nowTs));
  }

  // 4. Emit lane SQL per dashboard
  console.log("[4/4] Generating dashboard lane assignments...");
  const tamilLaneStmts = tamil.generateLaneSql(catalog, tamilFeeds, nowDt, nowTs);
  const englishLaneStmts = english.generateLaneSql(catalog, englishFeeds, nowDt, nowTs);
  const animeLaneStmts = anime.generateLaneSql(catalog, animeFeeds, nowDt, nowTs);

  statements.push(...tamilLaneStmts);
  statements.push(...englishLaneStmts);
  statements.push(...animeLaneStmts);

  fs.mkdirSync(path.dirname(outSqlFile), { recursive: true });
  fs.writeFileSync(outSqlFile, statements.join("\n\n") + "\n", "utf-8");

  console.log(`[Done] Generated ${statements.length} total SQL statements -> ${outSqlFile}`);
  return statements.length;
}

// CLI entry point
if (require.main === module || process.argv[1]?.endsWith("sync_catalog_to_d1.ts")) {
  const args = process.argv.slice(2);
  const executeFlag = args.includes("--execute");

  let apiKeyArg: string | undefined;
  let traktIdArg: string | undefined;
  let outputArg = path.resolve(__dirname, "../sync_catalog.sql");

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--api-key" && args[i + 1]) apiKeyArg = args[++i];
    if (args[i] === "--trakt-client-id" && args[i + 1]) traktIdArg = args[++i];
    if (args[i] === "--output" && args[i + 1]) outputArg = path.resolve(args[++i]);
  }

  const apiKey = resolveApiKey(apiKeyArg);
  const traktClientId = resolveTraktClientId(traktIdArg);
  const isRemote = args.includes("--remote");
  const isLocal = !isRemote;

  if (isLocal) {
    console.log("[Mode] Targeting Local D1 database (--local).");
  } else {
    console.log("[Mode] Targeting Remote Cloudflare D1 database (--remote).");
  }

  generateSyncSql(apiKey, traktClientId, outputArg)
    .then(() => {
      if (executeFlag) {
        executeSeed(outputArg, isLocal);
      } else {
        console.log("\n[D1 Execution Skipped] SQL file generated only. Pass --execute to seed D1.");
      }
    })
    .catch((err) => {
      console.error("[Fatal Error]", err);
      process.exit(1);
    });
}
