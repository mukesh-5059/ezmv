import 'genre.dart';

class MovieSummary {
  final String imdbId;
  final int? tmdbId;
  final String title;
  final String overview;
  final String releaseDate;
  final String posterPath;
  final String backdropPath;
  final double ratingScore;
  final int voteCount;
  final String mediaType;
  final List<Genre> genres;

  const MovieSummary({
    required this.imdbId,
    this.tmdbId,
    required this.title,
    required this.overview,
    required this.releaseDate,
    required this.posterPath,
    required this.backdropPath,
    required this.ratingScore,
    required this.voteCount,
    required this.mediaType,
    required this.genres,
  });

  bool get isTv => mediaType == 'tv';
  bool get isMovie => mediaType == 'movie';

  String get year => releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';

  String get posterUrl {
    if (posterPath.isEmpty) return '';
    if (posterPath.startsWith('http')) return posterPath;
    return 'https://image.tmdb.org/t/p/w500$posterPath';
  }

  String get backdropUrl {
    if (backdropPath.isEmpty) return '';
    if (backdropPath.startsWith('http')) return backdropPath;
    return 'https://image.tmdb.org/t/p/w1280$backdropPath';
  }

  String get formattedRating => ratingScore > 0 ? ratingScore.toStringAsFixed(1) : '';

  String get formattedVoteCount {
    if (voteCount >= 1000000) return '${(voteCount / 1000000).toStringAsFixed(1)}M';
    if (voteCount >= 1000) return '${(voteCount / 1000).toStringAsFixed(1)}K';
    return voteCount > 0 ? '$voteCount' : '';
  }

  double get voteAverage => ratingScore;
  List<String> get genreTags => genres.map((g) => g.name).toList();
  String? get originalLanguage => null;

  factory MovieSummary.fromJson(Map<String, dynamic> json) {
    final rawGenres = json['genres'] as List? ?? [];
    return MovieSummary(
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
    );
  }

  Map<String, dynamic> toJson() => {
    'imdb_id': imdbId,
    'tmdb_id': tmdbId,
    'title': title,
    'overview': overview,
    'release_date': releaseDate,
    'poster_path': posterPath,
    'backdrop_path': backdropPath,
    'rating_score': ratingScore,
    'vote_count': voteCount,
    'media_type': mediaType,
    'genres': genres.map((g) => g.toJson()).toList(),
  };
}

typedef Movie = MovieSummary;
