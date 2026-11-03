import defaultRatingRules from '../config/rating_rules.json';
import defaultActors from '../config/actors.json';
import defaultDashboardList from '../config/dashboardlist.json';
import defaultTamilDashboard from '../config/dashboards/tamil.json';
import { ActorSummary, DashboardConfig } from '../types/api';
import { DashboardsList, RatingRules } from '../types/config';
import { CacheService } from './cache';

const DEFAULT_DASHBOARDS: Record<string, DashboardConfig> = {
  tamil: defaultTamilDashboard as DashboardConfig,
};

export class ConfigService {
  private kv: KVNamespace;
  private cache: CacheService;

  constructor(kv: KVNamespace) {
    this.kv = kv;
    this.cache = new CacheService();
  }

  private async loadConfig<T>(key: string, defaultVal: T, ttlSeconds = 3600): Promise<T> {
    const cacheUrl = `https://cache.internal/config/${key}`;
    const cached = await this.cache.get<T>(cacheUrl);
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

  async getRatingRules(): Promise<RatingRules> {
    return this.loadConfig<RatingRules>('rating_rules', defaultRatingRules as RatingRules);
  }

  async getCuratedActors(): Promise<ActorSummary[]> {
    return this.loadConfig<ActorSummary[]>('curated_actors', defaultActors as ActorSummary[]);
  }

  async getDashboards(): Promise<DashboardsList> {
    return this.loadConfig<DashboardsList>('dashboards', defaultDashboardList as DashboardsList);
  }

  async getDashboard(id: string): Promise<DashboardConfig | null> {
    const normId = id.trim().toLowerCase();
    const fallback = DEFAULT_DASHBOARDS[normId] || null;
    return this.loadConfig<DashboardConfig | null>(`dashboard:${normId}`, fallback);
  }
}
