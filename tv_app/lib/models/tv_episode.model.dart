class TvEpisode {
  final int id;
  final int episodeNumber;
  final int seasonNumber;
  final String name;
  final String overview;
  final String? stillPath;
  final String? airDate;
  final double voteAverage;
  final int? runtime;

  TvEpisode({
    required this.id,
    required this.episodeNumber,
    this.seasonNumber = 1,
    this.name = '',
    this.overview = '',
    this.stillPath,
    this.airDate,
    this.voteAverage = 0.0,
    this.runtime,
  });

  factory TvEpisode.fromJson(Map<String, dynamic> json) {
    return TvEpisode(
      id: json['id'] ?? 0,
      episodeNumber: json['episode_number'] ?? 0,
      seasonNumber: json['season_number'] ?? 1,
      name: json['name'] ?? '',
      overview: json['overview'] ?? '',
      stillPath: json['still_path'],
      airDate: json['air_date'],
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      runtime: json['runtime'],
    );
  }

  String get stillUrl => (stillPath != null && stillPath!.isNotEmpty)
      ? 'https://image.tmdb.org/t/p/w300$stillPath'
      : '';

  String get formattedRuntime {
    if (runtime == null || runtime! <= 0) return '';
    return '${runtime}m';
  }
}
