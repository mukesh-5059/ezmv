class ContinueWatchingEntry {
  final String imdbId;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String mediaType;
  final int? season;
  final int? episode;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  const ContinueWatchingEntry({
    required this.imdbId,
    required this.title,
    this.posterPath,
    this.backdropPath,
    required this.mediaType,
    this.season,
    this.episode,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  bool get isTv => mediaType == 'tv';
  bool get isMovie => mediaType == 'movie';

  double get progress => durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  bool get isCompleted => progress >= 0.92;

  String get posterUrl {
    if (posterPath == null || posterPath!.isEmpty) return '';
    if (posterPath!.startsWith('http')) return posterPath!;
    return 'https://image.tmdb.org/t/p/w500$posterPath';
  }

  String get backdropUrl {
    if (backdropPath == null || backdropPath!.isEmpty) return '';
    if (backdropPath!.startsWith('http')) return backdropPath!;
    return 'https://image.tmdb.org/t/p/w1280$backdropPath';
  }

  factory ContinueWatchingEntry.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    final rawDate = json['updated_at'];
    if (rawDate is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
    } else if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return ContinueWatchingEntry(
      imdbId: json['imdb_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      mediaType: json['media_type'] as String? ?? 'movie',
      season: (json['season'] as num?)?.toInt(),
      episode: (json['episode'] as num?)?.toInt(),
      positionMs: (json['position_ms'] as num?)?.toInt() ?? 0,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      updatedAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() => {
    'imdb_id': imdbId,
    'title': title,
    'poster_path': posterPath,
    'backdrop_path': backdropPath,
    'media_type': mediaType,
    'season': season,
    'episode': episode,
    'position_ms': positionMs,
    'duration_ms': durationMs,
    'updated_at': updatedAt.toIso8601String(),
  };
}
