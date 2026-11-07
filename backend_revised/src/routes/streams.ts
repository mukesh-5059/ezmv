import { Hono } from 'hono';
import { Bindings, StreamsResponse, Variables } from '../types';
import { StreamsService } from '../services/streams';
import { CacheService } from '../services/cache';

export const streamsRouter = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// GET /api/v1/streams/:media_type/:imdb_id
streamsRouter.get('/:media_type/:imdb_id', async (c) => {
  const mediaTypeParam = c.req.param('media_type').toLowerCase();
  if (mediaTypeParam !== 'movie' && mediaTypeParam !== 'tv') {
    return c.json({ error: 'Invalid media_type parameter. Must be "movie" or "tv".' }, 400);
  }
  const mediaType: 'movie' | 'tv' = mediaTypeParam;

  const imdbId = c.req.param('imdb_id').trim();
  if (!imdbId.startsWith('tt')) {
    return c.json({ error: 'Invalid imdb_id parameter (must start with "tt").' }, 400);
  }

  const query = c.req.query();
  const season = query.season ? Number(query.season) : undefined;
  const episode = query.episode ? Number(query.episode) : undefined;
  const defaultLanguage = query.default_language?.trim();

  if (mediaType === 'tv' && (!season || !episode || isNaN(season) || isNaN(episode))) {
    return c.json(
      { error: 'For tv media_type, both "season" and "episode" query parameters are required.' },
      400
    );
  }

  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/streams/${mediaType}/${imdbId}/${season || 0}/${episode || 0}/${defaultLanguage || ''}`;
  const cacheService = new CacheService();

  const trace = c.get('trace');
  const isRefresh = c.req.query('refresh') === 'true' || c.req.query('cache') === 'false';
  const tCache = Date.now();
  const cached = isRefresh ? null : await cacheService.get<StreamsResponse>(cacheKey);
  if (trace) trace.add(`cache: ${cached ? 'HIT' : 'MISS'} ${Date.now() - tCache}ms`);
  
  if (cached) return c.json(cached);

  const streamsService = new StreamsService(c.env);
  const tFetch = Date.now();
  const data = await streamsService.getStreams({
    imdbId,
    mediaType,
    season,
    episode,
    defaultLanguage,
  });
  if (trace) trace.add(`streams: ${data.streams.length} links ${Date.now() - tFetch}ms`);

  if (data.streams.length > 0) await cacheService.set(cacheKey, data, 900);

  return c.json(data);
});
