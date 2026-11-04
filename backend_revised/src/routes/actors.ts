import { Hono } from 'hono';
import { Bindings, PersonDetailsResponse, Variables } from '../types';
import { ActorsService } from '../services/actors';
import { CacheService } from '../services/cache';

export const actorsRouter = new Hono<{ Bindings: Bindings; Variables: Variables }>();

actorsRouter.get('/', async (c) => {
  const actorsService = new ActorsService(c.env);
  c.header('Cache-Control', 'public, max-age=604800, stale-while-revalidate=86400');
  return c.json(await actorsService.getCuratedActors());
});

actorsRouter.get('/:tmdb_id', async (c) => {
  const personId = Number(c.req.param('tmdb_id'));
  if (isNaN(personId) || personId <= 0) {
    return c.json({ error: 'Invalid actor/person id parameter.' }, 400);
  }

  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/actors/${personId}`;
  const cacheService = new CacheService();

  const trace = c.get('trace');
  const tCache = Date.now();
  const cached = await cacheService.get<PersonDetailsResponse>(cacheKey);
  if (trace) trace.add(`cache: ${cached ? 'HIT' : 'MISS'} ${Date.now() - tCache}ms`);

  if (cached) {
    c.header('Cache-Control', 'public, max-age=604800, stale-while-revalidate=86400');
    return c.json(cached);
  }

  const actorsService = new ActorsService(c.env);
  const personDetails = await actorsService.getPersonDetails(personId, trace);

  if (!personDetails) {
    return c.json({ error: `Person ${personId} not found.` }, 404);
  }

  await cacheService.set(cacheKey, personDetails, 604800);
  c.header('Cache-Control', 'public, max-age=604800, stale-while-revalidate=86400');

  return c.json(personDetails);
});
