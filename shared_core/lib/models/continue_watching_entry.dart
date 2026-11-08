import 'genre.dart';
import 'movie_summary.dart';

class ContinueWatchingEntry {
  final String imdbId;
  final int? tmdbId;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String mediaType;
  final int? season;
  final int? episode;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;
  final String? overview;
  final String? releaseDate;
  final double? ratingScore;
  final int? voteCount;
  final List<String>? genres;
  final String? originalLanguage;

  const ContinueWatchingEntry({
    required this.imdbId,
    this.tmdbId,
    required this.title,
    this.posterPath,
    this.backdropPath,
    required this.mediaType,
    this.season,
    this.episode,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    this.overview,
    this.releaseDate,
    this.ratingScore,
    this.voteCount,
    this.genres,
    this.originalLanguage,
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

  MovieSummary toMovieSummary() {
    return MovieSummary(
      imdbId: imdbId,
      tmdbId: tmdbId,
      title: title,
      overview: overview ?? '',
      releaseDate: releaseDate ?? '',
      posterPath: posterPath ?? '',
      backdropPath: backdropPath ?? '',
      ratingScore: ratingScore ?? 0.0,
      voteCount: voteCount ?? 0,
      mediaType: mediaType,
      genres: genres?.map((g) => Genre(slug: g.toLowerCase().replaceAll(' ', '-'), name: g)).toList() ?? <Genre>[],
      originalLanguage: originalLanguage,
    );
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

    final rawGenres = json['genres'];
    List<String>? parsedGenres;
    if (rawGenres is List) {
      parsedGenres = rawGenres.map((e) => e.toString()).toList();
    }

    return ContinueWatchingEntry(
      imdbId: json['imdb_id'] as String? ?? '',
      tmdbId: (json['tmdb_id'] as num?)?.toInt(),
      title: json['title'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      mediaType: json['media_type'] as String? ?? 'movie',
      season: (json['season'] as num?)?.toInt(),
      episode: (json['episode'] as num?)?.toInt(),
      positionMs: (json['position_ms'] as num?)?.toInt() ?? 0,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      updatedAt: parsedDate,
      overview: json['overview'] as String?,
      releaseDate: json['release_date'] as String?,
      ratingScore: (json['rating_score'] as num?)?.toDouble(),
      voteCount: (json['vote_count'] as num?)?.toInt(),
      genres: parsedGenres,
      originalLanguage: json['original_language'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'imdb_id': imdbId,
    'tmdb_id': tmdbId,
    'title': title,
    'poster_path': posterPath,
    'backdrop_path': backdropPath,
    'media_type': mediaType,
    'season': season,
    'episode': episode,
    'position_ms': positionMs,
    'duration_ms': durationMs,
    'updated_at': updatedAt.toIso8601String(),
    if (overview != null) 'overview': overview,
    if (releaseDate != null) 'release_date': releaseDate,
    if (ratingScore != null) 'rating_score': ratingScore,
    if (voteCount != null) 'vote_count': voteCount,
    if (genres != null) 'genres': genres,
    if (originalLanguage != null) 'original_language': originalLanguage,
  };
}
