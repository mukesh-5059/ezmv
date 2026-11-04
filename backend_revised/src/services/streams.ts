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

    const penguBase = (this.env.PENGUPLAY_MANIFEST_URL || '').replace(
      /\/manifest\.json\/?$/,
      ''
    );
    const hdhubBase = (this.env.HDHUB_MANIFEST_URL || '').replace(
      /\/manifest\.json\/?$/,
      ''
    );

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
        const timeoutId = setTimeout(() => controller.abort(), 8000);
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

    const [penguResults, hdhubResults] = await Promise.allSettled([
      fetchAddon(penguBase, 'penguplay'),
      fetchAddon(hdhubBase, 'hdhub'),
    ]);

    const penguStreams =
      penguResults.status === 'fulfilled' ? penguResults.value : [];
    const hdhubStreams =
      hdhubResults.status === 'fulfilled' ? hdhubResults.value : [];

    const allStreams = [...penguStreams, ...hdhubStreams].sort(
      (a, b) => (a.priority ?? 100) - (b.priority ?? 100)
    );

    return {
      imdb_id: imdbId,
      media_type: mediaType,
      season: mediaType === 'tv' ? season : undefined,
      episode: mediaType === 'tv' ? episode : undefined,
      streams: allStreams,
    };
  }
}
