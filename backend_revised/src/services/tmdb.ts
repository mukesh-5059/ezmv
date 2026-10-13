import { Bindings } from '../types';

export interface TmdbResult {
  data: any;
  cached: boolean;
  ttlSeconds: number;
}

export class TmdbService {
  private apiKey: string;
  private readToken: string;
  private baseUrl = 'https://api.themoviedb.org/3';

  constructor(env: Bindings) {
    this.apiKey = env.TMDB_API_KEY || env.ApiKey || '';
    this.readToken = env.TMDB_READ_ACCESS_TOKEN || env.ReadAccessToken || '';
  }

  private getHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': 'application/json',
    };
    if (this.readToken) {
      headers['Authorization'] = `Bearer ${this.readToken}`;
    }
    return headers;
  }

  async getDetails(mediaType: 'movie' | 'tv', tmdbId: number | string): Promise<TmdbResult | null> {
    const cacheKeyUrl = `https://cache.local/tmdb/${mediaType}/${tmdbId}?append=credits,external_ids,videos`;
    const cacheKey = new Request(cacheKeyUrl);
    const cache = caches.default;

    // 1. Check Cloudflare Cache API for existing TMDb response
    const cachedResponse = await cache.match(cacheKey);
    if (cachedResponse) {
      try {
        const data = await cachedResponse.json();
        const ttlHeader = cachedResponse.headers.get('X-Cache-TTL') || '172800s';
        const ttl = parseInt(ttlHeader, 10) || 172800;
        return {
          data,
          cached: true,
          ttlSeconds: ttl,
        };
      } catch (_) {}
    }

    // 2. Fetch fresh from TMDb
    let url = `${this.baseUrl}/${mediaType}/${tmdbId}?append_to_response=credits,external_ids,videos`;
    if (!this.readToken && this.apiKey) {
      url += `&api_key=${this.apiKey}`;
    }

    const response = await fetch(url, {
      headers: this.getHeaders(),
    });

    if (!response.ok) {
      if (response.status === 404) return null;
      throw new Error(`TMDb API returned status ${response.status}`);
    }

    const data: any = await response.json();

    // 3. Compute dynamic TTL (48 hours if complete, 12 hours if incomplete/upcoming)
    const hasPoster = Boolean(data.poster_path);
    const hasBackdrop = Boolean(data.backdrop_path);
    const hasOverview = Boolean(data.overview && data.overview.trim().length > 10);
    const hasCast = Boolean(data.credits?.cast && data.credits.cast.length > 0);

    const isComplete = hasPoster && hasBackdrop && hasOverview && hasCast;
    const ttlSeconds = isComplete ? 172800 : 43200; // 48h vs 12h

    // 4. Store in Cache API
    const cacheInit: ResponseInit = {
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': `public, max-age=${ttlSeconds}`,
        'X-Cache-TTL': `${ttlSeconds}s`,
      },
    };

    await cache.put(cacheKey, new Response(JSON.stringify(data), cacheInit));

    return {
      data,
      cached: false,
      ttlSeconds,
    };
  }
}
