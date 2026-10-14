export class CacheService {
  private cache: Cache;

  constructor() {
    this.cache = caches.default;
  }

  async get<T>(keyUrl: string): Promise<{ data: T; ttlSeconds: number } | null> {
    try {
      const cacheKey = new Request(keyUrl);
      const cached = await this.cache.match(cacheKey);
      if (!cached) return null;

      const data = (await cached.json()) as T;
      const ttlHeader = cached.headers.get('X-Cache-TTL') || '86400s';
      const ttlSeconds = parseInt(ttlHeader, 10) || 86400;

      return { data, ttlSeconds };
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
          'X-Cache-TTL': `${ttlSeconds}s`,
        },
      };
      await this.cache.put(cacheKey, new Response(JSON.stringify(data), cacheInit));
    } catch (_) {}
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
