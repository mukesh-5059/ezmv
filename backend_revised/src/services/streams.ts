import { Bindings, StreamProgressPayload, StreamSource, StreamsResponse } from '../types';
import { parseStreamItem } from './stream_parser';

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
    onProgress?: (progress: StreamProgressPayload) => Promise<void> | void;
  }): Promise<StreamsResponse> {
    const { imdbId, mediaType = 'movie', season, episode, defaultLanguage, onProgress } = params;

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
          .map((s) => parseStreamItem(s, providerName, defaultLanguage))
          .filter((s): s is StreamSource => s !== null);
        if (onProgress) await onProgress({ provider: displayName, status: 'resolved', count: parsed.length });
        return parsed;
      } catch {
        if (onProgress) await onProgress({ provider: displayName, status: 'resolved', count: 0 });
        return [];
      }
    };

    const streams: StreamSource[] = [];

    // Tier 1: High-priority primary scrapers (PlavioHD + HDHub)
    const tier1Fetches: Promise<StreamSource[]>[] = [];
    if (plavioBase) tier1Fetches.push(fetchAddon(plavioBase, 'plaviohd', 'PlavioHD'));
    if (hdhubBase) tier1Fetches.push(fetchAddon(hdhubBase, 'hdhub', 'HDHub'));

    const tier1Results = await Promise.allSettled(tier1Fetches);
    for (const res of tier1Results) {
      if (res.status === 'fulfilled') streams.push(...res.value);
    }

    // Tier 2 Fallback: If Tier 1 yields less than 20 streams, query PenguPlay + NoTorrent
    if (streams.length < 20) {
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

    // Sort by priority ascending and cap at top 20
    uniqueStreams.sort((a, b) => (a.priority ?? 100) - (b.priority ?? 100));
    const cappedStreams = uniqueStreams.slice(0, 20);

    return {
      imdb_id: imdbId,
      media_type: mediaType,
      season: mediaType === 'tv' ? season : undefined,
      episode: mediaType === 'tv' ? episode : undefined,
      streams: cappedStreams,
    };
  }
}
