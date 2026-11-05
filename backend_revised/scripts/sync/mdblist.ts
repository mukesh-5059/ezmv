import fs from "node:fs";
import { RawCandidateItem } from "./types";

const MDBLIST_BASE_URL = "https://api.mdblist.com";

export async function fetchListItems(
  apiKey: string,
  listId: number,
  queryStr: string = ""
): Promise<RawCandidateItem[]> {
  let url = `${MDBLIST_BASE_URL}/lists/${listId}/items?limit=1000&append_to_response=genres,poster,description,ratings&apikey=${apiKey}`;
  if (queryStr) {
    url += `&${queryStr}`;
  }

  const res = await fetch(url, {
    headers: {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      Accept: "application/json",
    },
  });

  if (!res.ok) {
    throw new Error(`Failed to fetch list ${listId}: ${res.statusText}`);
  }

  const data = (await res.json()) as any;
  return [...(data.movies || []), ...(data.shows || [])];
}

export async function fetchBatchDetails(
  apiKey: string,
  imdbIds: string[]
): Promise<Record<string, RawCandidateItem>> {
  const lookup: Record<string, RawCandidateItem> = {};
  if (!imdbIds || imdbIds.length === 0) return lookup;

  const cacheFile = "/tmp/mdblist_batch_cache.json";
  let idsToFetch = [...imdbIds];

  if (fs.existsSync(cacheFile)) {
    try {
      const cached = JSON.parse(fs.readFileSync(cacheFile, "utf-8"));
      Object.assign(lookup, cached);
      idsToFetch = idsToFetch.filter((iid) => !lookup[iid]);
      console.log(`  [Cache] Loaded ${Object.keys(lookup).length} items from ${cacheFile}. ${idsToFetch.length} missing.`);
      if (idsToFetch.length === 0) return lookup;
    } catch (e: any) {
      console.log(`  [Cache Warning] Could not load cache: ${e.message}`);
    }
  }

  const chunkSize = 100;

  async function batchQuery(targetType: "movie" | "show", ids: string[]) {
    const chunks: string[][] = [];
    for (let i = 0; i < ids.length; i += chunkSize) {
      chunks.push(ids.slice(i, i + chunkSize));
    }

    const concurrency = 3;
    for (let i = 0; i < chunks.length; i += concurrency) {
      const slice = chunks.slice(i, i + concurrency);
      await Promise.all(
        slice.map(async (chunk, chunkIdx) => {
          const res = await fetch(`${MDBLIST_BASE_URL}/imdb/${targetType}/?apikey=${apiKey}`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "User-Agent": "MDBListSync/1.0",
            },
            body: JSON.stringify({ ids: chunk }),
          });

          if (!res.ok) {
            const errText = await res.text().catch(() => "");
            throw new Error(
              `MDBList batch query failed for ${targetType} chunk ${i + chunkIdx}: HTTP ${res.status} ${res.statusText} - ${errText}`
            );
          }

          const items = (await res.json()) as any[];
          if (!Array.isArray(items)) {
            throw new Error(`MDBList batch query returned unexpected response: ${JSON.stringify(items)}`);
          }

          for (const item of items) {
            const iid = item.imdbid || item.ids?.imdb;
            if (iid) {
              lookup[iid] = item;
            }
          }
        })
      );
    }
  }

  console.log(`  -> Concurrently fetching ${idsToFetch.length} movie batch ratings...`);
  await batchQuery("movie", idsToFetch);

  const unresolved = idsToFetch.filter((iid) => !lookup[iid]);
  if (unresolved.length > 0) {
    console.log(`  -> Concurrently fetching ${unresolved.length} show/anime batch ratings...`);
    await batchQuery("show", unresolved);
  }

  try {
    fs.writeFileSync(cacheFile, JSON.stringify(lookup), "utf-8");
    console.log(`  [Cache] Saved ${Object.keys(lookup).length} items to ${cacheFile}.`);
  } catch (e: any) {
    console.log(`  [Cache Warning] Could not save cache: ${e.message}`);
  }

  return lookup;
}
