import { CompositeRating, MdblistItem, MdblistRating } from '../types/upstream';

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
        const res = await this.postBatch('imdb', targetType, chunk);
        results.push(...res);
      }
    } else {
      const resolved = new Set<string>();
      for (let i = 0; i < imdbIds.length; i += 100) {
        const chunk = imdbIds.slice(i, i + 100);
        const res = await this.postBatch('imdb', 'movie', chunk);
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
          const res = await this.postBatch('imdb', 'show', chunk);
          results.push(...res);
        }
      }
    }

    return results;
  }

  async batchByTmdbIds(
    items: Array<{ id: number; media_type: 'movie' | 'tv' }>
  ): Promise<MdblistItem[]> {
    if (!this.apiKey || items.length === 0) return [];

    const movieIds = Array.from(new Set(items.filter((i) => i.media_type === 'movie').map((i) => i.id)));
    const tvIds = Array.from(new Set(items.filter((i) => i.media_type === 'tv').map((i) => i.id)));

    const results: MdblistItem[] = [];

    for (let i = 0; i < movieIds.length; i += 100) {
      const chunk = movieIds.slice(i, i + 100);
      const res = await this.postBatch('tmdb', 'movie', chunk);
      results.push(...res);
    }

    for (let i = 0; i < tvIds.length; i += 100) {
      const chunk = tvIds.slice(i, i + 100);
      const res = await this.postBatch('tmdb', 'show', chunk);
      results.push(...res);
    }

    return results;
  }

  private async postBatch(
    provider: 'imdb' | 'tmdb',
    mediaType: 'movie' | 'show',
    ids: Array<string | number>
  ): Promise<MdblistItem[]> {
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
  static computeRating(item: MdblistItem): CompositeRating {
    const rawRatings = Array.isArray(item.ratings) ? item.ratings : [];
    let weightedSum = 0;
    let totalWeight = 0;
    let totalVotes = 0;
    const cleanedRatings: MdblistRating[] = [];
    const qualifiedSources = new Set<string>();

    for (const r of rawRatings) {
      if (!r || !r.source) continue;
      cleanedRatings.push({
        source: r.source,
        value: r.value,
        score: r.score,
        votes: r.votes || 0,
      });

      const weight = SOURCE_WEIGHTS[r.source];
      if (!weight) continue;

      const minVotes = MIN_VOTES[r.source] ?? 0;
      const votes = r.votes || 0;
      if (votes < minVotes) continue;

      let normalized: number | null = null;
      if (typeof r.score === 'number') {
        normalized = r.score / 10;
      }

      if (normalized !== null) {
        weightedSum += normalized * weight;
        totalWeight += weight;
        totalVotes += votes;
        qualifiedSources.add(r.source);
      }
    }

    const ratingsJson = JSON.stringify(cleanedRatings);

    if (totalWeight > 0 && qualifiedSources.size > 0) {
      const rawRating = weightedSum / totalWeight;
      const numSources = qualifiedSources.size;

      let m = 1000;
      if (numSources === 1) m = 10000;
      else if (numSources === 2) m = 3000;

      // Era modifier: exponential recency decay + slow classic boost
      const now = new Date();
      const currentYear = now.getUTCFullYear();
      let age: number | null = null;

      const relDateStr = item.released || (item as any).release_date;
      if (typeof relDateStr === 'string' && relDateStr.length >= 4) {
        const d = new Date(relDateStr);
        if (!isNaN(d.getTime())) {
          age = Math.max(0, (now.getTime() - d.getTime()) / (1000 * 60 * 60 * 24 * 365.25));
        }
      }
      if (age === null && typeof item.year === 'number') {
        age = Math.max(0, currentYear - item.year);
      }

      if (age !== null) {
        const penalty = 0.5 * Math.exp(-age * 1.5);
        const boost = 0.5 * Math.max(0, Math.min(1, (age - 3) / 25));
        const rawEra = Math.max(0.5, Math.min(1.5, 1.0 + penalty - boost));
        // Anti-double-penalty: distribute recency skepticism across corroborated sources
        const eraModifier = 1.0 + (rawEra - 1.0) / numSources;
        m *= eraModifier;
      }

      const C = 6.8;
      const rating_score = Number(
        (((totalVotes / (totalVotes + m)) * rawRating) + ((m / (totalVotes + m)) * C)).toFixed(1)
      );

      return { rating_score, votes: totalVotes, ratingsJson };
    }

    return { rating_score: 0, votes: 0, ratingsJson };
  }
}

export const MIN_VOTES: Record<string, number> = {
  imdb: 500,
  letterboxd: 50,
  tomatoes: 10,
  popcorn: 50,
  tomatoesaudience: 50,
  tmdb: 20,
  metacritic: 5,
  trakt: 20,
};

export const SOURCE_WEIGHTS: Record<string, number> = {
  imdb: 0.30,
  letterboxd: 0.25,
  tomatoes: 0.15,
  popcorn: 0.10,
  tomatoesaudience: 0.10,
  tmdb: 0.10,
  metacritic: 0.05,
  trakt: 0.05,
};
