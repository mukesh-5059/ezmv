import { Bindings, PaginatedMoviesResponse, RequestTrace, SearchFilters } from '../types/api';
import { CatalogService } from './catalog';
import { isProfane } from './profanity';

export class TmdbSearchService {
  private tmdbApiKey: string;
  private catalog: CatalogService;

  constructor(env: Bindings) {
    this.tmdbApiKey = env.TMDB_API_KEY || '';
    this.catalog = new CatalogService(env);
  }

  async search(
    query: string,
    page = 1,
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

    if (!this.tmdbApiKey || !cleanQuery || isProfane(cleanQuery)) return emptyResponse;

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
      movies = movies.filter((m) => !isProfane(m.title) && !isProfane(m.overview));
      if (filters?.media_type && filters.media_type !== 'all') {
        movies = movies.filter((m) => m.media_type === filters.media_type);
      }
      if (filters?.genre) {
        const target = filters.genre.toLowerCase();
        movies = movies.filter((m) => m.genres.some((g) => g.slug.toLowerCase() === target));
      }
      if (filters?.min_rating !== undefined && filters.min_rating > 0) {
        movies = movies.filter((m) => m.rating_score >= filters.min_rating!);
      }
      if (filters?.year !== undefined) {
        movies = movies.filter((m) => {
          const y = m.release_date ? parseInt(m.release_date.substring(0, 4), 10) : undefined;
          if (y === undefined || isNaN(y)) return false;
          if (filters.year === 2020) return y >= 2020 && y <= 2029;
          if (filters.year === 2010) return y >= 2010 && y <= 2019;
          if (filters.year === 2000) return y >= 2000 && y <= 2009;
          if (filters.year === 1990) return y >= 1990 && y <= 1999;
          if (filters.year === 1980) return y < 1990;
          return y === filters.year;
        });
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
      console.warn(`[TMDB search error] ${cleanQuery}:`, err?.message || err);
      return emptyResponse;
    }
  }
}
