import { Genre } from '../types/api';

// Curated core entertainment genres for frontend filter chips and display
export const GENRES: Genre[] = [
  { slug: 'action', name: 'Action' },
  { slug: 'adventure', name: 'Adventure' },
  { slug: 'animation', name: 'Animation' },
  { slug: 'anime', name: 'Anime' },
  { slug: 'biography', name: 'Biography' },
  { slug: 'comedy', name: 'Comedy' },
  { slug: 'crime', name: 'Crime' },
  { slug: 'documentary', name: 'Documentary' },
  { slug: 'drama', name: 'Drama' },
  { slug: 'family', name: 'Family' },
  { slug: 'fantasy', name: 'Fantasy' },
  { slug: 'history', name: 'History' },
  { slug: 'horror', name: 'Horror' },
  { slug: 'music', name: 'Music' },
  { slug: 'mystery', name: 'Mystery' },
  { slug: 'romance', name: 'Romance' },
  { slug: 'sci-fi', name: 'Sci-Fi' },
  { slug: 'sport', name: 'Sports' },
  { slug: 'thriller', name: 'Thriller' },
  { slug: 'war', name: 'War' },
];

// Unified map resolving any raw provider name, alias, or compound string into a list of canonical Genres
export const ANYTHING_TO_GENRES = new Map<string, Genre[]>();

// 1. Populate canonical genres by slug and display name
for (const g of GENRES) {
  ANYTHING_TO_GENRES.set(g.slug.toLowerCase(), [g]);
  ANYTHING_TO_GENRES.set(g.name.toLowerCase(), [g]);
}

// 2. Map provider aliases (MDBList, TMDb, Trakt, IMDb)
ANYTHING_TO_GENRES.set('sci fi', [{ slug: 'sci-fi', name: 'Sci-Fi' }]);
ANYTHING_TO_GENRES.set('science fiction', [{ slug: 'sci-fi', name: 'Sci-Fi' }]);
ANYTHING_TO_GENRES.set('science-fiction', [{ slug: 'sci-fi', name: 'Sci-Fi' }]);
ANYTHING_TO_GENRES.set('sporting event', [{ slug: 'sport', name: 'Sports' }]);
ANYTHING_TO_GENRES.set('sporting-event', [{ slug: 'sport', name: 'Sports' }]);
ANYTHING_TO_GENRES.set('musical', [{ slug: 'music', name: 'Music' }]);
ANYTHING_TO_GENRES.set('suspense', [{ slug: 'thriller', name: 'Thriller' }]);
ANYTHING_TO_GENRES.set('western', [{ slug: 'western', name: 'Western' }]);

// 3. Map compound TV genres into multiple canonical categories
ANYTHING_TO_GENRES.set('action & adventure', [{ slug: 'action', name: 'Action' }, { slug: 'adventure', name: 'Adventure' }]);
ANYTHING_TO_GENRES.set('action-&-adventure', [{ slug: 'action', name: 'Action' }, { slug: 'adventure', name: 'Adventure' }]);
ANYTHING_TO_GENRES.set('sci-fi & fantasy', [{ slug: 'sci-fi', name: 'Sci-Fi' }, { slug: 'fantasy', name: 'Fantasy' }]);
ANYTHING_TO_GENRES.set('sci-fi-&-fantasy', [{ slug: 'sci-fi', name: 'Sci-Fi' }, { slug: 'fantasy', name: 'Fantasy' }]);
ANYTHING_TO_GENRES.set('war & politics', [{ slug: 'war', name: 'War' }]);
ANYTHING_TO_GENRES.set('war-&-politics', [{ slug: 'war', name: 'War' }]);

export function resolveGenres(raw: string): Genre[] {
  const trimmed = raw.trim();
  if (!trimmed) return [];
  const key = trimmed.toLowerCase();

  const matched = ANYTHING_TO_GENRES.get(key);
  if (matched) return matched;

  const slug = key.replace(/\s+/g, '-');
  const name = trimmed.charAt(0).toUpperCase() + trimmed.slice(1);
  return [{ slug, name }];
}
