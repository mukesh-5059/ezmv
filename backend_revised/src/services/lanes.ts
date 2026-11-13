import { Bindings, Genre, LaneConfig, LaneFilters, MovieSummary, PaginatedLaneResponse, RequestTrace } from '../types/api';
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
    lane: LaneConfig,
    page = 1,
    limit = 100,
    filters?: LaneFilters,
    trace?: RequestTrace
  ): Promise<PaginatedLaneResponse> {
    const validPage = Math.max(1, page);
    const offset = (validPage - 1) * limit;

    const emptyResponse: PaginatedLaneResponse = {
      id: lane.id,
      title: lane.title,
      items: [],
      page: validPage,
      total_pages: 0,
      total_items: 0,
      has_more: false,
      next_page: null,
    };

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
        .bind(lane.id, limit, offset)
        .all<{ imdb_id: string }>();

      if (!rows.results?.length) return emptyResponse;
      const imdbIds = rows.results.map((r) => r.imdb_id);
      const items = await this.catalog.resolveMovies(imdbIds, trace);
      const hasMore = items.length >= limit;
      return {
        id: lane.id,
        title: lane.title,
        items,
        page: validPage,
        total_pages: hasMore ? validPage + 1 : validPage,
        total_items: hasMore ? (validPage * limit) + 1 : ((validPage - 1) * limit) + items.length,
        has_more: hasMore,
        next_page: hasMore ? validPage + 1 : null,
      };
    }

    // Filtered / custom-sorted path: JOIN lane_entries with v_movies directly in D1 SQL
    const conditions: string[] = ['l.lane_id = ?'];
    const params: any[] = [lane.id];

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
      conditions.push('m.rating_score >= ?');
      params.push(filters.min_rating);
    }

    let orderBy = 'l.rank ASC';
    if (filters.sort_by === 'top_rated') {
      orderBy = 'm.rating_score DESC, m.votes DESC';
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

    if (!rows.results?.length) return emptyResponse;

    const items = rows.results.map((row) => rowToMovieSummary(row));
    const hasMore = items.length >= limit;
    return {
      id: lane.id,
      title: lane.title,
      items,
      page: validPage,
      total_pages: hasMore ? validPage + 1 : validPage,
      total_items: hasMore ? (validPage * limit) + 1 : ((validPage - 1) * limit) + items.length,
      has_more: hasMore,
      next_page: hasMore ? validPage + 1 : null,
    };
  }

  // Pre-computes up to 5 featured billboard hero titles for a given dashboard
  computeBillboard(dashboardId: string, lanes: PaginatedLaneResponse[]): MovieSummary[] {
    const seenIds = new Set<string>();
    const candidates: MovieSummary[] = [];

    const addCandidate = (m: MovieSummary) => {
      if (m.backdrop_path && !seenIds.has(m.imdb_id)) {
        seenIds.add(m.imdb_id);
        candidates.push(m);
      }
    };

    const getLane = (...ids: string[]) => lanes.find((l) => ids.some((id) => l.id.toLowerCase().includes(id)));

    if (dashboardId === 'tamil') {
      const newOtt = getLane('new_ott');
      const trending = getLane('trending');
      const isComedy = (m: MovieSummary) => m.genres?.some((g: Genre) => g.name.toLowerCase() === 'comedy' || g.slug.toLowerCase() === 'comedy');

      if (newOtt && trending) {
        const trendingIds = new Set(trending.items.map((m) => m.imdb_id));
        for (const m of newOtt.items) {
          if (trendingIds.has(m.imdb_id) && isComedy(m)) addCandidate(m);
        }
      }
      if (candidates.length < 5 && trending) {
        for (const m of trending.items) {
          if (candidates.length >= 5) break;
          if (isComedy(m)) addCandidate(m);
        }
      }
      if (candidates.length < 5) {
        for (const lane of lanes) {
          for (const m of lane.items) {
            if (candidates.length >= 5) break;
            if (isComedy(m)) addCandidate(m);
          }
        }
      }
    } else if (dashboardId === 'english') {
      const trending = getLane('trending');
      const newReleases = getLane('releases');

      if (trending && newReleases) {
        const trendingIds = new Set(trending.items.map((m) => m.imdb_id));
        for (const m of newReleases.items) {
          if (trendingIds.has(m.imdb_id)) addCandidate(m);
        }
      }
      if (candidates.length < 5 && trending) {
        for (const m of trending.items) {
          if (candidates.length >= 5) break;
          addCandidate(m);
        }
      }
      if (candidates.length < 5 && newReleases) {
        for (const m of newReleases.items) {
          if (candidates.length >= 5) break;
          addCandidate(m);
        }
      }
    } else if (dashboardId === 'anime') {
      const trending = getLane('trending');
      const movies = getLane('movies');

      if (trending) {
        for (const m of trending.items) {
          if (candidates.length >= 5) break;
          addCandidate(m);
        }
      }
      if (candidates.length < 5 && movies) {
        for (const m of movies.items) {
          if (candidates.length >= 5) break;
          addCandidate(m);
        }
      }
    }

    // Universal Fallback: fill up to 5 with highest popularity in dashboard
    if (candidates.length < 5) {
      const allRemaining: MovieSummary[] = [];
      for (const lane of lanes) {
        for (const m of lane.items) {
          if (m.backdrop_path && !seenIds.has(m.imdb_id)) {
            seenIds.add(m.imdb_id);
            allRemaining.push(m);
          }
        }
      }
      allRemaining.sort((a, b) => b.vote_count - a.vote_count);
      for (const m of allRemaining) {
        if (candidates.length >= 5) break;
        candidates.push(m);
      }
    }

    candidates.sort((a, b) => b.vote_count - a.vote_count);
    return candidates.slice(0, 5);
  }
}
