import { Hono } from 'hono';
import { Bindings, SearchFilters, Variables } from '../types';
import { TraktSearchService } from '../services/traktsearch';
import { CacheService } from '../services/cache';

export const searchRouter = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// GET /api/v1/search (Fixed 100 items per page)
searchRouter.get('/', async (c) => {
  const query = c.req.query('query')?.trim() || c.req.query('q')?.trim();
  if (!query) {
    return c.json({ items: [], page: 1, total_pages: 0, total_items: 0, has_more: false, next_page: null });
  }

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
  const tCache = Date.now();
  const cached = await cacheService.get<any>(cacheKey);
  if (trace) trace.add(`cache: ${cached ? 'HIT' : 'MISS'} ${Date.now() - tCache}ms`);

  if (cached) {
    return c.json(cached, 200, {
      'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
    });
  }

  const trakt = new TraktSearchService(c.env);
  const result = await trakt.search(query, page, PAGE_SIZE, filters, trace);

  if (result.items.length > 0) {
    await cacheService.set(cacheKey, result, 43200);
  }

  return c.json(result, 200, {
    'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
  });
});
