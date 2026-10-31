import { MdblistItem } from '../types/upstream';

export class MdblistService {
  private apiKey: string;
  private baseUrl = 'https://api.mdblist.com';

  constructor(apiKey?: string) {
    this.apiKey = apiKey || '';
  }

  async batchMovies(imdbIds: string[], mediaType: 'all' | 'movie' | 'tv' = 'all'): Promise<MdblistItem[]> {
    if (!this.apiKey || imdbIds.length === 0) return [];

    const results: MdblistItem[] = [];
    const targetType = mediaType === 'tv' ? 'show' : (mediaType === 'movie' ? 'movie' : null);

    if (targetType) {
      for (let i = 0; i < imdbIds.length; i += 100) {
        const chunk = imdbIds.slice(i, i + 100);
        const res = await this.postBatch(targetType, chunk);
        results.push(...res);
      }
    } else {
      const resolved = new Set<string>();
      for (let i = 0; i < imdbIds.length; i += 100) {
        const chunk = imdbIds.slice(i, i + 100);
        const res = await this.postBatch('movie', chunk);
        for (const item of res) {
          const id = item.ids?.imdb || item.imdbid;
          if (id) resolved.add(id);
        }
        results.push(...res);
      }

      const remaining = imdbIds.filter((id) => !resolved.has(id));
      if (remaining.length > 0) {
        for (let i = 0; i < remaining.length; i += 100) {
          const chunk = remaining.slice(i, i + 100);
          const res = await this.postBatch('show', chunk);
          results.push(...res);
        }
      }
    }

    return results;
  }

  private async postBatch(mediaType: 'movie' | 'show', ids: string[]): Promise<MdblistItem[]> {
    const url = `${this.baseUrl}/imdb/${mediaType}/?apikey=${this.apiKey}`;
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
        console.warn(`[MDBList postBatch error] imdb/${mediaType} status ${resp.status}`);
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
      if (imdb) return Number(imdb.value.toFixed(1));
    }
    if (typeof item.score === 'number' && item.score > 0) {
      return Number((item.score / 10).toFixed(1));
    }
    return 0;
  }

  static parseVotes(item: MdblistItem): number {
    if (Array.isArray(item.ratings)) {
      const imdb = item.ratings.find((r) => r.source === 'imdb' && typeof r.votes === 'number');
      if (imdb?.votes !== undefined) return imdb.votes;
    }
    return 0;
  }
}
