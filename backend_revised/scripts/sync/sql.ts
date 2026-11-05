import { RawCandidateItem } from "./types";

export function escapeSql(val: string | null | undefined): string {
  if (val === null || val === undefined) return "NULL";
  const escaped = String(val).replace(/'/g, "''");
  return `'${escaped}'`;
}

export function buildMovieSql(
  imdbId: string,
  item: RawCandidateItem,
  fullItem: RawCandidateItem,
  poster: string,
  runtime: number,
  relStr: string,
  slugs: string[],
  now: number,
  lang: string = ""
): string {
  const isShow = item.type === "show" || fullItem.type === "show";
  const mediaType = isShow ? "tv" : "movie";
  const rawTmdb = item.id || item.ids?.tmdb || fullItem.id || fullItem.ids?.tmdb;
  const numTmdb = rawTmdb ? Number(String(rawTmdb).replace(/^(movie|tv):/, "")) : null;
  const tmdbIdSql = numTmdb && !isNaN(numTmdb) ? `'${mediaType}:${numTmdb}'` : "NULL";
  const title = escapeSql(item.title || fullItem.title || "Unknown");
  const year = item.release_year || fullItem.year || item.year;
  const yearSql = year ? String(Number(year)) : "NULL";
  const relDateSql = escapeSql(relStr ? relStr.slice(0, 10) : year ? `${year}-01-01` : "");
  const posterSql = escapeSql(poster);
  const backdropSql = escapeSql(item.backdrop || fullItem.backdrop || "");
  const overviewSql = escapeSql(item.description || fullItem.description || "");
  const runtimeSql = runtime ? String(Number(runtime)) : "NULL";
  const genresSql = escapeSql(JSON.stringify(slugs));
  const langSql = escapeSql(lang || fullItem.language || item.language || "");

  return (
    `INSERT INTO movies (imdb_id, tmdb_id, media_type, title, year, release_date, poster_path, backdrop_path, overview, runtime, genres, original_language, updated_at) ` +
    `VALUES ('${imdbId}', ${tmdbIdSql}, '${mediaType}', ${title}, ${yearSql}, ${relDateSql}, ${posterSql}, ${backdropSql}, ${overviewSql}, ${runtimeSql}, ${genresSql}, ${langSql}, ${now}) ` +
    `ON CONFLICT(imdb_id) DO UPDATE SET ` +
    `tmdb_id = COALESCE(excluded.tmdb_id, movies.tmdb_id), ` +
    `media_type = excluded.media_type, ` +
    `title = excluded.title, ` +
    `year = COALESCE(excluded.year, movies.year), ` +
    `release_date = CASE WHEN excluded.release_date != '' THEN excluded.release_date ELSE movies.release_date END, ` +
    `poster_path = CASE WHEN excluded.poster_path != '' THEN excluded.poster_path ELSE movies.poster_path END, ` +
    `backdrop_path = CASE WHEN excluded.backdrop_path != '' THEN excluded.backdrop_path ELSE movies.backdrop_path END, ` +
    `overview = CASE WHEN excluded.overview != '' THEN excluded.overview ELSE movies.overview END, ` +
    `runtime = COALESCE(excluded.runtime, movies.runtime), ` +
    `genres = CASE WHEN excluded.genres != '[]' AND excluded.genres != '' THEN excluded.genres ELSE movies.genres END, ` +
    `original_language = CASE WHEN excluded.original_language != '' THEN excluded.original_language ELSE movies.original_language END, ` +
    `updated_at = excluded.updated_at;`
  );
}

export function buildRatingSql(
  imdbId: string,
  ratingsJson: string,
  ratingScore: number,
  votes: number,
  now: number
): string {
  const ratingsSql = escapeSql(ratingsJson);
  return (
    `INSERT INTO ratings (imdb_id, ratings, rating_score, votes, updated_at) ` +
    `VALUES ('${imdbId}', ${ratingsSql}, ${ratingScore}, ${votes}, ${now}) ` +
    `ON CONFLICT(imdb_id) DO UPDATE SET ` +
    `ratings = excluded.ratings, ` +
    `rating_score = excluded.rating_score, ` +
    `votes = excluded.votes, ` +
    `updated_at = excluded.updated_at;`
  );
}

export function buildLaneEntrySql(laneId: string, itemIds: string[], now: number): string[] {
  const statements: string[] = [`DELETE FROM lane_entries WHERE lane_id = '${laneId}';`];
  for (let rank = 1; rank <= itemIds.length; rank++) {
    const iid = itemIds[rank - 1];
    statements.push(
      `INSERT INTO lane_entries (lane_id, imdb_id, rank, updated_at) ` +
        `VALUES ('${laneId}', '${iid}', ${rank}, ${now}) ` +
        `ON CONFLICT(lane_id, imdb_id) DO UPDATE SET ` +
        `rank = excluded.rank, ` +
        `updated_at = excluded.updated_at;`
    );
  }
  return statements;
}
