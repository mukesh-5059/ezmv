import { Bindings, PaginatedMoviesResponse, RequestTrace, SearchFilters } from '../types/api';
import { TraktSearchItem } from '../types/upstream';
import { CatalogService } from './catalog';
import { isProfane } from './profanity';

export class TraktSearchService {
  private clientId: string;
  private tmdbApiKey: string;
  private catalog: CatalogService;
  private baseUrl = 'https://api.trakt.tv';

  constructor(env: Bindings) {
    this.clientId = env.TRAKT_CLIENT_ID || '';
    this.tmdbApiKey = env.TMDB_API_KEY || '';
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

    if (!cleanQuery || isProfane(cleanQuery)) return emptyResponse;

    let endpointType = 'movie,show';
    if (filters?.media_type === 'movie')   endpointType = 'movie';
    else if (filters?.media_type === 'tv') endpointType = 'show';

    let url = `${this.baseUrl}/search/${endpointType}?query=${encodeURIComponent(cleanQuery)}&page=${page}&limit=${limit}`;
    if (filters?.genre) url += `&genres=${encodeURIComponent(filters.genre)}`;
    if (filters?.year)  url += `&years=${encodeURIComponent(String(filters.year))}`;

    try {
      if (!this.clientId) throw new Error('Missing TRAKT_CLIENT_ID');
      const tTrakt = Date.now();
      const resp = await fetch(url, {
        headers: {
          'Content-Type': 'application/json',
          'trakt-api-version': '2',
          'trakt-api-key': this.clientId,
          'User-Agent': 'CloudflareWorker/1.0',
        },
        signal: AbortSignal.timeout(10000),
      });

      if (!resp.ok) {
        console.warn(`[Trakt search error] HTTP ${resp.status} for ${url}, falling back to TMDb`);
        return this.searchTmdb(cleanQuery, page, filters, trace);
      }

      const pageHeader = Number(resp.headers.get('x-pagination-page')) || page;
      const totalPages = Number(resp.headers.get('x-pagination-page-count')) || 0;
      const totalItems = Number(resp.headers.get('x-pagination-item-count')) || 0;

      const rawItems: TraktSearchItem[] = await resp.json();
      const imdbIds: string[] = [];
      if (trace) trace.add(`trakt search: ${rawItems.length} items ${Date.now() - tTrakt}ms`);

      for (const item of rawItems) {
        const payload = item.movie || item.show;
        if (isProfane(payload?.title)) continue;
        const imdbId = payload?.ids?.imdb;
        if (imdbId && imdbId.startsWith('tt')) imdbIds.push(imdbId);
      }

      if (!imdbIds.length) return emptyResponse;

      let movies = await this.catalog.resolveMovies(imdbIds, trace, filters?.media_type);

      if (filters?.min_rating !== undefined && filters.min_rating > 0)
        movies = movies.filter((m) => m.rating_score >= filters.min_rating!);

      if (movies.length === 0) return emptyResponse;

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
      console.warn(`[Trakt search error] ${cleanQuery}:`, err.message, 'falling back to TMDb');
      return this.searchTmdb(cleanQuery, page, filters, trace);
    }
  }

  private async searchTmdb(
    cleanQuery: string,
    page = 1,
    filters?: SearchFilters,
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

    if (!this.tmdbApiKey || isProfane(cleanQuery)) return emptyResponse;

    let path = 'search/multi';
    if (filters?.media_type === 'movie') path = 'search/movie';
    else if (filters?.media_type === 'tv') path = 'search/tv';

    let url = `https://api.themoviedb.org/3/${path}?query=${encodeURIComponent(cleanQuery)}&page=${page}&api_key=${this.tmdbApiKey}`;
    if (filters?.year) {
      if (filters.media_type === 'tv') url += `&first_air_date_year=${filters.year}`;
      else url += `&year=${filters.year}`;
    }

    try {
      const tTmdb = Date.now();
      const resp = await fetch(url, { signal: AbortSignal.timeout(10000) });
      if (!resp.ok) return emptyResponse;

      const data: any = await resp.json();
      const results: any[] = data.results || [];
      if (trace) trace.add(`tmdb search: ${results.length} items ${Date.now() - tTmdb}ms`);
      const tmdbItems: Array<{ id: number; media_type: 'movie' | 'tv' }> = [];

      for (const item of results) {
        if (item.adult === true) continue;
        if (isProfane(item.title || item.name)) continue;
        const mType = item.media_type || (filters?.media_type === 'tv' ? 'tv' : 'movie');
        if (mType === 'movie' || mType === 'tv') {
          tmdbItems.push({ id: item.id, media_type: mType });
        }
      }

      if (!tmdbItems.length) return emptyResponse;

      let movies = await this.catalog.resolveByTmdbItems(tmdbItems, trace);
      if (filters?.min_rating !== undefined && filters.min_rating > 0) {
        movies = movies.filter((m) => m.rating_score >= filters.min_rating!);
      }

      const totalPages = data.total_pages || 1;
      const totalItems = data.total_results || movies.length;
      const hasMore = page < totalPages;

      return {
        items: movies,
        page,
        total_pages: totalPages,
        total_items: totalItems,
        has_more: hasMore,
        next_page: hasMore ? page + 1 : null,
      };
    } catch (err: any) {
      console.warn(`[TMDB fallback search error] ${cleanQuery}:`, err.message);
      return emptyResponse;
    }
  }
}
