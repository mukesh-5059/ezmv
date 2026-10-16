import { MovieSummaryResponse } from '../types';

export class TursoService {
  private httpUrl: string;

  constructor(private url: string, private token: string) {
    this.httpUrl = url.replace('libsql://', 'https://').replace(/\/$/, '') + '/v2/pipeline';
  }

  async getCatalogMovie(id: string | number): Promise<MovieSummaryResponse | null> {
    const isNumeric = typeof id === 'number' || /^\d+$/.test(id.toString());
    const sql = isNumeric
      ? 'SELECT imdb_id, tmdb_id, title, release_date, rating, votes, poster_path, backdrop_path, overview FROM v_catalog WHERE tmdb_id = ? LIMIT 1;'
      : 'SELECT imdb_id, tmdb_id, title, release_date, rating, votes, poster_path, backdrop_path, overview FROM v_catalog WHERE imdb_id = ? LIMIT 1;';

    const args = isNumeric
      ? [{ type: 'integer', value: String(id) }]
      : [{ type: 'text', value: id.toString() }];

    try {
      const resp = await fetch(this.httpUrl, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          requests: [
            {
              type: 'execute',
              stmt: { sql, args },
            },
          ],
        }),
      });

      if (!resp.ok) {
        return null;
      }

      const data = (await resp.json()) as any;
      const rows = data?.results?.[0]?.response?.result?.rows;
      if (rows && rows.length > 0) {
        const row = rows[0];
        return {
          imdb_id: row[0]?.value ? String(row[0].value) : null,
          tmdb_id: Number(row[1]?.value || 0),
          title: String(row[2]?.value || ''),
          release_date: String(row[3]?.value || ''),
          rating: Number(row[4]?.value || 0),
          vote_count: Number(row[5]?.value || 0),
          poster_path: String(row[6]?.value || ''),
          backdrop_path: String(row[7]?.value || ''),
          overview: String(row[8]?.value || ''),
          media_type: 'movie',
          genre_ids: [],
        };
      }
      return null;
    } catch {
      return null;
    }
  }

  async getRating(imdbId: string): Promise<{ rating: number; votes: number } | null> {
    try {
      const resp = await fetch(this.httpUrl, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          requests: [
            {
              type: 'execute',
              stmt: {
                sql: 'SELECT rating, votes FROM imdb_titles WHERE imdb_id = ?',
                args: [{ type: 'text', value: imdbId }],
              },
            },
          ],
        }),
      });

      if (!resp.ok) {
        return null;
      }

      const data = (await resp.json()) as any;
      const rows = data?.results?.[0]?.response?.result?.rows;
      if (rows && rows.length > 0) {
        return {
          rating: Number(rows[0][0].value),
          votes: Number(rows[0][1].value),
        };
      }
      return null;
    } catch {
      return null;
    }
  }

  async upsertMovie(movie: {
    imdb_id: string;
    tmdb_id?: number | null;
    title: string;
    release_date?: string | null;
    poster_path?: string | null;
    backdrop_path?: string | null;
    overview?: string | null;
  }): Promise<boolean> {
    const sql = `
      INSERT INTO movies (imdb_id, tmdb_id, title, release_date, poster_path, backdrop_path, overview, last_updated)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(imdb_id) DO UPDATE SET
        tmdb_id = COALESCE(excluded.tmdb_id, movies.tmdb_id),
        poster_path = COALESCE(excluded.poster_path, movies.poster_path),
        backdrop_path = COALESCE(excluded.backdrop_path, movies.backdrop_path),
        overview = COALESCE(excluded.overview, movies.overview),
        last_updated = excluded.last_updated;
    `;

    const now = Math.floor(Date.now() / 1000);
    const args = [
      { type: 'text', value: movie.imdb_id },
      movie.tmdb_id ? { type: 'integer', value: String(movie.tmdb_id) } : { type: 'null' },
      { type: 'text', value: movie.title },
      movie.release_date ? { type: 'text', value: movie.release_date } : { type: 'null' },
      movie.poster_path ? { type: 'text', value: movie.poster_path } : { type: 'null' },
      movie.backdrop_path ? { type: 'text', value: movie.backdrop_path } : { type: 'null' },
      { type: 'text', value: movie.overview || '' },
      { type: 'integer', value: String(now) },
    ];

    try {
      const resp = await fetch(this.httpUrl, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          requests: [{ type: 'execute', stmt: { sql, args } }],
        }),
      });
      return resp.ok;
    } catch {
      return false;
    }
  }
}

