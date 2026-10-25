import { Hono } from 'hono';
import { Bindings, MovieSummary, Variables } from '../types';
import { TraktService } from '../services/trakt';
import { CatalogService } from '../services/catalog';
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

  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/search?q=${encodeURIComponent(query)}&page=${page}`;
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

  // 1. Search Trakt for ordered candidate IMDb IDs and pagination headers
  const trakt = new TraktService(c.env.TRAKT_CLIENT_ID);
  const tTrakt = Date.now();
  const traktResult = await trakt.search(query, page, PAGE_SIZE);
  if (trace) trace.add(`trakt: DONE ${Date.now() - tTrakt}ms (${traktResult.imdb_ids.length} items)`);

  if (!traktResult.imdb_ids.length) {
    const emptyPayload = {
      items: [],
      page: traktResult.page,
      total_pages: traktResult.total_pages,
      total_items: traktResult.total_items,
      has_more: false,
      next_page: null,
    };
    return c.json(emptyPayload);
  }

  // 2. Resolve metadata & ratings via D1 + MDBList batch using IMDb IDs
  const catalog = new CatalogService(c.env);
  const movies = await catalog.resolveMovies(traktResult.imdb_ids, trace);

  const hasMore = page < traktResult.total_pages;
  const responsePayload = {
    items: movies,
    page: traktResult.page,
    total_pages: traktResult.total_pages,
    total_items: traktResult.total_items,
    has_more: hasMore,
    next_page: hasMore ? page + 1 : null,
  };

  if (movies.length > 0) {
    await cacheService.set(cacheKey, responsePayload, 43200); // 12 hours cache
  }

  return c.json(responsePayload, 200, {
    'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
  });
});
