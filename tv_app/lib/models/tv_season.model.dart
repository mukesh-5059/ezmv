import 'tv_episode.model.dart';

class TvSeason {
  final int id;
  final int seasonNumber;
  final String name;
  final String overview;
  final String? posterPath;
  final int episodeCount;
  final String? airDate;
  final List<TvEpisode> episodes;

  TvSeason({
    required this.id,
    required this.seasonNumber,
    this.name = '',
    this.overview = '',
    this.posterPath,
    this.episodeCount = 0,
    this.airDate,
    this.episodes = const [],
  });

  factory TvSeason.fromJson(Map<String, dynamic> json) {
    final rawEpisodes = json['episodes'] as List? ?? [];
    return TvSeason(
      id: json['id'] ?? 0,
      seasonNumber: json['season_number'] ?? 0,
      name: json['name'] ?? '',
      overview: json['overview'] ?? '',
      posterPath: json['poster_path'],
      episodeCount: json['episode_count'] ?? rawEpisodes.length,
      airDate: json['air_date'],
      episodes: rawEpisodes
          .map((e) => TvEpisode.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  String get posterUrl => (posterPath != null && posterPath!.isNotEmpty)
      ? 'https://image.tmdb.org/t/p/w342$posterPath'
      : '';
}
