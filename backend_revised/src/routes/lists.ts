import { Hono } from 'hono';
import { Bindings, ListFilters, Variables } from '../types';
import { ListsService } from '../services/lists';
import { CacheService } from '../services/cache';

export const listsRouter = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// GET /api/v1/lists/popular (Paginated popular curated lists)
listsRouter.get('/popular', async (c) => {
  const page = Math.max(1, Number(c.req.query('page') || 1));
  const PAGE_SIZE = 100;

  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/lists/popular?page=${page}`;
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

  const tTrakt = Date.now();
  const listsService = new ListsService(c.env);
  const result = await listsService.getPopularLists(page, PAGE_SIZE);
  if (trace) trace.add(`trakt fetch: ${result.items.length} items ${Date.now() - tTrakt}ms`);

  if (result.items.length > 0) await cacheService.set(cacheKey, result, 43200);

  return c.json(result, 200, {
    'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
  });
});

// GET /api/v1/lists/search (Search curated lists by query)
listsRouter.get('/search', async (c) => {
  const query = c.req.query('query')?.trim() || c.req.query('q')?.trim() || '';
  const page = Math.max(1, Number(c.req.query('page') || 1));
  const PAGE_SIZE = 50;

  if (!query) return c.redirect(`/api/v1/lists/popular?page=${page}`);

  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/lists/search?q=${encodeURIComponent(query)}&page=${page}`;
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

  const tTrakt = Date.now();
  const listsService = new ListsService(c.env);
  const result = await listsService.searchLists(query, page, PAGE_SIZE);
  if (trace) trace.add(`trakt fetch: ${result.items.length} items ${Date.now() - tTrakt}ms`);

  if (result.items.length > 0) await cacheService.set(cacheKey, result, 43200);

  return c.json(result, 200, {
    'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
  });
});

// GET /api/v1/lists/:list_id/items (Items inside a specific list, with in-list filters and sorting)
listsRouter.get('/:list_id/items', async (c) => {
  const listId = Number(c.req.param('list_id')?.trim());
  if (isNaN(listId) || listId <= 0) {
    return c.json({ error: 'Invalid or missing list_id parameter (must be numeric Trakt list ID)' }, 400);
  }

  const page = Math.max(1, Number(c.req.query('page') || 1));
  const PAGE_SIZE = 100;

  const typeParam = (c.req.query('type') || c.req.query('media_type'))?.trim().toLowerCase();
  const media_type: ListFilters['media_type'] = (typeParam === 'movie' || typeParam === 'tv') ? typeParam : 'all';
  const genre = c.req.query('genre')?.trim().toLowerCase();
  const yearQuery = c.req.query('year')?.trim();
  const year = yearQuery && !isNaN(Number(yearQuery)) ? Number(yearQuery) : undefined;
  const minRatingQuery = c.req.query('min_rating')?.trim();
  const min_rating = minRatingQuery && !isNaN(Number(minRatingQuery)) ? Number(minRatingQuery) : undefined;

  const sortByParam = c.req.query('sort_by')?.trim().toLowerCase() as ListFilters['sort_by'];
  const validSortBys = ['rank', 'added', 'title', 'released', 'popularity', 'votes'];
  const sort_by = validSortBys.includes(sortByParam || '') ? sortByParam : undefined;

  const sortOrderParam = c.req.query('sort_order')?.trim().toLowerCase() as ListFilters['sort_order'];
  const sort_order = (sortOrderParam === 'asc' || sortOrderParam === 'desc') ? sortOrderParam : undefined;

  const filters: ListFilters = {
    media_type,
    genre,
    year,
    min_rating,
    sort_by,
    sort_order,
  };

  const origin = new URL(c.req.url).origin;
  const filterKeyPart = `&t=${media_type}&g=${genre || ''}&y=${year || ''}&min_r=${min_rating || ''}&sort=${sort_by || ''}&order=${sort_order || ''}`;
  const cacheKey = `${origin}/api/v1/lists/${encodeURIComponent(listId)}/items?page=${page}${filterKeyPart}`;
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

  const listsService = new ListsService(c.env);
  const result = await listsService.getListItems(listId, page, PAGE_SIZE, filters, trace);

  if (result.items.length > 0) await cacheService.set(cacheKey, result, 43200);

  return c.json(result, 200, {
    'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
  });
});
