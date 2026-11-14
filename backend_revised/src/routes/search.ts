import { Hono } from 'hono';
import { Bindings, PaginatedMoviesResponse, SearchFilters, Variables } from '../types';
import { TraktSearchService } from '../services/traktsearch';
import { CacheService } from '../services/cache';
import { rowToMovieSummary } from '../services/catalog';

export const searchRouter = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// GET /api/v1/search (Fixed 100 items per page)
searchRouter.get('/', async (c) => {
  const query = c.req.query('query')?.trim() || c.req.query('q')?.trim() || '';

  const page = Math.max(1, Number(c.req.query('page') || 1));
  const PAGE_SIZE = 100;

  const typeParam = (c.req.query('type') || c.req.query('media_type'))?.trim().toLowerCase();
  const media_type: SearchFilters['media_type'] = (typeParam === 'movie' || typeParam === 'tv') ? typeParam : 'all';
  const genre = c.req.query('genre')?.trim().toLowerCase();
  const yearQuery = c.req.query('year')?.trim();
  const year = yearQuery && !isNaN(Number(yearQuery)) ? Number(yearQuery) : undefined;
  const minRatingQuery = c.req.query('min_rating')?.trim();
  const min_rating = minRatingQuery && !isNaN(Number(minRatingQuery)) ? Number(minRatingQuery) : undefined;

  const filters: SearchFilters = { media_type, genre, year, min_rating };

  const origin = new URL(c.req.url).origin;
  const filterKeyPart = `&t=${media_type}&g=${genre || ''}&y=${year || ''}&min_r=${min_rating || ''}`;
  const cacheKey = `${origin}/api/v1/search?q=${encodeURIComponent(query)}&page=${page}${filterKeyPart}`;
  const cacheService = new CacheService();

  const trace = c.get('trace');
  const isRefresh = c.req.query('refresh') === 'true' || c.req.query('cache') === 'false';
  const tCache = Date.now();
  const cached = isRefresh ? null : await cacheService.get<any>(cacheKey);
  if (trace) trace.add(`cache: ${cached ? 'HIT' : 'MISS'} ${Date.now() - tCache}ms`);

  if (cached) {
    return c.json(cached, 200, {
      'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
    });
  }

  // When query is empty, serve popular catalog movies from D1
  if (!query) {
    const conditions: string[] = ['1=1'];
    const params: any[] = [];

    if (filters.media_type && filters.media_type !== 'all') {
      conditions.push('media_type = ?');
      params.push(filters.media_type);
    }
    if (filters.genre) {
      conditions.push('LOWER(genres) LIKE ?');
      params.push(`%"${filters.genre.toLowerCase()}"%`);
    }
    if (filters.year !== undefined) {
      conditions.push('year = ?');
      params.push(filters.year);
    }
    if (filters.min_rating !== undefined && filters.min_rating > 0) {
      conditions.push('rating_score >= ?');
      params.push(filters.min_rating);
    }

    const offset = (page - 1) * PAGE_SIZE;
    const tD1 = Date.now();

    const countRow = await c.env.DB
      .prepare(`SELECT COUNT(*) as total FROM v_movies WHERE ${conditions.join(' AND ')}`)
      .bind(...params)
      .first<{ total: number }>();

    const totalItems = countRow?.total || 0;
    const totalPages = Math.ceil(totalItems / PAGE_SIZE) || 1;

    const rows = await c.env.DB
      .prepare(`SELECT * FROM v_movies WHERE ${conditions.join(' AND ')} ORDER BY votes DESC, rating_score DESC LIMIT ? OFFSET ?`)
      .bind(...params, PAGE_SIZE, offset)
      .all<any>();

    if (trace) trace.add(`d1: POPULAR_CATALOG (${rows.results?.length || 0} items) in ${Date.now() - tD1}ms`);

    const items = (rows.results || []).map((row) => rowToMovieSummary(row));
    const hasMore = page < totalPages;

    const result: PaginatedMoviesResponse = {
      items,
      page,
      total_pages: totalPages,
      total_items: totalItems,
      has_more: hasMore,
      next_page: hasMore ? page + 1 : null,
    };

    if (items.length > 0) {
      await cacheService.set(cacheKey, result, 43200);
      return c.json(result, 200, {
        'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
      });
    }

    return c.json(result, 200, {
      'Cache-Control': 'no-cache, no-store, must-revalidate',
    });
  }

  const trakt = new TraktSearchService(c.env);
  const result = await trakt.search(query, page, PAGE_SIZE, filters, trace);

  if (result.items.length > 0) {
    await cacheService.set(cacheKey, result, 43200);
    return c.json(result, 200, {
      'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
    });
  }

  return c.json(result, 200, {
    'Cache-Control': 'no-cache, no-store, must-revalidate',
  });
});
