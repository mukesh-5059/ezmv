import { Bindings, MovieDetails, MovieSummary, Genre, RequestTrace } from '../types/api';
import { MdblistItem } from '../types/upstream';
import { MdblistService } from './mdblist';
import { resolveGenres } from '../config/genres';

export class CatalogService {
  private db: D1Database;
  private mdblist: MdblistService;
  private tmdbApiKey: string;

  constructor(env: Bindings) {
    this.db = env.DB;
    this.mdblist = new MdblistService(env.MDBLIST_API_KEY);
    this.tmdbApiKey = env.TMDB_API_KEY || '';
  }

  // Resolve multiple movie IDs: checks D1 first, batches missing to MDBList, upserts D1, returns in requested order
  async resolveMovies(imdbIds: string[], trace?: RequestTrace, mediaType: 'all' | 'movie' | 'tv' = 'all'): Promise<MovieSummary[]> {
    if (!imdbIds.length) return [];

    const now = Math.floor(Date.now() / 1000);
    const staleRatingThreshold = now - 86400 * 2; // 48 hours

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
        const isRatingStale = !row.ratings_updated_at || row.ratings_updated_at < staleRatingThreshold;
        if (isRatingStale) continue; // treat as needing refresh

        const summary = rowToMovieSummary(row);
        if (summary.imdb_id) lookup.set(summary.imdb_id, summary);
      }
    }
    const d1ReadDuration = Date.now() - tD1;
    if (trace) {
      trace.add(`d1_read: HIT ${lookup.size}/${cleanIds.length} in ${d1ReadDuration}ms`);
    }

    // Identify which requested items are missing or stale
    for (const id of cleanIds) {
      if (!lookup.has(id)) {
        missingIds.push(id);
      }
    }

    // 2. Batch fetch missing items from MDBList
    if (missingIds.length > 0) {
      const tMdb = Date.now();
      const fetchedItems = await this.mdblist.batchMovies(missingIds, mediaType);
      if (trace) trace.add(`mdblist: FETCH ${Date.now() - tMdb}ms (${fetchedItems.length} items)`);

      if (fetchedItems.length > 0 && this.db) {
        const tUpsert = Date.now();
        await this.upsertBatch(fetchedItems);
        if (trace) trace.add(`d1_upsert: ${Date.now() - tUpsert}ms`);

        // Populate lookup map with fresh items
        for (const item of fetchedItems) {
          const summary = this.mdblistItemToSummary(item);
          if (summary.imdb_id) lookup.set(summary.imdb_id, summary);
        }
      }
    }

    // 3. Assemble results matching requested ordering
    const finalResults: MovieSummary[] = [];
    for (const id of imdbIds) {
      const item = lookup.get(id);
      if (item) {
        finalResults.push(item);
      }
    }

    return finalResults;
  }

  // Single movie details lookup: strictly D1 summary + TMDb for cast & extra details. Zero fallbacks.
  async getSingleMovie(imdbId: string): Promise<MovieDetails | null> {
    const row = await this.db
      .prepare('SELECT * FROM v_movies WHERE imdb_id = ? LIMIT 1')
      .bind(imdbId)
      .first<any>();

    if (!row) return null;

    const details: MovieDetails = {
      ...rowToMovieSummary(row),
      runtime: row.runtime || null,
      cast: [],
      seasons: [],
    };

    // Fetch credits & seasons from TMDb if tmdb_id exists
    if (details.tmdb_id && this.tmdbApiKey) {
      try {
        const mediaEndpoint = details.media_type === 'tv' ? 'tv' : 'movie';
        const url = `https://api.themoviedb.org/3/${mediaEndpoint}/${details.tmdb_id}?api_key=${this.tmdbApiKey}&append_to_response=credits`;
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
          if (details.media_type === 'tv' && Array.isArray(tmdbData.seasons)) {
            details.seasons = tmdbData.seasons.map((s: any) => ({
              season_number: s.season_number,
              name: s.name,
              episode_count: s.episode_count,
              poster_path: s.poster_path ? `https://image.tmdb.org/t/p/w500${s.poster_path}` : null,
            }));
          }
        }
      } catch (err: any) {
        console.warn(`[TMDb credits error for ${imdbId}]:`, err.message);
      }
    }

    return details;
  }


  // Bulk upsert into movies and ratings tables
  private async upsertBatch(items: MdblistItem[]): Promise<void> {
    if (!items.length) return;
    const now = Math.floor(Date.now() / 1000);
    const statements: D1PreparedStatement[] = [];

    for (const item of items) {
      const summary = this.mdblistItemToSummary(item);
      if (!summary.imdb_id) continue;

      const year = summary.release_date ? Number(summary.release_date.slice(0, 4)) : null;
      const genresJson = JSON.stringify(summary.genres.map((g) => g.slug));

      // Metadata upsert
      statements.push(
        this.db.prepare(`
          INSERT INTO movies (imdb_id, tmdb_id, media_type, title, year, release_date, poster_path, backdrop_path, overview, runtime, genres, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(imdb_id) DO UPDATE SET
            tmdb_id = COALESCE(excluded.tmdb_id, movies.tmdb_id),
            media_type = excluded.media_type,
            title = excluded.title,
            year = COALESCE(excluded.year, movies.year),
            release_date = COALESCE(excluded.release_date, movies.release_date),
            poster_path = COALESCE(excluded.poster_path, movies.poster_path),
            backdrop_path = COALESCE(excluded.backdrop_path, movies.backdrop_path),
            overview = COALESCE(excluded.overview, movies.overview),
            runtime = COALESCE(excluded.runtime, movies.runtime),
            genres = excluded.genres,
            updated_at = excluded.updated_at
        `).bind(
          summary.imdb_id,
          summary.tmdb_id || null,
          summary.media_type,
          summary.title || 'Unknown',
          year,
          summary.release_date,
          summary.poster_path,
          summary.backdrop_path,
          summary.overview,
          item.runtime || null,
          genresJson,
          now
        )
      );

      // Rating upsert
      statements.push(
        this.db.prepare(`
          INSERT INTO ratings (imdb_id, rating, votes, updated_at)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(imdb_id) DO UPDATE SET
            rating = excluded.rating,
            votes = excluded.votes,
            updated_at = excluded.updated_at
        `).bind(summary.imdb_id, summary.rating, summary.vote_count, now)
      );
    }

    if (statements.length > 0) {
      await this.db.batch(statements);
    }
  }

  private mdblistItemToSummary(item: MdblistItem): MovieSummary {
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
      tmdb_id: item.ids?.tmdb || item.tmdbid || 0,
      title: item.title || '',
      overview: item.description || '',
      release_date: item.released || (year ? `${year}-01-01` : ''),
      poster_path: item.poster || '',
      backdrop_path: item.backdrop || '',
      rating: MdblistService.parseRating(item),
      vote_count: MdblistService.parseVotes(item),
      media_type: item.type === 'show' ? 'tv' : 'movie',
      genres,
    };
  }
}

// Map D1 row to MovieSummary
export function rowToMovieSummary(row: any): MovieSummary {
  const slugs: string[] = row.genres ? JSON.parse(row.genres) : [];
  const genres: Genre[] = slugs.flatMap(resolveGenres);

  return {
    imdb_id: row.imdb_id,
    tmdb_id: row.tmdb_id || 0,
    title: row.title || '',
    overview: row.overview || '',
    release_date: row.release_date || '',
    poster_path: row.poster_path || '',
    backdrop_path: row.backdrop_path || '',
    rating: row.rating,
    vote_count: row.votes,
    media_type: row.media_type,
    genres,
  };
}
