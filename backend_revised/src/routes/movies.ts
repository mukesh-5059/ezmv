import { Hono } from 'hono';
import {
  Bindings,
  MovieDetailsResponse,
  MovieSummaryResponse,
  CastMember,
  GenreItem,
  TvSeasonItem,
  TvEpisode,
  TvSeasonDetailsResponse,
} from '../types';
import { TmdbService } from '../services/tmdb';
import { CacheService } from '../services/cache';

export const moviesRouter = new Hono<{ Bindings: Bindings }>();

// GET /api/v1/movies/tv/:id/season/:season_number
moviesRouter.get('/tv/:id/season/:season_number', async (c) => {
  const tmdbId = c.req.param('id');
  const seasonNumber = c.req.param('season_number');

  if (!tmdbId || isNaN(Number(tmdbId))) {
    return c.json({ error: 'Invalid TV show tmdb_id' }, 400);
  }
  if (seasonNumber === undefined || isNaN(Number(seasonNumber))) {
    return c.json({ error: 'Invalid season_number' }, 400);
  }

  const cacheKey = `https://cache.local/api/v1/movies/tv/${tmdbId}/season/${seasonNumber}`;
  const cacheService = new CacheService();

  const cached = await cacheService.get<TvSeasonDetailsResponse>(cacheKey);
  if (cached) {
    c.header('X-Cache-Status', 'HIT');
    c.header('X-Cache-TTL', `${cached.ttlSeconds}s`);
    c.header('Cache-Control', `public, max-age=${cached.ttlSeconds}`);
    return c.json(cached.data);
  }

  const tmdbService = new TmdbService(c.env);
  let seasonResult;
  try {
    seasonResult = await tmdbService.fetchTvSeason(tmdbId, seasonNumber);
  } catch (err: any) {
    return c.json({ error: 'Failed to fetch season details', details: err.message }, 502);
  }

  if (!seasonResult || !seasonResult.data) {
    return c.json({ error: `Season ${seasonNumber} not found on TMDb` }, 404);
  }

  const raw = seasonResult.data;
  const rawEpisodes = Array.isArray(raw.episodes) ? raw.episodes : [];

  const now = Date.now();
  const episodes: TvEpisode[] = rawEpisodes.map((ep: any) => {
    const isUpcoming = !ep.air_date || new Date(ep.air_date).getTime() > now;
    const item: TvEpisode = {
      id: ep.id || 0,
      episode_number: ep.episode_number || 0,
      name: ep.name || '',
      overview: ep.overview || '',
      still_path: ep.still_path || null,
      air_date: ep.air_date || null,
      rating: Number(ep.vote_average || 0),
      runtime: ep.runtime || null,
    };
    if (isUpcoming) {
      item.upcoming = true;
    }
    return item;
  });

  const payload: TvSeasonDetailsResponse = {
    season_number: raw.season_number ?? Number(seasonNumber),
    episodes,
  };

  await cacheService.set(cacheKey, payload, seasonResult.ttlSeconds);

  c.header('X-Cache-Status', 'MISS');
  c.header('X-Cache-TTL', `${seasonResult.ttlSeconds}s`);
  c.header('Cache-Control', `public, max-age=${seasonResult.ttlSeconds}`);

  return c.json(payload);
});

// GET /api/v1/movies/:media_type/:id
moviesRouter.get('/:media_type/:id', async (c) => {
  const mediaTypeParam = c.req.param('media_type').toLowerCase();
  const idParam = c.req.param('id');
  const isConcise =
    c.req.query('concise') === 'true' || c.req.query('short') === 'true';

  if (mediaTypeParam !== 'movie' && mediaTypeParam !== 'tv') {
    return c.json({ error: 'Invalid media_type. Must be "movie" or "tv".' }, 400);
  }

  const mediaType: 'movie' | 'tv' = mediaTypeParam as 'movie' | 'tv';
  const cacheKey = `https://cache.local/api/v1/movies/${mediaType}/${idParam}${isConcise ? '?concise=true' : ''}`;
  const cacheService = new CacheService();

  const cached = await cacheService.get<MovieDetailsResponse | MovieSummaryResponse>(cacheKey);
  if (cached) {
    c.header('X-Cache-Status', 'HIT');
    c.header('X-Cache-TTL', `${cached.ttlSeconds}s`);
    c.header('Cache-Control', `public, max-age=${cached.ttlSeconds}`);
    return c.json(cached.data);
  }

  const tmdbService = new TmdbService(c.env);
  let tmdbResult;
  try {
    tmdbResult = await tmdbService.fetchDetails(mediaType, idParam, isConcise);
  } catch (err: any) {
    return c.json({ error: 'Failed to fetch upstream details', details: err.message }, 502);
  }

  if (!tmdbResult || !tmdbResult.data) {
    return c.json({ error: 'Title not found' }, 404);
  }

  const rawData = tmdbResult.data;

  // 1. Extract IMDb ID
  let imdbId = rawData.imdb_id || rawData.external_ids?.imdb_id || null;

  // 2. Fetch authoritative rating & votes from D1
  let rating = Number(rawData.vote_average || 0);
  let voteCount = Number(rawData.vote_count || 0);

  if (imdbId) {
    const d1Rating = await c.env.DB.prepare(
      'SELECT rating, votes FROM imdb_ratings WHERE imdb_id = ?'
    )
      .bind(imdbId)
      .first<{ rating: number; votes: number }>();

    if (d1Rating && d1Rating.rating != null) {
      rating = d1Rating.rating;
      voteCount = d1Rating.votes || 0;
    }
  }

  // 3. Return lightweight summary if ?concise=true or ?short=true
  if (isConcise) {
    const genreIds =
      rawData.genre_ids ||
      (Array.isArray(rawData.genres) ? rawData.genres.map((g: any) => g.id) : []);

    const summaryPayload: MovieSummaryResponse = {
      tmdb_id: rawData.id,
      imdb_id: imdbId,
      title: rawData.title || rawData.name || '',
      overview: rawData.overview || '',
      release_date: rawData.release_date || rawData.first_air_date || '',
      poster_path: rawData.poster_path || '',
      backdrop_path: rawData.backdrop_path || '',
      rating,
      vote_count: voteCount,
      media_type: mediaType,
      genre_ids: genreIds,
    };

    await cacheService.set(cacheKey, summaryPayload, tmdbResult.ttlSeconds);

    c.header('X-Cache-Status', 'MISS');
    c.header('X-Cache-TTL', `${tmdbResult.ttlSeconds}s`);
    c.header('Cache-Control', `public, max-age=${tmdbResult.ttlSeconds}`);
    return c.json(summaryPayload);
  }

  // 4. Format Full Details (Cast, Genres, Seasons, Runtime)
  const rawCast = rawData.credits?.cast || [];
  const cast: CastMember[] = rawCast.slice(0, 30).map((member: any) => ({
    id: member.id,
    name: member.name || '',
    character: member.character || '',
    profile_path: member.profile_path || null,
  }));

  const genres: GenreItem[] = (rawData.genres || []).map((g: any) => ({
    id: g.id,
    name: g.name || '',
  }));

  let seasons: TvSeasonItem[] | undefined;
  if (mediaType === 'tv' && Array.isArray(rawData.seasons)) {
    seasons = rawData.seasons.map((s: any) => ({
      id: s.id,
      season_number: s.season_number,
      name: s.name || `Season ${s.season_number}`,
      episode_count: s.episode_count || 0,
    }));
  }

  let runtime: number | null = rawData.runtime || null;
  if (!runtime && Array.isArray(rawData.episode_run_time) && rawData.episode_run_time.length > 0) {
    runtime = rawData.episode_run_time[0];
  }

  const responsePayload: MovieDetailsResponse = {
    tmdb_id: rawData.id,
    imdb_id: imdbId,
    title: rawData.title || rawData.name || '',
    overview: rawData.overview || '',
    release_date: rawData.release_date || rawData.first_air_date || '',
    poster_path: rawData.poster_path || '',
    backdrop_path: rawData.backdrop_path || '',
    rating,
    vote_count: voteCount,
    runtime,
    tagline: rawData.tagline || null,
    media_type: mediaType,
    number_of_seasons: rawData.number_of_seasons || seasons?.length,
    number_of_episodes: rawData.number_of_episodes || 0,
    genres,
    cast,
    seasons,
  };

  await cacheService.set(cacheKey, responsePayload, tmdbResult.ttlSeconds);

  c.header('X-Cache-Status', 'MISS');
  c.header('X-Cache-TTL', `${tmdbResult.ttlSeconds}s`);
  c.header('Cache-Control', `public, max-age=${tmdbResult.ttlSeconds}`);
  return c.json(responsePayload);
});
