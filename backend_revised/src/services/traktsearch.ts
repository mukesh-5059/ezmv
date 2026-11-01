import { Bindings, PaginatedMoviesResponse, RequestTrace, SearchFilters } from '../types/api';
import { TraktSearchItem } from '../types/upstream';
import { CatalogService } from './catalog';

export class TraktSearchService {
  private clientId: string;
  private catalog: CatalogService;
  private baseUrl = 'https://api.trakt.tv';

  constructor(env: Bindings) {
    this.clientId = env.TRAKT_CLIENT_ID || '';
    this.catalog = new CatalogService(env);
  }

  async search(
    query: string,
    page = 1,
    limit = 100,
    filters?: SearchFilters,
    trace?: RequestTrace
  ): Promise<PaginatedMoviesResponse> {
    const cleanQuery = query.trim();
    const emptyResponse: PaginatedMoviesResponse = {
      items: [],
      page,
      total_pages: 0,
      total_items: 0,
      has_more: false,
      next_page: null,
    };

    if (!cleanQuery || !this.clientId) return emptyResponse;

    let endpointType = 'movie,show';
    if (filters?.media_type === 'movie') {
      endpointType = 'movie';
    } else if (filters?.media_type === 'tv') {
      endpointType = 'show';
    }

    let url = `${this.baseUrl}/search/${endpointType}?query=${encodeURIComponent(cleanQuery)}&page=${page}&limit=${limit}`;
    if (filters?.genre) {
      url += `&genres=${encodeURIComponent(filters.genre)}`;
    }
    if (filters?.year) {
      url += `&years=${encodeURIComponent(String(filters.year))}`;
    }

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
        const imdbId = payload?.ids?.imdb;
        if (imdbId && imdbId.startsWith('tt')) {
          imdbIds.push(imdbId);
        }
      }

      if (!imdbIds.length) return emptyResponse;

      let movies = await this.catalog.resolveMovies(imdbIds, trace, filters?.media_type);

      if (filters?.min_rating !== undefined && filters.min_rating > 0) {
        movies = movies.filter((m) => m.rating_score >= filters.min_rating!);
      }

      const hasMore = pageHeader < totalPages;
      return {
        items: movies,
        page: pageHeader,
        total_pages: totalPages,
        total_items: totalItems,
        has_more: hasMore,
        next_page: hasMore ? pageHeader + 1 : null,
      };
    } catch (err: any) {
      console.warn(`[Trakt search error] ${cleanQuery}:`, err.message);
      return emptyResponse;
    }
  }
}
