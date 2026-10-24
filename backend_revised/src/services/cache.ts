export class CacheService {
  private cache: Cache;

  constructor() {
    this.cache = caches.default;
  }

  async get<T>(keyUrl: string): Promise<T | null> {
    try {
      const cacheKey = new Request(keyUrl);
      const cached = await this.cache.match(cacheKey);
      if (!cached) return null;
      return (await cached.json()) as T;
    } catch (err: any) {
      console.warn(`[Cache MATCH ERROR] ${keyUrl}:`, err.message);
      return null;
    }
  }

  async set(keyUrl: string, data: any, ttlSeconds: number): Promise<void> {
    try {
      const cacheKey = new Request(keyUrl);
      const cacheInit: ResponseInit = {
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': `public, max-age=${ttlSeconds}`,
        },
      };
      await this.cache.put(cacheKey, new Response(JSON.stringify(data), cacheInit));
    } catch (err: any) {
      console.warn(`[Cache PUT ERROR] ${keyUrl}:`, err.message);
    }
  }

  async delete(keyUrl: string): Promise<boolean> {
    try {
      const cacheKey = new Request(keyUrl);
      return await this.cache.delete(cacheKey);
    } catch (_) {
      return false;
    }
  }
}

