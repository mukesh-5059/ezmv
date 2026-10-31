import { Hono } from 'hono';
import { Bindings, MovieSummary, Variables, LaneFilters } from '../types';
import { LanesService } from '../services/lanes';
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

  const lanesService = new LanesService(c.env);
  const tCatalog = Date.now();
  const lanesOutput = await Promise.all(
    dashboard.lanes.map(async (lane) => {
      const movies = await lanesService.getLaneItems(lane.id, 100, 0);
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

// GET /api/v1/dashboard/:dashboard_id/lanes/:lane_id (Paginates individual lane, fixed 100 items per page with filters)
dashboardRouter.get('/:dashboard_id/lanes/:lane_id', async (c) => {
  const dashboard = DASHBOARDS[c.req.param('dashboard_id')?.toLowerCase()];
  const laneId = c.req.param('lane_id')?.toLowerCase();
  const lane = dashboard?.lanes.find((l) => l.id === laneId);

  if (!lane) return c.notFound();

  const page = Math.max(1, Number(c.req.query('page') || 1));
  const PAGE_SIZE = 100;
  const offset = (page - 1) * PAGE_SIZE;

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
  const tCache = Date.now();
  const cached = await cacheService.get<any>(cacheKey);
  if (trace) trace.add(`cache: ${cached ? 'HIT' : 'MISS'} ${Date.now() - tCache}ms`);

  if (cached) {
    return c.json(cached, 200, {
      'Cache-Control': 'public, max-age=43200, stale-while-revalidate=86400',
    });
  }

  const lanesService = new LanesService(c.env);
  const items = await lanesService.getLaneItems(laneId, PAGE_SIZE, offset, filters, trace);
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
