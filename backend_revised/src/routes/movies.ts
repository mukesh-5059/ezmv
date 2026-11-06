import { Hono } from 'hono';
import { Bindings, AdditionalMovieDetails, TvSeasonResponse, Variables } from '../types';
import { CatalogService } from '../services/catalog';
import { CacheService } from '../services/cache';

export const moviesRouter = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// GET /api/v1/movies/tv/:tmdb_id/season/:season_number
moviesRouter.get('/tv/:tmdb_id/season/:season_number', async (c) => {
  const tmdbId = Number(c.req.param('tmdb_id'));
  const seasonNumber = Number(c.req.param('season_number'));

  if (isNaN(tmdbId) || tmdbId <= 0) return c.json({ error: 'Invalid tmdb_id parameter (must be numeric TMDb ID).' }, 400);
  if (isNaN(seasonNumber) || seasonNumber < 0) return c.json({ error: 'Invalid season_number parameter.' }, 400);

  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/movies/tv/${tmdbId}/season/${seasonNumber}`;
  const cacheService = new CacheService();

  const trace = c.get('trace');
  const tCache = Date.now();
  const cached = await cacheService.get<TvSeasonResponse>(cacheKey);
  if (trace) trace.add(`cache: ${cached ? 'HIT' : 'MISS'} ${Date.now() - tCache}ms`);

  if (cached) {
    c.header('Cache-Control', 'public, max-age=86400, stale-while-revalidate=43200');
    return c.json(cached);
  }

  const catalog = new CatalogService(c.env);
  const seasonDetails = await catalog.getTvSeason(tmdbId, seasonNumber);
  if (!seasonDetails) return c.json({ error: `Season ${seasonNumber} not found for TMDb ID ${tmdbId}` }, 404);

  await cacheService.set(cacheKey, seasonDetails, 86400);
  c.header('Cache-Control', 'public, max-age=86400, stale-while-revalidate=43200');

  return c.json(seasonDetails);
});

// GET /api/v1/movies/:media_type/:imdb_id
moviesRouter.get('/:media_type/:tmdb_id', async (c) => {
  const mediaTypeParam = c.req.param('media_type').toLowerCase();
  const tmdbId = Number(c.req.param('tmdb_id'));

  if (mediaTypeParam !== 'movie' && mediaTypeParam !== 'tv') {
    return c.json({ error: 'Invalid media_type. Must be "movie" or "tv".' }, 400);
  }

  if (isNaN(tmdbId) || tmdbId <= 0) return c.json({ error: 'Invalid tmdb_id parameter (must be numeric TMDb ID).' }, 400); 

  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/movies/${mediaTypeParam}/${tmdbId}`;
  const cacheService = new CacheService();

  const trace = c.get('trace');
  const tCache = Date.now();
  const cached = await cacheService.get<AdditionalMovieDetails>(cacheKey);
  if (trace) trace.add(`cache: ${cached ? 'HIT' : 'MISS'} ${Date.now() - tCache}ms`);

  if (cached) {
    c.header('Cache-Control', 'public, max-age=86400, stale-while-revalidate=43200');
    return c.json(cached);
  }

  const catalog = new CatalogService(c.env);
  const movieDetails = await catalog.getSingleMovie(tmdbId, mediaTypeParam);

  if (!movieDetails) {
    return c.json({ error: 'Movie not found' }, 404);
  }

  await cacheService.set(cacheKey, movieDetails, 86400);
  c.header('Cache-Control', 'public, max-age=86400, stale-while-revalidate=43200');

  return c.json(movieDetails);
});
