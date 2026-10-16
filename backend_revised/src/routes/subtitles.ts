import { Hono } from 'hono';
import { Bindings, SubtitleTrack } from '../types';
import { TmdbService } from '../services/tmdb';
import { CacheService } from '../services/cache';

export const subtitlesRouter = new Hono<{ Bindings: Bindings }>();

const langNames = new Intl.DisplayNames(['en'], { type: 'language' });

subtitlesRouter.get('/', async (c) => {
  const tmdbIdParam = c.req.query('tmdb_id');
  if (!tmdbIdParam || isNaN(Number(tmdbIdParam))) {
    return c.json({ error: 'Missing or invalid tmdb_id parameter' }, 400);
  }

  const tmdbId = Number(tmdbIdParam);
  const mediaTypeParam = (c.req.query('media_type') || 'movie').toLowerCase();
  if (mediaTypeParam !== 'movie' && mediaTypeParam !== 'tv') {
    return c.json({ error: 'Invalid media_type. Must be "movie" or "tv".' }, 400);
  }
  const mediaType: 'movie' | 'tv' = mediaTypeParam as 'movie' | 'tv';

  const seasonParam = c.req.query('season');
  const episodeParam = c.req.query('episode');
  const season = seasonParam ? Number(seasonParam) : undefined;
  const episode = episodeParam ? Number(episodeParam) : undefined;
  const langFilter = c.req.query('language')?.trim().toLowerCase();

  const cacheKey = `https://cache.local/api/v1/subtitles/${tmdbId}/${mediaType}/${season || 0}/${episode || 0}`;
  const cacheService = new CacheService();
  const cached = await cacheService.get<SubtitleTrack[]>(cacheKey);
  if (cached) {
    let responseData = cached;
    if (langFilter) {
      responseData = responseData.filter(
        (t) => t.language.toLowerCase() === langFilter
      );
    }
    return c.json(responseData);
  }

  let imdbId = c.req.query('imdb_id')?.trim();
  if (!imdbId || !imdbId.startsWith('tt')) {
    const tmdbService = new TmdbService(c.env);
    try {
      const tmdbResult = await tmdbService.fetchDetails(mediaType, tmdbId, true);
      if (tmdbResult && tmdbResult.data) {
        imdbId =
          tmdbResult.data.imdb_id ||
          tmdbResult.data.external_ids?.imdb_id ||
          null;
      }
    } catch (err: any) {
      throw new Error(`Failed resolving IMDb ID: ${err.message}`);
    }
  }

  if (!imdbId) {
    await cacheService.set(cacheKey, [], 86400);
    return c.json([]);
  }

  let stremioUrl: string;
  if (mediaType === 'tv' && season && episode) {
    stremioUrl = `https://opensubtitles-v3.strem.io/subtitles/series/${imdbId}:${season}:${episode}.json`;
  } else {
    stremioUrl = `https://opensubtitles-v3.strem.io/subtitles/movie/${imdbId}.json`;
  }

  let stremioData: any;
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 8000);
    const response = await fetch(stremioUrl, { signal: controller.signal });
    clearTimeout(timeoutId);

    if (response.ok) {
      stremioData = await response.json();
    }
  } catch (_) {}

  const rawSubs = Array.isArray(stremioData?.subtitles) ? stremioData.subtitles : [];
  const tracks: SubtitleTrack[] = [];

  for (const sub of rawSubs) {
    if (!sub.url) continue;

    const rawLang = (sub.lang || '').toLowerCase();
    let language = rawLang;
    try {
      language = langNames.of(rawLang) || rawLang;
    } catch (_) {}

    const name =
      sub.movieReleaseName ||
      sub.subtitleFileName ||
      sub.releaseGroup ||
      language;
    const popularity = Number(sub.g || 0);

    tracks.push({
      name,
      language,
      url: sub.url,
      popularity,
    });
  }

  tracks.sort((a, b) => b.popularity - a.popularity);
  await cacheService.set(cacheKey, tracks, 86400);

  let responseData = tracks;
  if (langFilter) {
    responseData = responseData.filter(
      (t) => t.language.toLowerCase() === langFilter
    );
  }

  return c.json(responseData);
});
