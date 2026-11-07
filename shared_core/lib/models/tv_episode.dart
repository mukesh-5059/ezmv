class TvEpisode {
  final int episodeNumber;
  final String name;
  final String overview;
  final String? stillPath;
  final String? airDate;
  final int? runtime;
  final bool isReleased;

  const TvEpisode({
    required this.episodeNumber,
    required this.name,
    required this.overview,
    this.stillPath,
    this.airDate,
    this.runtime,
    this.isReleased = true,
  });

  String get stillUrl {
    if (stillPath == null || stillPath!.isEmpty) return '';
    if (stillPath!.startsWith('http')) return stillPath!;
    return 'https://image.tmdb.org/t/p/w500$stillPath';
  }

  String get formattedRuntime {
    if (runtime == null || runtime! <= 0) return '';
    return '${runtime}m';
  }

  factory TvEpisode.fromJson(Map<String, dynamic> json) => TvEpisode(
    episodeNumber: (json['episode_number'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    overview: json['overview'] as String? ?? '',
    stillPath: json['still_path'] as String?,
    airDate: json['air_date'] as String?,
    runtime: (json['runtime'] as num?)?.toInt(),
    isReleased: json['is_released'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'episode_number': episodeNumber,
    'name': name,
    'overview': overview,
    'still_path': stillPath,
    'air_date': airDate,
    'runtime': runtime,
    'is_released': isReleased,
  };
}
