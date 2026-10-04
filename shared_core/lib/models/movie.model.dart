class Movie {
  final int tmdbId;
  final String title;
  final String overview;
  final String releaseDate;
  final String posterPath;
  final String backdropPath;
  final double voteAverage;
  final String originalLanguage;
  final String mediaType;
  final List<int> genreIds;

  Movie({
    required this.tmdbId,
    required this.title,
    required this.overview,
    required this.releaseDate,
    required this.posterPath,
    required this.backdropPath,
    required this.voteAverage,
    required this.originalLanguage,
    this.mediaType = 'movie',
    this.genreIds = const [],
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      tmdbId: json['tmdb_id'] ?? 0,
      title: json['title'] ?? json['name'] ?? 'Unknown',
      overview: json['overview'] ?? '',
      releaseDate: json['release_date'] ?? json['first_air_date'] ?? '',
      posterPath: json['poster_path'] ?? '',
      backdropPath: json['backdrop_path'] ?? '',
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      originalLanguage: json['original_language'] ?? 'en',
      mediaType: json['media_type'] ?? 'movie',
      genreIds: json['genre_ids'] != null
          ? List<int>.from(json['genre_ids'])
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tmdb_id': tmdbId,
      'title': title,
      'overview': overview,
      'release_date': releaseDate,
      'poster_path': posterPath,
      'backdrop_path': backdropPath,
      'vote_average': voteAverage,
      'original_language': originalLanguage,
      'media_type': mediaType,
      'genre_ids': genreIds,
    };
  }

  // Get full poster URL
  String get posterUrl => posterPath.isNotEmpty
      ? 'https://image.tmdb.org/t/p/w342$posterPath'
      : 'https://via.placeholder.com/342x513?text=No+Image';

  // Get full backdrop URL
  String get backdropUrl => backdropPath.isNotEmpty
      ? 'https://image.tmdb.org/t/p/w780$backdropPath'
      : '';

  // Get release year
  String get year => releaseDate.isNotEmpty ? releaseDate.split('-')[0] : '';

  bool get isTv => mediaType == 'tv';

  static const Map<int, String> _genreMap = {
    28: 'Action',
    12: 'Adventure',
    16: 'Animation',
    35: 'Comedy',
    80: 'Crime',
    99: 'Documentary',
    18: 'Drama',
    10751: 'Family',
    14: 'Fantasy',
    36: 'History',
    27: 'Horror',
    10402: 'Music',
    9648: 'Mystery',
    10749: 'Romance',
    878: 'Sci-Fi',
    10770: 'TV Movie',
    53: 'Thriller',
    10752: 'War',
    37: 'Western',
  };

  // Convert genre IDs list to string tag representation
  String get genreTags {
    if (genreIds.isEmpty) return '';
    final names = genreIds
        .map((id) => _genreMap[id])
        .where((name) => name != null)
        .cast<String>()
        .toList();
    return names.join(' • ');
  }
}
