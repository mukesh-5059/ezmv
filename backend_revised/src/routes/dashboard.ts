import { Hono } from 'hono';
import { Bindings, MovieSummary, Variables } from '../types';
import { CatalogService } from '../services/catalog';
import { CacheService } from '../services/cache';
import { MdblistService } from '../services/mdblist';
import { TAMIL_LANES } from '../config/lanes';

export const dashboardRouter = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// GET /api/v1/dashboard (Returns all homepage lanes)
dashboardRouter.get('/', async (c) => {
  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/dashboard`;
  const cacheService = new CacheService();

  const trace = c.get('trace');
  const tCache = Date.now();
  const cached = await cacheService.get<any>(cacheKey);
  if (trace) trace.cache = cached ? `HIT ${Date.now() - tCache}ms` : `MISS ${Date.now() - tCache}ms`;

  if (cached) {
    return c.json(cached, 200, {
      'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
    });
  }

  const catalog = new CatalogService(c.env);
  const lanesOutput: { id: string; title: string; items: MovieSummary[]; has_more: boolean; next_page: number | null }[] = [];

  for (const lane of TAMIL_LANES) {
    const movies = await catalog.getLaneItems(lane.id, 100, 0);

    lanesOutput.push({
      id: lane.id,
      title: lane.title,
      items: movies,
      has_more: movies.length >= 100,
      next_page: movies.length >= 100 ? 2 : null,
    });
  }

  const responsePayload = { lanes: lanesOutput };
  await cacheService.set(cacheKey, responsePayload, 43200); // 12 hours cache

  return c.json(responsePayload, 200, {
    'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
  });
});

// GET /api/v1/dashboard/lane (Paginates individual lane, fixed 100 items per page)
dashboardRouter.get('/lane', async (c) => {
  const laneId = c.req.query('lane_id') || 'trending';
  const page = Math.max(1, Number(c.req.query('page') || 1));
  const PAGE_SIZE = 100;
  const offset = (page - 1) * PAGE_SIZE;

  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/dashboard/lane?lane_id=${laneId}&page=${page}`;
  const cacheService = new CacheService();

  const trace = c.get('trace');
  const tCache = Date.now();
  const cached = await cacheService.get<any>(cacheKey);
  if (trace) trace.cache = cached ? `HIT ${Date.now() - tCache}ms` : `MISS ${Date.now() - tCache}ms`;

  if (cached) {
    return c.json(cached, 200, {
      'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
    });
  }

  const catalog = new CatalogService(c.env);
  const tCatalog = Date.now();
  const items = await catalog.getLaneItems(laneId, PAGE_SIZE, offset);
  if (trace) trace.d1 = `RESOLVE ${Date.now() - tCatalog}ms`;
  const hasMore = items.length >= PAGE_SIZE;

  const responsePayload = {
    items,
    has_more: hasMore,
    next_page: hasMore ? page + 1 : null,
  };

  if (items.length > 0) {
    await cacheService.set(cacheKey, responsePayload, 43200); // 12 hours cache
  }

  return c.json(responsePayload, 200, {
    'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
  });
});
