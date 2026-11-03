import { DashboardConfig, DashboardSummary } from '../types/api';

export const DASHBOARDS: Record<string, DashboardConfig> = {
  tamil: {
    id: 'tamil',
    title: 'Tamil Cinema',
    lanes: [
      { id: 'ta_trending', title: 'Trending Now' },
      { id: 'ta_new_releases', title: 'New in Theaters' },
      { id: 'ta_new_ott', title: 'New on OTT' },
      { id: 'ta_top_rated', title: 'All-Time Masterpieces' },
      { id: 'ta_comedy', title: 'Popular Comedy' },
      { id: 'ta_pan_india', title: 'South Indian Blockbusters' },
    ],
  },
  english: {
    id: 'english',
    title: 'Hollywood & English',
    lanes: [
      { id: 'en_trending', title: 'Trending Now' },
      { id: 'en_new_releases', title: 'New in Theaters' },
      { id: 'en_top_rated', title: 'All-Time Masterpieces' },
      { id: 'en_animated', title: 'Trending Animated Movies' },
      { id: 'en_series', title: 'Binge-Worthy Series' },
    ],
  },
  anime: {
    id: 'anime',
    title: 'Anime',
    lanes: [
      { id: 'anime_trending', title: 'Trending Anime' },
      { id: 'anime_top_rated', title: 'Top Rated Series' },
      { id: 'anime_movies', title: 'Masterpiece Movies' },
      { id: 'anime_comedy', title: 'Comedy Anime' },
    ],
  },
};

export const DASHBOARDS_LIST: DashboardSummary[] = Object.values(DASHBOARDS).map((d) => ({
  id: d.id,
  title: d.title,
}));
