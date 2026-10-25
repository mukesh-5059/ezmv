import { Hono } from 'hono';
import { Bindings, MovieSummary, Variables } from '../types';
import { CatalogService } from '../services/catalog';
import { CacheService } from '../services/cache';
import { DASHBOARDS } from '../config/lanes';

export const dashboardRouter = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// GET /api/v1/dashboard/:dashboard_id (Returns all homepage lanes for dashboard)
dashboardRouter.get('/:dashboard_id', async (c) => {
  const dashboard = DASHBOARDS[c.req.param('dashboard_id')?.toLowerCase()];
  if (!dashboard) return c.notFound();

  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/dashboard/${dashboard.id}`;
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

  const catalog = new CatalogService(c.env);
  const tCatalog = Date.now();
  const lanesOutput = await Promise.all(
    dashboard.lanes.map(async (lane) => {
      const movies = await catalog.getLaneItems(lane.id, 100, 0);
      return {
        id: lane.id,
        title: lane.title,
        items: movies,
        has_more: movies.length >= 100,
        next_page: movies.length >= 100 ? 2 : null,
      };
    })
  );
  if (trace) trace.add(`d1: RESOLVE ${dashboard.lanes.length} LANES in ${Date.now() - tCatalog}ms`);

  const responsePayload = {
    id: dashboard.id,
    title: dashboard.title,
    lanes: lanesOutput,
  };
  await cacheService.set(cacheKey, responsePayload, 43200);

  return c.json(responsePayload, 200, {
    'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
  });
});

// GET /api/v1/dashboard/:dashboard_id/lanes/:lane_id (Paginates individual lane, fixed 100 items per page)
dashboardRouter.get('/:dashboard_id/lanes/:lane_id', async (c) => {
  const dashboard = DASHBOARDS[c.req.param('dashboard_id')?.toLowerCase()];
  const laneId = c.req.param('lane_id')?.toLowerCase();
  const lane = dashboard?.lanes.find((l) => l.id === laneId);

  if (!lane) return c.notFound();

  const page = Math.max(1, Number(c.req.query('page') || 1));
  const PAGE_SIZE = 100;
  const offset = (page - 1) * PAGE_SIZE;

  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/dashboard/${dashboard.id}/lanes/${laneId}?page=${page}`;
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

  const catalog = new CatalogService(c.env);
  const items = await catalog.getLaneItems(laneId, PAGE_SIZE, offset, trace);
  const hasMore = items.length >= PAGE_SIZE;

  const responsePayload = {
    id: lane.id,
    title: lane.title,
    page,
    items,
    has_more: hasMore,
    next_page: hasMore ? page + 1 : null,
  };

  if (items.length > 0) {
    await cacheService.set(cacheKey, responsePayload, 43200);
  }

  return c.json(responsePayload, 200, {
    'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
  });
});
