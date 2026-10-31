import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { Bindings, Variables } from './types';
import { dashboardRouter } from './routes/dashboard';
import { moviesRouter } from './routes/movies';
import { searchRouter } from './routes/search';
import { subtitlesRouter } from './routes/subtitles';
import { GENRES } from './config/genres';

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>();

app.use('*', cors());

// Diagnostic & Latency logger middleware
app.use('*', async (c, next) => {
  const start = Date.now();
  const url = new URL(c.req.url);
  const target = url.pathname + url.search;

  const traceSteps: string[] = [];
  c.set('trace', {
    steps: traceSteps,
    add(step: string) {
      traceSteps.push(step);
    },
  });

  await next();

  const total = Date.now() - start;
  const trace = c.get('trace');
  const traceOutput = trace && trace.steps.length > 0 ? ` [${trace.steps.join(' -> ')}]` : '';
  console.log(`[${c.res.status}] ${c.req.method} ${target} | total: ${total}ms${traceOutput}`);
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

// Canonical genre list for client filter pills
app.get('/api/v1/genres', (c) => {
  return c.json(GENRES, 200, {
    'Cache-Control': 'public, max-age=2592000, stale-while-revalidate=86400',
  });
});

export default app;
