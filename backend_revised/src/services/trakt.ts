import { TraktSearchItem, TraktSearchResponse } from '../types';

export class TraktService {
  private clientId: string;
  private baseUrl = 'https://api.trakt.tv';

  constructor(clientId?: string) {
    this.clientId = clientId || '';
  }

  async search(query: string, page = 1, limit = 100): Promise<TraktSearchResponse> {
    const cleanQuery = query.trim();
    const emptyResponse: TraktSearchResponse = {
      imdb_ids: [],
      page,
      total_pages: 0,
      total_items: 0,
    };

    if (!cleanQuery || !this.clientId) return emptyResponse;

    const url = `${this.baseUrl}/search/movie,show?query=${encodeURIComponent(cleanQuery)}&page=${page}&limit=${limit}`;

    try {
      const resp = await fetch(url, {
        headers: {
          'Content-Type': 'application/json',
          'trakt-api-version': '2',
          'trakt-api-key': this.clientId,
          'User-Agent': 'CloudflareWorker/1.0',
        },
        signal: AbortSignal.timeout(10000),
      });

      if (!resp.ok) return emptyResponse;

      const pageHeader = Number(resp.headers.get('x-pagination-page')) || page;
      const totalPages = Number(resp.headers.get('x-pagination-page-count')) || 0;
      const totalItems = Number(resp.headers.get('x-pagination-item-count')) || 0;

      const rawItems: TraktSearchItem[] = await resp.json();
      const imdbIds: string[] = [];

      for (const item of rawItems) {
        const payload = item.movie || item.show;
        if (payload?.ids?.imdb) {
          imdbIds.push(payload.ids.imdb);
        }
      }

      return {
        imdb_ids: imdbIds,
        page: pageHeader,
        total_pages: totalPages,
        total_items: totalItems,
      };
    } catch (err: any) {
      console.warn(`[Trakt search error] ${cleanQuery}:`, err.message);
      return emptyResponse;
    }
  }
}
