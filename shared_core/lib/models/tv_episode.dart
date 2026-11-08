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

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String get stillUrl {
    if (stillPath == null || stillPath!.isEmpty) return '';
    if (stillPath!.startsWith('http')) return stillPath!;
    return 'https://image.tmdb.org/t/p/w500$stillPath';
  }

  String get formattedRuntime {
    if (runtime == null || runtime! <= 0) return '';
    return '${runtime}m';
  }

  bool get isUpcoming {
    if (!isReleased) return true;
    if (airDate == null || airDate!.trim().isEmpty) return false;
    try {
      final date = DateTime.tryParse(airDate!);
      if (date != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        return date.isAfter(today);
      }
    } catch (_) {}
    return false;
  }

  String get formattedAirDate {
    if (airDate == null || airDate!.trim().isEmpty) return '';
    try {
      final d = DateTime.tryParse(airDate!);
      if (d != null && d.month >= 1 && d.month <= 12) {
        return '${_months[d.month - 1]} ${d.day}, ${d.year}';
      }
    } catch (_) {}
    return airDate!;
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
