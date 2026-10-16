export class CacheService {
  private cache: Cache;

  constructor() {
    this.cache = caches.default;
  }

  async get<T>(keyUrl: string): Promise<T | null> {
    try {
      const cacheKey = new Request(keyUrl);
      const cached = await this.cache.match(cacheKey);
      if (!cached) {
        console.log(`[Cache MISS] ${keyUrl}`);
        return null;
      }

      console.log(`[Cache HIT] ${keyUrl}`);
      return (await cached.json()) as T;
    } catch (_) {
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
      console.log(`[Cache SET] ${keyUrl} (TTL: ${ttlSeconds}s)`);
    } catch (_) {}
  }

  async delete(keyUrl: string): Promise<boolean> {
    try {
      const cacheKey = new Request(keyUrl);
      const deleted = await this.cache.delete(cacheKey);
      console.log(`[Cache DEL] ${keyUrl} (deleted: ${deleted})`);
      return deleted;
    } catch (_) {
      return false;
    }
  }
}
