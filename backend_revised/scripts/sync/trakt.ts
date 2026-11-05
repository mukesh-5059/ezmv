import { RawCandidateItem } from "./types";

const TRAKT_BASE_URL = "https://api.trakt.tv";

export async function traktGet(
  traktClientId: string,
  pathStr: string,
  params?: Record<string, string | number>
): Promise<any> {
  const queryStr = params
    ? `?${new URLSearchParams(
        Object.entries(params).map(([k, v]) => [k, String(v)])
      ).toString()}`
    : "";
  const cleanPath = pathStr.replace(/^\//, "");
  const url = `${TRAKT_BASE_URL}/${cleanPath}${queryStr}`;

  try {
    const res = await fetch(url, {
      headers: {
        "Content-Type": "application/json",
        "trakt-api-version": "2",
        "trakt-api-key": traktClientId,
        "User-Agent": "MDBListSync/1.0",
      },
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

export async function fetchTraktItems(
  traktClientId: string,
  endpoint: string,
  params?: Record<string, string | number>
): Promise<RawCandidateItem[]> {
  const data = (await traktGet(traktClientId, endpoint, params)) || [];
  const items: RawCandidateItem[] = [];

  for (const it of data) {
    const target = it.movie || it.show || it;
    const ids = target.ids || {};
    const imdbId = ids.imdb;
    if (!imdbId || !String(imdbId).startsWith("tt")) continue;

    const isShow = Boolean(it.show || target.aired_episodes || endpoint.includes("/shows"));
    items.push({
      imdb_id: String(imdbId),
      ids,
      title: target.title || "",
      year: target.year,
      type: isShow ? "show" : "movie",
      language: target.language || "en",
      genres: target.genres || [],
    });
  }

  return items;
}
