import { Hono } from 'hono';
import { Bindings, MovieDetails, Variables } from '../types';
import { CatalogService } from '../services/catalog';
import { CacheService } from '../services/cache';

export const moviesRouter = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// GET /api/v1/movies/:media_type/:id
moviesRouter.get('/:media_type/:id', async (c) => {
  const mediaTypeParam = c.req.param('media_type').toLowerCase();
  const imdbId = c.req.param('id').trim();

  if (mediaTypeParam !== 'movie' && mediaTypeParam !== 'tv') {
    return c.json({ error: 'Invalid media_type. Must be "movie" or "tv".' }, 400);
  }

  if (!imdbId.startsWith('tt')) {
    return c.json({ error: 'Invalid id parameter (must start with "tt").' }, 400);
  }

  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/movies/${mediaTypeParam}/${imdbId}`;
  const cacheService = new CacheService();

  const trace = c.get('trace');
  const tCache = Date.now();
  const cached = await cacheService.get<MovieDetails>(cacheKey);
  if (trace) trace.cache = cached ? `HIT ${Date.now() - tCache}ms` : `MISS ${Date.now() - tCache}ms`;

  if (cached) {
    c.header('Cache-Control', 'public, max-age=86400, stale-while-revalidate=43200');
    return c.json(cached);
  }

  const catalog = new CatalogService(c.env);
  const movieDetails = await catalog.getSingleMovie(imdbId);

  if (!movieDetails) {
    return c.json({ error: 'Movie not found' }, 404);
  }

  await cacheService.set(cacheKey, movieDetails, 86400);
  c.header('Cache-Control', 'public, max-age=86400, stale-while-revalidate=43200');

  return c.json(movieDetails);
});
