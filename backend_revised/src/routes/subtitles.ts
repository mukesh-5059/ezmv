import { Context, Hono } from 'hono';
import { Bindings, SubtitleTrack, Variables } from '../types';
import { CacheService } from '../services/cache';

export const subtitlesRouter = new Hono<{ Bindings: Bindings; Variables: Variables }>();

const langNames = new Intl.DisplayNames(['en'], { type: 'language' });

async function handleSubtitles(
  c: Context<{ Bindings: Bindings; Variables: Variables }>,
  mediaTypeParam: string,
  imdbId: string,
  seasonParam?: string,
  episodeParam?: string,
  langFilterParam?: string
) {
  if (!imdbId || !imdbId.startsWith('tt')) {
    return c.json({ error: 'Missing or invalid imdb_id parameter (must start with "tt")' }, 400);
  }

  const mediaTypeLower = (mediaTypeParam || 'movie').toLowerCase();
  if (mediaTypeLower !== 'movie' && mediaTypeLower !== 'tv') {
    return c.json({ error: 'Invalid media_type. Must be "movie" or "tv".' }, 400);
  }
  const mediaType: 'movie' | 'tv' = mediaTypeLower as 'movie' | 'tv';

  const season = seasonParam ? Number(seasonParam) : undefined;
  const episode = episodeParam ? Number(episodeParam) : undefined;

  if (mediaType === 'tv' && (season === undefined || episode === undefined || isNaN(season) || isNaN(episode))) {
    return c.json({ error: 'For tv media_type, both "season" and "episode" parameters are required.' }, 400);
  }

  const langFilter = langFilterParam?.trim().toLowerCase();

  const origin = new URL(c.req.url).origin;
  const cacheKey = `${origin}/api/v1/subtitles/${mediaType}/${imdbId}/${season || 0}/${episode || 0}`;
  const cacheService = new CacheService();

  const trace = c.get('trace');
  const tCache = Date.now();
  const cached = await cacheService.get<SubtitleTrack[]>(cacheKey);
  if (trace) trace.add(`cache: ${cached ? 'HIT' : 'MISS'} ${Date.now() - tCache}ms`);
  if (cached) {
    let responseData = cached;
    if (langFilter) {
      responseData = responseData.filter(
        (t) => t.language.toLowerCase() === langFilter
      );
    }
    return c.json(responseData);
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
  if(tracks.length > 0) await cacheService.set(cacheKey, tracks, 86400);

  let responseData = tracks;
  if (langFilter) {
    responseData = responseData.filter(
      (t) => t.language.toLowerCase() === langFilter
    );
  }

  return c.json(responseData);
}

// Path parameter route: GET /api/v1/subtitles/:media_type/:imdb_id
subtitlesRouter.get('/:media_type/:imdb_id', async (c) => {
  return handleSubtitles(
    c,
    c.req.param('media_type'),
    c.req.param('imdb_id'),
    c.req.query('season'),
    c.req.query('episode'),
    c.req.query('language')
  );
});

// Query parameter route for backward compatibility: GET /api/v1/subtitles?imdb_id=...&media_type=...
subtitlesRouter.get('/', async (c) => {
  return handleSubtitles(
    c,
    c.req.query('media_type') || 'movie',
    c.req.query('imdb_id') || '',
    c.req.query('season'),
    c.req.query('episode'),
    c.req.query('language')
  );
});
