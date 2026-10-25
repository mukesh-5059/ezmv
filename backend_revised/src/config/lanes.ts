import { LaneConfig } from '../types';

export interface DashboardConfig {
  id: string;
  title: string;
  lanes: LaneConfig[];
}

export const TAMIL_LANES: LaneConfig[] = [
  {
    id: 'trending',
    title: 'Trending Now',
  },
  {
    id: 'new_releases',
    title: 'New in Theaters',
  },
  {
    id: 'new_ott',
    title: 'New on OTT',
  },
  {
    id: 'top_rated',
    title: 'All-Time Masterpieces',
  },
  {
    id: 'comedy',
    title: 'Popular Comedy',
  },
  {
    id: 'pan_india',
    title: 'South Indian Blockbusters',
  },
];

export const DASHBOARDS: Record<string, DashboardConfig> = {
  tamil: {
    id: 'tamil',
    title: 'Tamil Cinema',
    lanes: TAMIL_LANES,
  },
};
