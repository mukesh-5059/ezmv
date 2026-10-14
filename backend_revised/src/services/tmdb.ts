import { Bindings } from '../types';

export interface TmdbFetchResult {
  data: any;
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

  async fetchDetails(
    mediaType: 'movie' | 'tv',
    tmdbId: number | string,
    concise: boolean = false
  ): Promise<TmdbFetchResult | null> {
    const appends: string[] = [];
    if (!concise) appends.push('credits');
    if (mediaType === 'tv') appends.push('external_ids');

    const appendParam = appends.length > 0 ? `?append_to_response=${appends.join(',')}` : '';
    let url = `${this.baseUrl}/${mediaType}/${tmdbId}${appendParam}`;

    if (!this.readToken && this.apiKey) {
      url += (url.includes('?') ? '&' : '?') + `api_key=${this.apiKey}`;
    }

    const response = await fetch(url, { headers: this.getHeaders() });
    if (!response.ok) {
      if (response.status === 404) return null;
      throw new Error(`TMDb API returned status ${response.status}`);
    }

    const data: any = await response.json();

    // 48 hours if complete, 12 hours if incomplete/upcoming
    const hasPoster = Boolean(data.poster_path);
    const hasBackdrop = Boolean(data.backdrop_path);
    const hasOverview = Boolean(data.overview && data.overview.trim().length > 10);
    const hasCast = concise ? true : Boolean(data.credits?.cast && data.credits.cast.length > 0);

    const isComplete = hasPoster && hasBackdrop && hasOverview && hasCast;
    const ttlSeconds = isComplete ? 172800 : 43200; // 48h vs 12h

    return { data, ttlSeconds };
  }

  async fetchTvSeason(
    tmdbId: number | string,
    seasonNumber: number | string
  ): Promise<TmdbFetchResult | null> {
    let url = `${this.baseUrl}/tv/${tmdbId}/season/${seasonNumber}`;
    if (!this.readToken && this.apiKey) {
      url += `?api_key=${this.apiKey}`;
    }

    const response = await fetch(url, { headers: this.getHeaders() });
    if (!response.ok) {
      if (response.status === 404) return null;
      throw new Error(`TMDb API returned status ${response.status}`);
    }

    const data: any = await response.json();

    // Ongoing/Recent: has future episode, un-aired episode, or aired in last 30 days -> 24h (86,400s)
    // Concluded: all episodes aired > 30 days ago -> 30 days (2,592,000s)
    let isOngoing = false;
    const now = Date.now();
    const thirtyDaysAgo = now - 30 * 24 * 60 * 60 * 1000;

    if (Array.isArray(data.episodes) && data.episodes.length > 0) {
      for (const ep of data.episodes) {
        if (!ep.air_date) {
          isOngoing = true;
          break;
        }
        const airTime = new Date(ep.air_date).getTime();
        if (airTime >= thirtyDaysAgo) {
          isOngoing = true;
          break;
        }
      }
    }

    const ttlSeconds = isOngoing ? 86400 : 2592000; // 24h vs 30d
    return { data, ttlSeconds };
  }
}
