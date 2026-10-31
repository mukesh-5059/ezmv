import { Bindings, LaneFilters, MovieSummary, RequestTrace } from '../types/api';
import { CatalogService, rowToMovieSummary } from './catalog';

export class LanesService {
  private db: D1Database;
  private catalog: CatalogService;

  constructor(env: Bindings) {
    this.db = env.DB;
    this.catalog = new CatalogService(env);
  }

  // Get lane items from D1 with optional filtering & sorting, resolving missing/stale entries via MDBList on demand
  async getLaneItems(
    laneId: string,
    limit = 100,
    offset = 0,
    filters?: LaneFilters,
    trace?: RequestTrace
  ): Promise<MovieSummary[]> {

    const hasFilters = filters && (
      (filters.media_type && filters.media_type !== 'all') ||
      Boolean(filters.genre) ||
      filters.year !== undefined ||
      filters.min_rating !== undefined ||
      (Boolean(filters.sort_by) && filters.sort_by !== 'popular')
    );

    // Fast-path for default unfiltered lane fetch (uses lane_entries rank order)
    if (!hasFilters) {
      const rows = await this.db
        .prepare('SELECT imdb_id FROM lane_entries WHERE lane_id = ? ORDER BY rank ASC LIMIT ? OFFSET ?')
        .bind(laneId, limit, offset)
        .all<{ imdb_id: string }>();

      if (!rows.results?.length) return [];
      const imdbIds = rows.results.map((r) => r.imdb_id);
      return this.catalog.resolveMovies(imdbIds, trace);
    }

    // Filtered / custom-sorted path: JOIN lane_entries with v_movies directly in D1 SQL
    const conditions: string[] = ['l.lane_id = ?'];
    const params: any[] = [laneId];

    if (filters.media_type && filters.media_type !== 'all') {
      conditions.push('m.media_type = ?');
      params.push(filters.media_type);
    }

    if (filters.genre) {
      conditions.push('LOWER(m.genres) LIKE ?');
      params.push(`%"${filters.genre.toLowerCase()}"%`);
    }

    if (filters.year !== undefined) {
      conditions.push('m.year = ?');
      params.push(filters.year);
    }

    if (filters.min_rating !== undefined && filters.min_rating > 0) {
      conditions.push('m.rating >= ?');
      params.push(filters.min_rating);
    }

    let orderBy = 'l.rank ASC';
    if (filters.sort_by === 'top_rated') {
      orderBy = 'm.rating DESC, m.votes DESC';
    } else if (filters.sort_by === 'newest') {
      orderBy = 'm.release_date DESC';
    } else if (filters.sort_by === 'oldest') {
      orderBy = 'm.release_date ASC';
    } else if (filters.sort_by === 'title') {
      orderBy = 'm.title ASC';
    }

    const tD1 = Date.now();
    const querySql = `
      SELECT m.* 
      FROM lane_entries l
      JOIN v_movies m ON l.imdb_id = m.imdb_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY ${orderBy}
      LIMIT ? OFFSET ?
    `;

    const rows = await this.db
      .prepare(querySql)
      .bind(...params, limit, offset)
      .all<any>();

    if (trace) trace.add(`d1: FILTERED_LANE (${rows.results?.length || 0} items) in ${Date.now() - tD1}ms`);

    if (!rows.results?.length) return [];

    return rows.results.map((row) => rowToMovieSummary(row));
  }
}
