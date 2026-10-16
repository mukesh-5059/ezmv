import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { Bindings } from './types';
import { moviesRouter } from './routes/movies';
import { subtitlesRouter } from './routes/subtitles';

const app = new Hono<{ Bindings: Bindings }>();

app.use('*', cors());

// Root health check probed by DiscoveryService and TV app
app.get('/', (c) => {
  return c.json({
    status: 'online',
    message: 'Movie Streaming Backend API is running.',
  });
});

// Mount routes
app.route('/api/v1/movies', moviesRouter);
app.route('/api/v1/subtitles', subtitlesRouter);

// Diagnostic route to test D1 connectivity and IMDb ratings lookup
app.get('/api/v1/imdb/:id', async (c) => {
  const imdbId = c.req.param('id');
  const result = await c.env.DB.prepare(
    'SELECT imdb_id, rating, votes FROM imdb_ratings WHERE imdb_id = ?'
  )
    .bind(imdbId)
    .first();

  if (!result) {
    return c.json({ error: 'Title not found' }, 404);
  }

  return c.json(result);
});

export default app;
