import { Bindings, MovieDetails, MovieSummary, MdblistItem, GenreItem, RequestTrace } from '../types';
import { MdblistService } from './mdblist';

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
  async resolveMovies(imdbIds: string[], trace?: RequestTrace): Promise<MovieSummary[]> {
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

        const summary = this.rowToMovieSummary(row);
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
      const fetchedItems = await this.mdblist.batchMovies(missingIds);
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
    if (!this.db) return null;

    const row = await this.db
      .prepare('SELECT * FROM v_movies WHERE imdb_id = ? LIMIT 1')
      .bind(imdbId)
      .first<any>();

    if (!row || !row.title) {
      return null;
    }

    let genres: GenreItem[] = [];
    try {
      const parsed = typeof row.genres === 'string' ? JSON.parse(row.genres) : [];
      genres = parsed.map((g: any) => ({ mdb_id: g.id, name: g.title || g.name || '' }));
    } catch (_) {}

    const details: MovieDetails = {
      ...this.rowToMovieSummary(row),
      runtime: row.runtime || null,
      genres,
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

  // Get lane items from D1, resolving missing/stale entries via MDBList on demand
  async getLaneItems(laneId: string, limit = 100, offset = 0, trace?: RequestTrace): Promise<MovieSummary[]> {
    if (!this.db) return [];

    const rows = await this.db
      .prepare('SELECT imdb_id FROM lane_entries WHERE lane_id = ? ORDER BY rank ASC LIMIT ? OFFSET ?')
      .bind(laneId, limit, offset)
      .all<{ imdb_id: string }>();

    if (!rows.results?.length) return [];

    const imdbIds = rows.results.map((r) => r.imdb_id);
    return this.resolveMovies(imdbIds, trace);
  }

  // Bulk upsert into movies and ratings tables
  private async upsertBatch(items: MdblistItem[]): Promise<void> {
    if (!this.db || !items.length) return;
    const now = Math.floor(Date.now() / 1000);

    const statements: D1PreparedStatement[] = [];

    for (const item of items) {
      const imdbId = item.ids?.imdb || item.imdbid;
      if (!imdbId) continue;

      const tmdbId = item.ids?.tmdb || item.tmdbid || null;
      const mediaType = item.type === 'show' ? 'tv' : 'movie';
      const title = item.title || 'Unknown';
      const year = item.year || (item.released ? Number(item.released.slice(0, 4)) : null);
      const releaseDate = item.released || (year ? `${year}-01-01` : '');
      const posterPath = item.poster || '';
      const backdropPath = item.backdrop || '';
      const overview = item.description || '';
      const runtime = item.runtime || null;
      const genresJson = JSON.stringify(item.genres || []);

      const rating = MdblistService.parseRating(item);
      const votes = MdblistService.parseVotes(item);

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
        `).bind(imdbId, tmdbId, mediaType, title, year, releaseDate, posterPath, backdropPath, overview, runtime, genresJson, now)
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
        `).bind(imdbId, rating, votes, now)
      );
    }

    if (statements.length > 0) {
      await this.db.batch(statements);
    }
  }

  // Row mappings
  private rowToMovieSummary(row: any): MovieSummary {
    let genreIds: number[] = [];
    try {
      const parsed = typeof row.genres === 'string' ? JSON.parse(row.genres) : [];
      genreIds = parsed.map((g: any) => g.id).filter((id: any): id is number => typeof id === 'number');
    } catch (_) {}

    return {
      imdb_id: row.imdb_id,
      tmdb_id: row.tmdb_id || 0,
      title: row.title || '',
      overview: row.overview || '',
      release_date: row.release_date || '',
      poster_path: row.poster_path || '',
      backdrop_path: row.backdrop_path || '',
      rating: Number(row.rating || 0),
      vote_count: Number(row.votes || 0),
      media_type: row.media_type || 'movie',
      genre_ids: genreIds,
    };
  }


  private mdblistItemToSummary(item: MdblistItem): MovieSummary {
    const genreIds = (item.genres || []).map((g) => g.id);
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
      genre_ids: genreIds,
    };
  }
}
