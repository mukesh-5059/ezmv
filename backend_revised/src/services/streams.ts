import { Bindings, StreamSource, StreamsResponse } from '../types';
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
  }): Promise<StreamsResponse> {
    const { imdbId, mediaType = 'movie', season, episode, defaultLanguage } = params;

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
      providerName: string
    ): Promise<StreamSource[]> => {
      if (!baseUrl) return [];
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
        if (!res.ok) return [];
        const data = (await res.json()) as { streams?: any[] };
        if (!Array.isArray(data.streams)) return [];
        return data.streams
          .map((s) => parseStreamItem(s, providerName, defaultLanguage))
          .filter((s): s is StreamSource => s !== null);
      } catch {
        return [];
      }
    };

    // 1. Query Tier 1 (Direct CDNs: PlavioHD + HDHub)
    const primaryFetches: Promise<StreamSource[]>[] = [];
    if (plavioBase) primaryFetches.push(fetchAddon(plavioBase, 'plaviohd'));
    if (hdhubBase) primaryFetches.push(fetchAddon(hdhubBase, 'hdhub'));

    const primaryResults = await Promise.allSettled(primaryFetches);
    const streams: StreamSource[] = [];
    for (const res of primaryResults) {
      if (res.status === 'fulfilled') streams.push(...res.value);
    }

    // 2. Fallback to Tier 2 (PenguPlay + NoTorrent) if primary streams < 3
    if (streams.length < 3) {
      const secondaryFetches: Promise<StreamSource[]>[] = [];
      if (penguBase) secondaryFetches.push(fetchAddon(penguBase, 'penguplay'));
      if (notorrentBase) secondaryFetches.push(fetchAddon(notorrentBase, 'notorrent'));

      const secondaryResults = await Promise.allSettled(secondaryFetches);
      for (const res of secondaryResults) {
        if (res.status === 'fulfilled') streams.push(...res.value);
      }
    }

    // 3. Deduplicate by exact URL and (filename + size_bytes)
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

    // 4. Sort by priority ascending and cap at top 20
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
