import 'tv_episode.dart';

class TvSeason {
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final List<TvEpisode> episodes;

  const TvSeason({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.episodes = const [],
  });

  factory TvSeason.fromJson(Map<String, dynamic> json) {
    final rawEpisodes = json['episodes'] as List? ?? [];
    return TvSeason(
      seasonNumber: (json['season_number'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? rawEpisodes.length,
      episodes: rawEpisodes
          .map((e) => TvEpisode.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'season_number': seasonNumber,
    'name': name,
    'episode_count': episodeCount,
    'episodes': episodes.map((e) => e.toJson()).toList(),
  };
}
