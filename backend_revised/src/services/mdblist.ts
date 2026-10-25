import { MdblistItem } from '../types';

export class MdblistService {
  private apiKey: string;
  private baseUrl = 'https://api.mdblist.com';

  constructor(apiKey?: string) {
    this.apiKey = apiKey || '';
  }

  async batchMovies(ids: (string | number)[]): Promise<MdblistItem[]> {
    if (!this.apiKey || ids.length === 0) return [];

    const imdbIds: string[] = [];
    const tmdbIds: number[] = [];

    for (const id of ids) {
      if (typeof id === 'string' && id.startsWith('tt')) {
        imdbIds.push(id);
      } else if (!isNaN(Number(id))) {
        tmdbIds.push(Number(id));
      }
    }

    const results: MdblistItem[] = [];

    // Chunk size 100
    if (imdbIds.length > 0) {
      for (let i = 0; i < imdbIds.length; i += 100) {
        const chunk = imdbIds.slice(i, i + 100);
        const res = await this.postBatch('imdb', 'movie', chunk);
        results.push(...res);
      }
    }

    if (tmdbIds.length > 0) {
      for (let i = 0; i < tmdbIds.length; i += 100) {
        const chunk = tmdbIds.slice(i, i + 100);
        const res = await this.postBatch('tmdb', 'movie', chunk);
        results.push(...res);
      }
    }

    return results;
  }

  private async postBatch(provider: 'imdb' | 'tmdb', mediaType: 'movie' | 'show', ids: (string | number)[]): Promise<MdblistItem[]> {
    const url = `${this.baseUrl}/${provider}/${mediaType}/?apikey=${this.apiKey}`;
    try {
      const resp = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'User-Agent': 'CloudflareWorker/1.0',
        },
        body: JSON.stringify({ ids }),
        signal: AbortSignal.timeout(10000),
      });

      if (!resp.ok) {
        console.warn(`[MDBList postBatch error] ${provider}/${mediaType} status ${resp.status}`);
        return [];
      }

      const data: any = await resp.json();
      return Array.isArray(data) ? data : [];
    } catch (err: any) {
      console.warn(`[MDBList postBatch fetch error]`, err.message);
      return [];
    }
  }

  // Utilities to parse MDBList item into standard format
  static parseRating(item: MdblistItem): number {
    if (Array.isArray(item.ratings)) {
      const imdb = item.ratings.find((r) => r.source === 'imdb' && typeof r.value === 'number');
      if (imdb && typeof imdb.value === 'number') return Number(imdb.value.toFixed(1));
      const tmdb = item.ratings.find((r) => r.source === 'tmdb' && typeof r.value === 'number');
      if (tmdb && typeof tmdb.value === 'number') return Number((tmdb.value / 10).toFixed(1));
    }
    if (typeof item.score === 'number' && item.score > 0) {
      return Number((item.score / 10).toFixed(1));
    }
    return 0;
  }

  static parseVotes(item: MdblistItem): number {
    if (Array.isArray(item.ratings)) {
      const imdb = item.ratings.find((r) => r.source === 'imdb' && typeof r.votes === 'number');
      if (imdb && typeof imdb.votes === 'number') return imdb.votes;
      const tmdb = item.ratings.find((r) => r.source === 'tmdb' && typeof r.votes === 'number');
      if (tmdb && typeof tmdb.votes === 'number') return tmdb.votes;
    }
    return 0;
  }
}
