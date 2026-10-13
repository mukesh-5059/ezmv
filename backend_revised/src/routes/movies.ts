import { Hono } from 'hono';
import {
  Bindings,
  MovieDetailsResponse,
  MovieSummaryResponse,
  CastMember,
  GenreItem,
  TvSeasonItem,
} from '../types';
import { TmdbService } from '../services/tmdb';

export const moviesRouter = new Hono<{ Bindings: Bindings }>();

moviesRouter.get('/:media_type/:id', async (c) => {
  const mediaTypeParam = c.req.param('media_type').toLowerCase();
  const idParam = c.req.param('id');
  const isConcise =
    c.req.query('concise') === 'true' || c.req.query('short') === 'true';

  if (mediaTypeParam !== 'movie' && mediaTypeParam !== 'tv') {
    return c.json({ error: 'Invalid media_type. Must be "movie" or "tv".' }, 400);
  }

  const mediaType: 'movie' | 'tv' = mediaTypeParam as 'movie' | 'tv';
  const tmdbService = new TmdbService(c.env);

  let tmdbResult;
  try {
    tmdbResult = await tmdbService.getDetails(mediaType, idParam, isConcise);
  } catch (err: any) {
    return c.json({ error: 'Failed to fetch upstream details', details: err.message }, 502);
  }

  if (!tmdbResult || !tmdbResult.data) {
    return c.json({ error: 'Title not found' }, 404);
  }

  const rawData = tmdbResult.data;
  c.header('X-Cache-Status', tmdbResult.cached ? 'HIT' : 'MISS');
  c.header('X-Cache-TTL', `${tmdbResult.ttlSeconds}s`);
  c.header('Cache-Control', `public, max-age=${tmdbResult.ttlSeconds}`);

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
      name: rawData.name,
      overview: rawData.overview || '',
      release_date: rawData.release_date || rawData.first_air_date || '',
      first_air_date: rawData.first_air_date,
      poster_path: rawData.poster_path || '',
      backdrop_path: rawData.backdrop_path || '',
      rating,
      vote_count: voteCount,
      media_type: mediaType,
      genre_ids: genreIds,
    };
    return c.json(summaryPayload);
  }

  // 4. Format Full Details (Cast, Genres, Seasons, Runtime)
  const rawCast = rawData.credits?.cast || [];
  const cast: CastMember[] = rawCast.slice(0, 30).map((c: any) => ({
    id: c.id,
    name: c.name || '',
    character: c.character || '',
    profile_path: c.profile_path || null,
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
      poster_path: s.poster_path || null,
      air_date: s.air_date || null,
      overview: s.overview || null,
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
    name: rawData.name,
    overview: rawData.overview || '',
    release_date: rawData.release_date || rawData.first_air_date || '',
    first_air_date: rawData.first_air_date,
    poster_path: rawData.poster_path || '',
    backdrop_path: rawData.backdrop_path || '',
    rating,
    vote_count: voteCount,
    runtime: runtime,
    tagline: rawData.tagline || null,
    media_type: mediaType,
    number_of_seasons: rawData.number_of_seasons || seasons?.length,
    number_of_episodes: rawData.number_of_episodes || 0,
    genres: genres,
    cast: cast,
    seasons: seasons,
  };

  return c.json(responsePayload);
});
