import 'cast_member.dart';
import 'genre.dart';
import 'movie_summary.dart';

class SeasonSummary {
  final int seasonNumber;
  final String name;
  final int episodeCount;

  const SeasonSummary({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
  });

  factory SeasonSummary.fromJson(Map<String, dynamic> json) => SeasonSummary(
    seasonNumber: (json['season_number'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'season_number': seasonNumber,
    'name': name,
    'episode_count': episodeCount,
  };
}

class MovieDetails extends MovieSummary {
  final int? runtime;
  final List<CastMember> cast;
  final List<SeasonSummary> seasons;
  final String? status;
  final bool isOngoing;
  final String? originalLanguage;

  const MovieDetails({
    required super.imdbId,
    super.tmdbId,
    required super.title,
    required super.overview,
    required super.releaseDate,
    required super.posterPath,
    required super.backdropPath,
    required super.ratingScore,
    required super.voteCount,
    required super.mediaType,
    required super.genres,
    this.runtime,
    this.cast = const [],
    this.seasons = const [],
    this.status,
    this.isOngoing = false,
    this.originalLanguage,
  });

  String get genreNamesString => genres.map((g) => g.name).join(', ');

  String get formattedRuntime {
    if (runtime == null || runtime! <= 0) return '';
    final h = runtime! ~/ 60;
    final m = runtime! % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  factory MovieDetails.fromJson(Map<String, dynamic> json) {
    final rawGenres = json['genres'] as List? ?? [];
    final rawCast = json['cast'] as List? ?? [];
    final rawSeasons = json['seasons'] as List? ?? [];

    return MovieDetails(
      imdbId: json['imdb_id'] as String? ?? '',
      tmdbId: (json['tmdb_id'] as num?)?.toInt(),
      title: json['title'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      releaseDate: json['release_date'] as String? ?? '',
      posterPath: json['poster_path'] as String? ?? '',
      backdropPath: json['backdrop_path'] as String? ?? '',
      ratingScore: (json['rating_score'] as num?)?.toDouble() ?? 0.0,
      voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
      mediaType: json['media_type'] as String? ?? 'movie',
      genres: rawGenres
          .map((g) => Genre.fromJson(g as Map<String, dynamic>))
          .toList(),
      runtime: (json['runtime'] as num?)?.toInt(),
      cast: rawCast
          .map((c) => CastMember.fromJson(c as Map<String, dynamic>))
          .toList(),
      seasons: rawSeasons
          .map((s) => SeasonSummary.fromJson(s as Map<String, dynamic>))
          .toList(),
      status: json['status'] as String?,
      isOngoing: json['is_ongoing'] as bool? ?? false,
      originalLanguage: json['original_language'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map.addAll({
      'runtime': runtime,
      'cast': cast.map((c) => c.toJson()).toList(),
      'seasons': seasons.map((s) => s.toJson()).toList(),
      'status': status,
      'is_ongoing': isOngoing,
      'original_language': originalLanguage,
    });
    return map;
  }
}
