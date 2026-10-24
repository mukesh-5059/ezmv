import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { Bindings, Variables } from './types';
import { dashboardRouter } from './routes/dashboard';
import { moviesRouter } from './routes/movies';
import { searchRouter } from './routes/search';
import { subtitlesRouter } from './routes/subtitles';

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>();

app.use('*', cors());

// Diagnostic & Latency logger middleware
app.use('*', async (c, next) => {
  const start = Date.now();
  const url = new URL(c.req.url);
  const target = url.pathname + url.search;

  c.set('trace', {
    cache: 'SKIP',
    d1: 'SKIP',
    mdblist: 'SKIP',
    trakt: 'SKIP',
  });

  await next();

  const total = Date.now() - start;
  const trace = c.get('trace') || { cache: 'SKIP', d1: 'SKIP', mdblist: 'SKIP', trakt: 'SKIP' };
  console.log(`[${c.res.status}] ${c.req.method} ${target} | total: ${total}ms [cache: ${trace.cache} | d1: ${trace.d1} | mdblist: ${trace.mdblist} | trakt: ${trace.trakt}]`);
});

// Root health check
app.get('/', (c) => {
  return c.json({
    status: 'online',
    message: 'Movie Streaming Backend API is running.',
  });
});

// Mount separate routes
app.route('/api/v1/dashboard', dashboardRouter);
app.route('/api/v1/movies', moviesRouter);
app.route('/api/v1/search', searchRouter);
app.route('/api/v1/subtitles', subtitlesRouter);

// Diagnostic D1 check
app.get('/api/v1/imdb/:id', async (c) => {
  const imdbId = c.req.param('id');
  const result = await c.env.DB.prepare('SELECT * FROM v_movies WHERE imdb_id = ?')
    .bind(imdbId)
    .first();

  if (!result) {
    return c.json({ error: 'Title not found' }, 404);
  }

  return c.json(result);
});

export default app;
