import { Hono } from 'hono';
import { Bindings, DashboardResponse, LaneFilters, PaginatedLaneResponse, Variables } from '../types';
import { LanesService } from '../services/lanes';
import { CacheService } from '../services/cache';
import { DASHBOARDS, DASHBOARDS_LIST } from '../config/dashboards';

export const dashboardRouter = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// GET /api/v1/dashboard (Returns list of available dashboards)
dashboardRouter.get('/', async (c) => {
  c.header('Cache-Control', 'public, max-age=604800, stale-while-revalidate=86400');
  return c.json(DASHBOARDS_LIST);
});

// GET /api/v1/dashboard/:dashboard_id (Returns all homepage lanes for dashboard)
dashboardRouter.get('/:dashboard_id', async (c) => {
  const dashboardId = c.req.param('dashboard_id')?.toLowerCase();
  const dashboard = DASHBOARDS[dashboardId];
  if (!dashboard) return c.notFound();

  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/dashboard/${dashboard.id}`;
  const cacheService = new CacheService();

  const trace = c.get('trace');
  const isRefresh = c.req.query('refresh') === 'true';
  const tCache = Date.now();
  const cached = isRefresh ? null : await cacheService.get<any>(cacheKey);
  if (trace) trace.add(`cache: ${cached ? 'HIT' : 'MISS'} ${Date.now() - tCache}ms`);

  if (cached) {
    return c.json(cached, 200, {
      'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
    });
  }

  const lanesService = new LanesService(c.env);
  const tCatalog = Date.now();
  const lanesOutput: PaginatedLaneResponse[] = await Promise.all(
    dashboard.lanes.map((lane) => lanesService.getLaneItems(lane, 1, 100))
  );
  if (trace) trace.add(`d1: RESOLVE ${dashboard.lanes.length} LANES in ${Date.now() - tCatalog}ms`);

  const responsePayload: DashboardResponse = {
    id: dashboard.id,
    title: dashboard.title,
    lanes: lanesOutput,
  };
  await cacheService.set(cacheKey, responsePayload, 43200);

  return c.json(responsePayload, 200, {
    'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
  });
});

// GET /api/v1/dashboard/:dashboard_id/lanes/:lane_id (Paginates individual lane, fixed 100 items per page with filters)
dashboardRouter.get('/:dashboard_id/lanes/:lane_id', async (c) => {
  const dashboardId = c.req.param('dashboard_id')?.toLowerCase();
  const dashboard = DASHBOARDS[dashboardId];
  const laneId = c.req.param('lane_id')?.toLowerCase();
  const lane = dashboard?.lanes.find((l) => l.id === laneId);

  if (!dashboard || !lane) return c.notFound();

  const page = Math.max(1, Number(c.req.query('page') || 1));
  const PAGE_SIZE = 100;

  const typeParam = (c.req.query('type') || c.req.query('media_type'))?.trim().toLowerCase();
  const media_type: LaneFilters['media_type'] = (typeParam === 'movie' || typeParam === 'tv') ? typeParam : 'all';
  const genre = c.req.query('genre')?.trim().toLowerCase();
  const yearQuery = c.req.query('year')?.trim();
  const year = yearQuery && !isNaN(Number(yearQuery)) ? Number(yearQuery) : undefined;
  const minRatingQuery = c.req.query('min_rating')?.trim();
  const min_rating = minRatingQuery && !isNaN(Number(minRatingQuery)) ? Number(minRatingQuery) : undefined;
  const sortBy = c.req.query('sort_by')?.trim().toLowerCase() as LaneFilters['sort_by'];

  const filters: LaneFilters = {
    media_type,
    genre,
    year,
    min_rating,
    sort_by: sortBy,
  };

  const origin = new URL(c.req.url).origin;
  const filterKeyPart = `&t=${media_type}&g=${genre || ''}&y=${year || ''}&min_r=${min_rating || ''}&sort=${sortBy || ''}`;
  const cacheKey = `${origin}/api/v1/dashboard/${dashboard.id}/lanes/${laneId}?page=${page}${filterKeyPart}`;
  const cacheService = new CacheService();

  const trace = c.get('trace');
  const isRefresh = c.req.query('refresh') === 'true';
  const tCache = Date.now();
  const cached = isRefresh ? null : await cacheService.get<any>(cacheKey);
  if (trace) trace.add(`cache: ${cached ? 'HIT' : 'MISS'} ${Date.now() - tCache}ms`);

  if (cached) {
    return c.json(cached, 200, {
      'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
    });
  }

  const lanesService = new LanesService(c.env);
  const result = await lanesService.getLaneItems(lane, page, PAGE_SIZE, filters, trace);

  if (result.items.length > 0) {
    await cacheService.set(cacheKey, result, 43200);
  }

  return c.json(result, 200, {
    'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
  });
});
