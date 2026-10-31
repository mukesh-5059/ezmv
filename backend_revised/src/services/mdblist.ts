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
  static computeRating(item: MdblistItem): CompositeRating {
    const rawRatings = Array.isArray(item.ratings) ? item.ratings : [];
    let weightedSum = 0;
    let totalWeight = 0;
    let totalVotes = 0;
    const cleanedRatings: MdblistRating[] = [];

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
      }
    }

    const ratingsJson = JSON.stringify(cleanedRatings);

    if (totalWeight > 0) {
      const rating_score = Number((weightedSum / totalWeight).toFixed(1));
      return { rating_score, votes: totalVotes, ratingsJson };
    }

    const fallbackScore = item.score_average;
    if (typeof fallbackScore === 'number' && fallbackScore > 0) {
      return {
        rating_score: Number((fallbackScore / 10).toFixed(1)),
        votes: 0,
        ratingsJson,
      };
    }

    return { rating_score: 0, votes: 0, ratingsJson };
  }
}

export const MIN_VOTES: Record<string, number> = {
  imdb: 100,
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
