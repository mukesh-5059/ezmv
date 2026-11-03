import {
  ActorSummary,
  Bindings,
  MovieSummary,
  PersonDetailsResponse,
  RequestTrace,
  TmdbCredit,
} from '../types';
import curatedActors from '../config/actors.json';
import { CatalogService } from './catalog';

const EXCLUDED_GENRE_IDS = new Set([99, 10763, 10764, 10767]);

function isExcludedCharacter(character?: string): boolean {
  if (!character) return false;
  const c = character.toLowerCase();
  return (
    c.includes('cameo') ||
    c.includes('uncredited') ||
    c.includes('voice') ||
    c.includes('narrat') ||
    c.includes('self') ||
    c.includes('himself') ||
    c.includes('herself')
  );
}

export class ActorsService {
  private env: Bindings;
  private tmdbApiKey?: string;

  constructor(env: Bindings) {
    this.env = env;
    this.tmdbApiKey = env.TMDB_API_KEY;
  }

  getCuratedActors(): ActorSummary[] {
    return curatedActors as ActorSummary[];
  }

  async getPersonDetails(personId: number, trace?: RequestTrace): Promise<PersonDetailsResponse | null> {
    if (!this.tmdbApiKey || !personId) return null;

    const url = `https://api.themoviedb.org/3/person/${personId}?api_key=${this.tmdbApiKey}&append_to_response=combined_credits`;
    const tTmdb = Date.now();
    let data: any = null;

    try {
      const resp = await fetch(url, {
        headers: { Accept: 'application/json', 'User-Agent': 'CloudflareWorker/1.0' },
        signal: AbortSignal.timeout(8000),
      });

      if (!resp.ok) return null;

      data = await resp.json();
    } catch (err: any) {
      console.warn(`[TMDB person fetch error for ${personId}]:`, err.message);
      return null;
    }

    if (trace) trace.add(`tmdb_person: ${Date.now() - tTmdb}ms`);

    const rawCredits: TmdbCredit[] = Array.isArray(data.combined_credits?.cast)
      ? data.combined_credits.cast
      : [];

    const seen = new Set<string>();
    const allItems: Array<{ id: number; media_type: 'movie' | 'tv' }> = [];
    for (const c of rawCredits) {
      if (!c.id || !c.media_type) continue;
      if (Array.isArray(c.genre_ids) && c.genre_ids.some((gid) => EXCLUDED_GENRE_IDS.has(gid))) continue;
      if (isExcludedCharacter(c.character)) continue;
      if (typeof c.order === 'number' && c.order > 20) continue;

      const key = `${c.media_type}:${c.id}`;
      if (!seen.has(key)) {
        seen.add(key);
        allItems.push({ id: c.id, media_type: c.media_type });
      }
    }

    const catalog = new CatalogService(this.env);
    const resolvedItems = await catalog.resolveByTmdbItems(allItems, trace);

    const nowIso = new Date().toISOString().slice(0, 10);

    const sortedByPopularity = [...resolvedItems].sort((a, b) => {
      if (b.rating_score !== a.rating_score) return b.rating_score - a.rating_score;
      return b.vote_count - a.vote_count;
    });

    const popular = sortedByPopularity
      .filter((item) => item.rating_score > 0 || item.vote_count > 0)
      .slice(0, 30);

    const recent = [...resolvedItems]
      .filter((item) => item.release_date && item.release_date.length >= 4 && item.release_date <= nowIso)
      .sort((a, b) => b.release_date.localeCompare(a.release_date))
      .slice(0, 30);

    return {
      tmdb_id: data.id,
      name: data.name || '',
      biography: data.biography || '',
      profile_path: data.profile_path ? `https://image.tmdb.org/t/p/w500${data.profile_path}` : null,
      popular,
      recent,
    };
  }
}
