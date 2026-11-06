import { Bindings, AdditionalMovieDetails, MovieSummary, Genre, RequestTrace, TvEpisodeSummary, TvSeasonResponse } from '../types/api';
import { CompositeRating, MdblistItem } from '../types/upstream';
import { MdblistService } from './mdblist';
import { ConfigService } from './config';
import { resolveGenres } from '../config/genres';

const RATING_TTL_SECONDS = 86400 * 2;

function isRatingStale(ratingsUpdatedAt?: number | null): boolean {
  if (!ratingsUpdatedAt) return true;
  return ratingsUpdatedAt < Math.floor(Date.now() / 1000) - RATING_TTL_SECONDS;
}

export class CatalogService {
  private db: D1Database;
  private mdblist: MdblistService;
  private tmdbApiKey: string;
  private config: ConfigService;

  constructor(env: Bindings) {
    this.db = env.DB;
    this.mdblist = new MdblistService(env.MDBLIST_API_KEY);
    this.tmdbApiKey = env.TMDB_API_KEY || '';
    this.config = new ConfigService(env.CONFIG_KV);
  }

  // Resolve multiple movie IDs: checks D1 first, batches missing to MDBList, upserts D1, returns in requested order
  async resolveMovies(imdbIds: string[], trace?: RequestTrace, mediaType: 'all' | 'movie' | 'tv' = 'all'): Promise<MovieSummary[]> {
    if (!imdbIds.length) return [];

    // 1. Check D1 for known items
    const lookup = new Map<string, MovieSummary>();
    const missingIds: string[] = [];

    const cleanIds = imdbIds.filter(Boolean);

    const tD1 = Date.now();
    if (this.db && cleanIds.length > 0) {
      const placeholders = cleanIds.map(() => '?').join(',');
      const query = `SELECT * FROM v_movies WHERE imdb_id IN (${placeholders})`;

      const { results } = await this.db.prepare(query).bind(...cleanIds).all<any>();

      for (const row of results || []) {
        if (isRatingStale(row.ratings_updated_at)) continue;

        const summary = rowToMovieSummary(row);
        if (summary.imdb_id) lookup.set(summary.imdb_id, summary);
      }
    }
    const d1ReadDuration = Date.now() - tD1;
    if (trace) {
      trace.add(`d1_read: HIT ${lookup.size}/${cleanIds.length} in ${d1ReadDuration}ms`);
    }

    for (const id of cleanIds) if (!lookup.has(id)) missingIds.push(id);

    // 2. Batch fetch missing items from MDBList
    if (missingIds.length > 0) {
      const tMdb = Date.now();
      const fetchedItems = await this.mdblist.batchMovies(missingIds, mediaType);
      if (trace) trace.add(`mdblist: FETCH ${Date.now() - tMdb}ms (${fetchedItems.length} items)`);

      if (fetchedItems.length > 0) {
        const tUpsert = Date.now();
        const freshSummaries = await this.upsertBatch(fetchedItems);
        if (trace && this.db) trace.add(`d1_upsert: ${Date.now() - tUpsert}ms`);

        for (const summary of freshSummaries) {
          if (summary.imdb_id) lookup.set(summary.imdb_id, summary);
        }
      }
    }

    // 3. Assemble results matching requested ordering
    const finalResults: MovieSummary[] = [];
    for (const id of imdbIds) {
      const item = lookup.get(id);
      if (item) finalResults.push(item);
    }

    return finalResults;
  }

  async resolveByTmdbItems(
    items: Array<{ id: number; media_type: 'movie' | 'tv' }>,
    trace?: RequestTrace
  ): Promise<MovieSummary[]> {
    if (!items.length) return [];

    const lookup = new Map<string, MovieSummary>();
    const compositeKeys = Array.from(new Set(items.map((i) => `${i.media_type}:${i.id}`)));

    const tD1 = Date.now();
    if (this.db && compositeKeys.length > 0) {
      for (let i = 0; i < compositeKeys.length; i += 100) {
        const chunk = compositeKeys.slice(i, i + 100);
        const placeholders = chunk.map(() => '?').join(',');
        const query = `SELECT * FROM v_movies WHERE tmdb_id IN (${placeholders})`;
        const { results } = await this.db.prepare(query).bind(...chunk).all<any>();
        for (const row of results || []) {
          if (isRatingStale(row.ratings_updated_at)) continue;
          const summary = rowToMovieSummary(row);
          if (summary.imdb_id && row.tmdb_id) lookup.set(row.tmdb_id, summary);
        }
      }
    }

    const d1ReadDuration = Date.now() - tD1;
    if (trace) trace.add(`d1_read_tmdb: HIT ${lookup.size}/${items.length} in ${d1ReadDuration}ms`);

    const missingItems: Array<{ id: number; media_type: 'movie' | 'tv' }> = [];
    for (const it of items) {
      const key = `${it.media_type}:${it.id}`;
      if (!lookup.has(key)) missingItems.push(it);
    }

    if (missingItems.length > 0) {
      const tMdb = Date.now();
      const fetchedItems = await this.mdblist.batchByTmdbIds(missingItems);
      if (trace) trace.add(`mdblist_tmdb: FETCH ${Date.now() - tMdb}ms (${fetchedItems.length} items)`);

      if (fetchedItems.length > 0) {
        const tUpsert = Date.now();
        const freshSummaries = await this.upsertBatch(fetchedItems);
        if (trace && this.db) trace.add(`d1_upsert: ${Date.now() - tUpsert}ms`);

        for (const summary of freshSummaries) {
          if (summary.imdb_id && summary.tmdb_id) {
            lookup.set(`${summary.media_type}:${summary.tmdb_id}`, summary);
          }
        }
      }
    }

    return Array.from(lookup.values()).filter((item) => item.imdb_id?.startsWith('tt'));
  }

  // Single movie details lookup: strictly D1 summary + TMDb for cast & extra details. Zero fallbacks.
  async getSingleMovie(tmdb_id: number, media_type: string): Promise<AdditionalMovieDetails | null> {
    let details = <AdditionalMovieDetails>{};
    // Fetch credits & seasons from TMDb if tmdb_id exists
    if (tmdb_id && this.tmdbApiKey) {
      try {
        const mediaEndpoint = media_type === 'tv' ? 'tv' : 'movie';
        const url = `https://api.themoviedb.org/3/${mediaEndpoint}/${tmdb_id}?api_key=${this.tmdbApiKey}&append_to_response=credits`;
        const resp = await fetch(url, {
          headers: { Accept: 'application/json', 'User-Agent': 'CloudflareWorker/1.0' },
          signal: AbortSignal.timeout(6000),
        });

        if (resp.ok) {
          const tmdbData: any = await resp.json();
          if (Array.isArray(tmdbData.credits?.cast)) {
            details.cast = tmdbData.credits.cast.slice(0, 20).map((c: any) => ({
              tmdb_id: c.id,
              name: c.name || '',
              character: c.character || '',
              profile_path: c.profile_path ? `https://image.tmdb.org/t/p/w185${c.profile_path}` : null,
              order: c.order,
            }));
          }
          if (media_type === 'tv') {
            details.status = tmdbData.status || null;
            details.is_ongoing = tmdbData.status === 'Returning Series' || Boolean(tmdbData.in_production);
            if (Array.isArray(tmdbData.seasons)) {
              details.seasons = tmdbData.seasons
                .filter((s: any) => s.season_number > 0)
                .map((s: any) => ({
                  season_number: s.season_number,
                  name: s.name || `Season ${s.season_number}`,
                  episode_count: s.episode_count || 0,
                }));
            }
          }
          return details;
        }
        
      } catch (err: any) {
        console.warn(`[TMDb credits error for ${media_type}:${tmdb_id}]:`, err.message);
      }
    }
    return null;
  }

  async getTvSeason(tmdbId: number, seasonNumber: number): Promise<TvSeasonResponse | null> {
    if (!tmdbId || !this.tmdbApiKey) return null;

    const url = `https://api.themoviedb.org/3/tv/${tmdbId}/season/${seasonNumber}?api_key=${this.tmdbApiKey}`;
    try {
      const resp = await fetch(url, {
        headers: { Accept: 'application/json', 'User-Agent': 'CloudflareWorker/1.0' },
        signal: AbortSignal.timeout(8000),
      });

      if (!resp.ok) return null;

      const data: any = await resp.json();
      const now = Date.now();

      const episodes: TvEpisodeSummary[] = Array.isArray(data.episodes)
        ? data.episodes.map((ep: any) => {
            const airDate = ep.air_date || null;
            const isReleased = Boolean(airDate && new Date(airDate).getTime() <= now);
            return {
              episode_number: ep.episode_number,
              name: ep.name || `Episode ${ep.episode_number}`,
              overview: ep.overview || '',
              still_path: ep.still_path ? `https://image.tmdb.org/t/p/w500${ep.still_path}` : null,
              air_date: airDate,
              runtime: ep.runtime ?? null,
              is_released: isReleased,
            };
          })
        : [];

      return {
        season_number: data.season_number ?? seasonNumber,
        name: data.name || `Season ${seasonNumber}`,
        episode_count: episodes.length,
        episodes,
      };
    } catch (err: any) {
      console.warn(`[TMDb season error for TMDb:${tmdbId} S${seasonNumber}]:`, err.message);
      return null;
    }
  }


  // Bulk upsert into movies and ratings tables
  private async upsertBatch(items: MdblistItem[]): Promise<MovieSummary[]> {
    if (!items.length) return [];
    const now = Math.floor(Date.now() / 1000);
    const statements: D1PreparedStatement[] = [];
    const summaries: MovieSummary[] = [];
    const rules = await this.config.getRatingRules();

    for (const item of items) {
      const comp = MdblistService.computeRating(item, rules);
      const summary = this.mdblistItemToSummary(item, comp);
      if (!summary.imdb_id) continue;
      if (!summary.poster_path && (!item.ratings || item.ratings.length === 0)) continue;
      summaries.push(summary);

      if (!this.db) continue;

      const year = summary.release_date ? Number(summary.release_date.slice(0, 4)) : null;
      const genresJson = JSON.stringify(summary.genres.map((g) => g.slug));

      // Metadata upsert
      statements.push(
        this.db.prepare(`
          INSERT INTO movies (imdb_id, tmdb_id, media_type, title, year, release_date, poster_path, backdrop_path, overview, runtime, genres, original_language, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(imdb_id) DO UPDATE SET
            tmdb_id = COALESCE(excluded.tmdb_id, movies.tmdb_id),
            media_type = excluded.media_type,
            title = excluded.title,
            year = COALESCE(excluded.year, movies.year),
            release_date = COALESCE(NULLIF(excluded.release_date, ''), movies.release_date),
            poster_path = COALESCE(NULLIF(excluded.poster_path, ''), movies.poster_path),
            backdrop_path = COALESCE(NULLIF(excluded.backdrop_path, ''), movies.backdrop_path),
            overview = COALESCE(NULLIF(excluded.overview, ''), movies.overview),
            runtime = COALESCE(excluded.runtime, movies.runtime),
            genres = CASE WHEN excluded.genres != '[]' AND excluded.genres != '' THEN excluded.genres ELSE movies.genres END,
            original_language = COALESCE(NULLIF(excluded.original_language, ''), movies.original_language),
            updated_at = excluded.updated_at
        `).bind(
          summary.imdb_id,
          summary.tmdb_id ? `${summary.media_type}:${summary.tmdb_id}` : null,
          summary.media_type,
          summary.title || 'Unknown',
          year,
          summary.release_date,
          summary.poster_path,
          summary.backdrop_path,
          summary.overview,
          item.runtime || null,
          genresJson,
          item.language || null,
          now
        ),
        this.db.prepare(`
          INSERT INTO ratings (imdb_id, ratings, rating_score, votes, updated_at)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(imdb_id) DO UPDATE SET
            ratings = excluded.ratings,
            rating_score = excluded.rating_score,
            votes = excluded.votes,
            updated_at = excluded.updated_at
        `).bind(summary.imdb_id, comp.ratingsJson, summary.rating_score, summary.vote_count, now)
      );
    }

    if (this.db && statements.length > 0) {
      for (let i = 0; i < statements.length; i += 50) {
        await this.db.batch(statements.slice(i, i + 50));
      }
    }

    return summaries;
  }

  private mdblistItemToSummary(item: MdblistItem, comp: CompositeRating): MovieSummary {
    const rawGenres = item.genres || [];
    const seen = new Set<string>();
    const genres: Genre[] = [];
    for (const g of rawGenres) {
      const rawStr = typeof g === 'string' ? g : String(g?.name || g?.title || g?.slug || '');
      if (!rawStr.trim()) continue;
      for (const resolved of resolveGenres(rawStr)) {
        if (!seen.has(resolved.slug)) {
          seen.add(resolved.slug);
          genres.push(resolved);
        }
      }
    }
    const year = item.year || (item.released ? Number(item.released.slice(0, 4)) : 0);

    return {
      imdb_id: item.ids?.imdb || item.imdbid || '',
      tmdb_id: item.ids?.tmdb || item.tmdbid || null,
      title: item.title || '',
      overview: item.description || '',
      release_date: item.released || (year ? `${year}-01-01` : ''),
      poster_path: item.poster || '',
      backdrop_path: item.backdrop || '',
      rating_score: comp.rating_score,
      vote_count: comp.votes,
      media_type: item.type === 'show' ? 'tv' : 'movie',
      genres,
      original_language: item.language || '',
      runtime: item.runtime ?? 0
    };
  }
}

// Map D1 row to MovieSummary
export function rowToMovieSummary(row: any): MovieSummary {
  const slugs: string[] = row.genres ? JSON.parse(row.genres) : [];
  const genres: Genre[] = slugs.flatMap(resolveGenres);
  const tmdb_id = row.tmdb_id ? Number(row.tmdb_id.split(':')[1]) : null;

  return {
    imdb_id: row.imdb_id,
    tmdb_id,
    title: row.title || '',
    overview: row.overview || '',
    release_date: row.release_date || '',
    poster_path: row.poster_path || '',
    backdrop_path: row.backdrop_path || '',
    rating_score: row.rating_score ?? 0,
    vote_count: row.votes,
    media_type: row.media_type,
    genres,
    original_language: row.original_language || '',
    runtime: row.runtime ?? 0
  };
}
