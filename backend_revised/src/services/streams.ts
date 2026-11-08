import { Bindings, StreamProgressPayload, StreamSource, StreamsResponse } from '../types';
import { calculatePriority, isIndianLanguage, parseStreamItem } from './stream_parser';

async function isStreamPlayable(stream: StreamSource): Promise<boolean> {
  const url = stream.url;
  if (!url || !url.startsWith('http')) return false;

  const lowerUrl = url.toLowerCase();
  if (
    lowerUrl.includes('/embed/') ||
    lowerUrl.includes('streamtape.com/e/') ||
    lowerUrl.includes('doodstream.com/d/') ||
    lowerUrl.includes('dood.to/d/') ||
    lowerUrl.includes('dood.so/d/')
  ) {
    return false;
  }

  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 2000);
    const headers: Record<string, string> = {
      'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      ...(stream.headers || {}),
    };

    const res = await fetch(url, {
      method: 'HEAD',
      headers,
      redirect: 'manual',
      signal: controller.signal,
    });
    clearTimeout(timeoutId);

    // Keep redirects (301, 302, 307, 308) and 403 (CF Worker datacenter IP block vs user residential IP)
    if ([301, 302, 307, 308, 403].includes(res.status)) return true;

    // Filter out explicit dead / missing / gateway errors
    if ([404, 410, 500, 502, 503, 504].includes(res.status)) return false;

    // Filter out HTML landing pages / Turnstile challenges
    const contentType = (res.headers.get('content-type') || '').toLowerCase();
    if (contentType.includes('text/html') || contentType.includes('application/xhtml+xml')) {
      return false;
    }

    // Filter out explicit 0-byte or empty responses
    const contentLength = res.headers.get('content-length');
    if (contentLength !== null && parseInt(contentLength, 10) === 0) {
      return false;
    }

    return true;
  } catch {
    // If probe times out or encounters network/TLS issue on worker, retain the stream
    return true;
  }
}

export class StreamsService {
  private env: Bindings;

  constructor(env: Bindings) {
    this.env = env;
  }

  async getStreams(params: {
    imdbId: string;
    mediaType?: 'movie' | 'tv';
    season?: number;
    episode?: number;
    defaultLanguage?: string;
    originalLanguage?: string;
    onProgress?: (progress: StreamProgressPayload) => Promise<void> | void;
  }): Promise<StreamsResponse> {
    const { imdbId, mediaType = 'movie', season, episode, defaultLanguage, originalLanguage, onProgress } = params;

    const plavioBase = (this.env.PLAVIOHD_MANIFEST_URL || '').replace(/\/manifest\.json\/?$/, '');
    const hdhubBase = (this.env.HDHUB_MANIFEST_URL || '').replace(/\/manifest\.json\/?$/, '');
    const penguBase = (this.env.PENGUPLAY_MANIFEST_URL || '').replace(/\/manifest\.json\/?$/, '');
    const notorrentBase = (this.env.NOTORRENT_MANIFEST_URL || '').replace(/\/manifest\.json\/?$/, '');

    const streamPath =
      mediaType === 'tv' && season && episode
        ? `/stream/series/${imdbId}:${season}:${episode}.json`
        : `/stream/movie/${imdbId}.json`;

    const fetchAddon = async (
      baseUrl: string,
      providerName: string,
      displayName: string
    ): Promise<StreamSource[]> => {
      if (onProgress) await onProgress({ provider: displayName, status: 'searching' });
      if (!baseUrl) {
        if (onProgress) await onProgress({ provider: displayName, status: 'resolved', count: 0 });
        return [];
      }
      const url = `${baseUrl}${streamPath}`;
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 10000);
        const res = await fetch(url, {
          headers: {
            'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
          signal: controller.signal,
        });
        clearTimeout(timeoutId);
        if (!res.ok) {
          if (onProgress) await onProgress({ provider: displayName, status: 'resolved', count: 0 });
          return [];
        }
        const data = (await res.json()) as { streams?: any[] };
        if (!Array.isArray(data.streams)) {
          if (onProgress) await onProgress({ provider: displayName, status: 'resolved', count: 0 });
          return [];
        }
        const parsed = data.streams
          .map((s) => parseStreamItem(s, providerName, defaultLanguage, originalLanguage))
          .filter((s): s is StreamSource => s !== null);
        if (onProgress) await onProgress({ provider: displayName, status: 'resolved', count: parsed.length });
        return parsed;
      } catch {
        if (onProgress) await onProgress({ provider: displayName, status: 'resolved', count: 0 });
        return [];
      }
    };

    const streams: StreamSource[] = [];

    // Tier 1 Execution (HDHub + PlavioHD)
    const tier1Fetches: Promise<StreamSource[]>[] = [];
    if (hdhubBase) tier1Fetches.push(fetchAddon(hdhubBase, 'hdhub', 'HDHub'));
    if (plavioBase) tier1Fetches.push(fetchAddon(plavioBase, 'plaviohd', 'PlavioHD'));

    const tier1Results = await Promise.allSettled(tier1Fetches);
    for (const res of tier1Results) {
      if (res.status === 'fulfilled') streams.push(...res.value);
    }

    // Tier 2 Fallback: If Tier 1 yields less than 15 streams, query PenguPlay + NoTorrent
    if (streams.length < 15) {
      const tier2Fetches: Promise<StreamSource[]>[] = [];
      if (penguBase) tier2Fetches.push(fetchAddon(penguBase, 'penguplay', 'PenguPlay'));
      if (notorrentBase) tier2Fetches.push(fetchAddon(notorrentBase, 'notorrent', 'NoTorrent'));

      const tier2Results = await Promise.allSettled(tier2Fetches);
      for (const res of tier2Results) {
        if (res.status === 'fulfilled') streams.push(...res.value);
      }
    }

    // Deduplicate by exact URL and (filename + size_bytes)
    const uniqueStreams: StreamSource[] = [];
    const seenUrls = new Set<string>();
    const seenFiles = new Set<string>();

    for (const s of streams) {
      if (seenUrls.has(s.url)) continue;
      seenUrls.add(s.url);

      if (s.filename && s.size_bytes) {
        const fileKey = `${s.filename.toLowerCase()}:${s.size_bytes}`;
        if (seenFiles.has(fileKey)) continue;
        seenFiles.add(fileKey);
      }

      uniqueStreams.push(s);
    }

    // Sort by priority ascending (HDHub has highest priority, then language & quality priority)
    uniqueStreams.sort((a, b) => {
      const aTop = a.provider.toLowerCase().includes('hdhub') ? 0 : 1;
      const bTop = b.provider.toLowerCase().includes('hdhub') ? 0 : 1;
      if (aTop !== bTop) return aTop - bTop;
      return (a.priority ?? 100) - (b.priority ?? 100);
    });

    // Probe top 15 candidate streams concurrently to filter out dead links (caps subrequests well below CF Free limit of 50)
    const candidates = uniqueStreams.slice(0, 15);
    const probeResults = await Promise.allSettled(candidates.map((s) => isStreamPlayable(s)));
    const playableStreams: StreamSource[] = [];

    for (let i = 0; i < candidates.length; i++) {
      const res = probeResults[i];
      if (res.status === 'fulfilled' && res.value) {
        playableStreams.push(candidates[i]);
      }
    }

    const cappedStreams = [
      ...playableStreams,
      ...uniqueStreams.slice(15),
    ].slice(0, 20);

    return {
      imdb_id: imdbId,
      media_type: mediaType,
      season: mediaType === 'tv' ? season : undefined,
      episode: mediaType === 'tv' ? episode : undefined,
      streams: cappedStreams,
    };
  }
}
