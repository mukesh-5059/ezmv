import defaultRatingRules from '../config/rating_rules.json';
import defaultActors from '../config/actors.json';
import { ActorSummary } from '../types/api';
import { RatingRules } from '../types/config';
import { CacheService } from './cache';

export class ConfigService {
  private kv: KVNamespace;
  private cache: CacheService;

  constructor(kv: KVNamespace) {
    this.kv = kv;
    this.cache = new CacheService();
  }

  private async loadConfig<T>(key: string, defaultVal: T, ttlSeconds = 3600, refresh = false): Promise<T> {
    const cacheUrl = `https://cache.internal/config/${key}`;
    const cached = refresh ? null : await this.cache.get<T>(cacheUrl);
    if (cached) return cached;

    if (this.kv) {
      try {
        const remote = await this.kv.get<T>(key, 'json');
        if (remote) {
          await this.cache.set(cacheUrl, remote, ttlSeconds);
          return remote;
        }
      } catch (e: any) {
        console.warn(`[ConfigService: ${key} KV fetch error]:`, e.message);
      }
    }

    return defaultVal;
  }

  async getRatingRules(refresh = false): Promise<RatingRules> {
    return this.loadConfig<RatingRules>('rating_rules', defaultRatingRules as RatingRules, 3600, refresh);
  }

  async getCuratedActors(refresh = false): Promise<ActorSummary[]> {
    return this.loadConfig<ActorSummary[]>('curated_actors', defaultActors as ActorSummary[], 3600, refresh);
  }
}
