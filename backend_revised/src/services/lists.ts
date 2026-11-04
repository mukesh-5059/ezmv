import { Bindings, ListFilters, PaginatedListsResponse, PaginatedMoviesResponse, RequestTrace, TraktListSummary } from '../types/api';
import { CatalogService } from './catalog';

export class ListsService {
  private clientId: string;
  private catalog: CatalogService;
  private baseUrl = 'https://api.trakt.tv';

  constructor(env: Bindings) {
    this.clientId = env.TRAKT_CLIENT_ID || '';
    this.catalog = new CatalogService(env);
  }

  private getHeaders(): Record<string, string> {
    return {
      'Content-Type': 'application/json',
      'trakt-api-version': '2',
      'trakt-api-key': this.clientId,
      'User-Agent': 'MoviesStreamingApp/1.0',
    };
  }

  // Get popular curated lists from Trakt
  async getPopularLists(page = 1, limit = 100): Promise<PaginatedListsResponse> {
    const emptyResponse: PaginatedListsResponse = {
      items: [],
      page,
      total_pages: 0,
      total_items: 0,
      has_more: false,
      next_page: null,
    };

    if (!this.clientId) return emptyResponse;

    const url = `${this.baseUrl}/lists/popular?page=${page}&limit=${limit}`;

    try {
      const resp = await fetch(url, {
        headers: this.getHeaders(),
        signal: AbortSignal.timeout(10000),
      });

      if (!resp.ok) {
        console.warn(`[ListsService getPopularLists] HTTP ${resp.status} ${resp.statusText} for ${url}`);
        return emptyResponse;
      }

      const pageHeader = Number(resp.headers.get('x-pagination-page')) || page;
      const totalPages = Number(resp.headers.get('x-pagination-page-count')) || 0;
      const totalItems = Number(resp.headers.get('x-pagination-item-count')) || 0;

      const rawItems: any[] = await resp.json();
      const items: TraktListSummary[] = [];

      for (const entry of rawItems) {
        const l = entry.list;
        if (!l?.ids?.trakt) continue;

        items.push({
          id: l.ids.trakt,
          name: l.name || 'Untitled List',
          item_count: l.item_count || 0,
          likes: l.likes ?? entry.like_count ?? 0,
        });
      }

      const hasMore = pageHeader < totalPages;
      return {
        items,
        page: pageHeader,
        total_pages: totalPages,
        total_items: totalItems,
        has_more: hasMore,
        next_page: hasMore ? pageHeader + 1 : null,
      };
    } catch (err: any) {
      console.warn('[ListsService getPopularLists error]:', err.message);
      return emptyResponse;
    }
  }

  // Search curated lists by query
  async searchLists(query: string, page = 1, limit = 50): Promise<PaginatedListsResponse> {
    const cleanQuery = query.trim();

    const emptyResponse: PaginatedListsResponse = {
      items: [],
      page,
      total_pages: 0,
      total_items: 0,
      has_more: false,
      next_page: null,
    };

    if (!this.clientId || !cleanQuery) return emptyResponse;

    const url = `${this.baseUrl}/search/list?query=${encodeURIComponent(cleanQuery)}&page=${page}&limit=${limit}`;

    try {
      const resp = await fetch(url, {
        headers: this.getHeaders(),
        signal: AbortSignal.timeout(10000),
      });

      if (!resp.ok) {
        console.warn(`[ListsService searchLists] HTTP ${resp.status} ${resp.statusText} for ${url}`);
        return emptyResponse;
      }

      const pageHeader = Number(resp.headers.get('x-pagination-page')) || page;
      const totalPages = Number(resp.headers.get('x-pagination-page-count')) || 0;
      const totalItems = Number(resp.headers.get('x-pagination-item-count')) || 0;

      const rawItems: any[] = await resp.json();
      const items: TraktListSummary[] = [];

      for (const entry of rawItems) {
        const l = entry.list;
        if (!l?.ids?.trakt) continue;

        items.push({
          id: l.ids.trakt,
          name: l.name || 'Untitled List',
          item_count: l.item_count || 0,
          likes: l.likes ?? entry.like_count ?? 0,
        });
      }

      const hasMore = pageHeader < totalPages;
      return {
        items,
        page: pageHeader,
        total_pages: totalPages,
        total_items: totalItems,
        has_more: hasMore,
        next_page: hasMore ? pageHeader + 1 : null,
      };
    } catch (err: any) {
      console.warn(`[ListsService searchLists error] ${cleanQuery}:`, err.message);
      return emptyResponse;
    }
  }

  // Get items in a specific list with filtering and sorting
  async getListItems(
    listId: number,
    page = 1,
    limit = 100,
    filters?: ListFilters,
    trace?: RequestTrace
  ): Promise<PaginatedMoviesResponse> {
    const emptyResponse: PaginatedMoviesResponse = {
      items: [],
      page,
      total_pages: 0,
      total_items: 0,
      has_more: false,
      next_page: null,
    };

    if (!listId || listId <= 0 || !this.clientId) return emptyResponse;

    let typeSegment = '';
    if (filters?.media_type === 'movie') {
      typeSegment = '/movies';
    } else if (filters?.media_type === 'tv') {
      typeSegment = '/shows';
    }

    let url = `${this.baseUrl}/lists/${encodeURIComponent(listId)}/items${typeSegment}?page=${page}&limit=${limit}`;

    if (filters?.sort_by) {
      url += `&sort_by=${encodeURIComponent(filters.sort_by)}`;
    }
    if (filters?.sort_order) {
      url += `&sort_how=${encodeURIComponent(filters.sort_order)}`;
    }

    try {
      const tTrakt = Date.now();
      const resp = await fetch(url, {
        headers: this.getHeaders(),
        signal: AbortSignal.timeout(10000),
      });

      if (!resp.ok) {
        console.warn(`[ListsService getListItems] HTTP ${resp.status} ${resp.statusText} for ${url}`);
        return emptyResponse;
      }

      const pageHeader = Number(resp.headers.get('x-pagination-page')) || page;
      const totalPages = Number(resp.headers.get('x-pagination-page-count')) || 0;
      const totalItems = Number(resp.headers.get('x-pagination-item-count')) || 0;

      const rawItems: any[] = await resp.json();
      if (trace) trace.add(`trakt: LIST_ITEMS ${Date.now() - tTrakt}ms (${rawItems.length} raw)`);

      // Extract valid tt... IMDb IDs only (strict IMDb requirement)
      const imdbIds: string[] = [];
      for (const item of rawItems) {
        const payload = item.movie || item.show;
        const iid = payload?.ids?.imdb;
        if (iid && typeof iid === 'string' && iid.startsWith('tt')) {
          imdbIds.push(iid);
        }
      }

      if (!imdbIds.length) {
        return {
          items: [],
          page: pageHeader,
          total_pages: totalPages,
          total_items: totalItems,
          has_more: pageHeader < totalPages,
          next_page: pageHeader < totalPages ? pageHeader + 1 : null,
        };
      }

      // Resolve metadata & ratings via D1 + on-demand MDBList batching
      const mediaType = filters?.media_type || 'all';
      let movies = await this.catalog.resolveMovies(imdbIds, trace, mediaType);

      // In-memory post-filters for precision
      if (filters?.min_rating !== undefined && filters.min_rating > 0) {
        movies = movies.filter((m) => m.rating_score >= filters.min_rating!);
      }

      if (filters?.genre) {
        const g = filters.genre.toLowerCase();
        movies = movies.filter((m) =>
          m.genres?.some((x) => x.slug?.toLowerCase() === g)
        );
      }

      if (filters?.year !== undefined) {
        const yStr = String(filters.year);
        movies = movies.filter((m) => m.release_date?.startsWith(yStr));
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
      console.warn(`[ListsService getListItems error] ${listId}:`, err.message);
      return emptyResponse;
    }
  }
}
