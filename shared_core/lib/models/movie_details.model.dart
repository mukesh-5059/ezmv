import 'tv_season.model.dart';

class CastMember {
  final int id;
  final String name;
  final String character;
  final String? profilePath;
  final int order;

  CastMember({
    required this.id,
    required this.name,
    required this.character,
    this.profilePath,
    this.order = 0,
  });

  factory CastMember.fromJson(Map<String, dynamic> json) {
    return CastMember(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      character: json['character'] ?? '',
      profilePath: json['profile_path'],
      order: json['order'] ?? 0,
    );
  }

  String get profileUrl => (profilePath != null && profilePath!.isNotEmpty)
      ? 'https://image.tmdb.org/t/p/w185$profilePath'
      : '';
}

class GenreItem {
  final int id;
  final String name;

  GenreItem({required this.id, required this.name});

  factory GenreItem.fromJson(Map<String, dynamic> json) {
    return GenreItem(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
    );
  }
}

class MovieDetails {
  final int tmdbId;
  final String? imdbId;
  final String title;
  final String overview;
  final String releaseDate;
  final String posterPath;
  final String backdropPath;
  final double voteAverage;
  final int voteCount;
  final int? runtime;
  final String? tagline;
  final String mediaType;
  final int numberOfSeasons;
  final int numberOfEpisodes;
  final List<GenreItem> genres;
  final List<CastMember> cast;
  final List<TvSeason> seasons;
  final Map<String, dynamic> externalIds;

  MovieDetails({
    required this.tmdbId,
    this.imdbId,
    required this.title,
    required this.overview,
    required this.releaseDate,
    required this.posterPath,
    required this.backdropPath,
    required this.voteAverage,
    required this.voteCount,
    this.runtime,
    this.tagline,
    this.mediaType = 'movie',
    this.numberOfSeasons = 0,
    this.numberOfEpisodes = 0,
    this.genres = const [],
    this.cast = const [],
    this.seasons = const [],
    this.externalIds = const {},
  });

  bool get isTv => mediaType == 'tv';

  factory MovieDetails.fromJson(Map<String, dynamic> json) {
    final rawGenres = json['genres'] as List? ?? [];
    final rawCast = json['cast'] as List? ?? [];
    final rawSeasons = json['seasons'] as List? ?? [];
    return MovieDetails(
      tmdbId: json['tmdb_id'] ?? 0,
      imdbId: json['imdb_id'],
      title: json['title'] ?? '',
      overview: json['overview'] ?? '',
      releaseDate: json['release_date'] ?? '',
      posterPath: json['poster_path'] ?? '',
      backdropPath: json['backdrop_path'] ?? '',
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['vote_count'] ?? 0,
      runtime: json['runtime'],
      tagline: json['tagline'],
      mediaType: json['media_type'] ?? 'movie',
      numberOfSeasons: json['number_of_seasons'] ?? rawSeasons.length,
      numberOfEpisodes: json['number_of_episodes'] ?? 0,
      genres: rawGenres.map((g) => GenreItem.fromJson(Map<String, dynamic>.from(g))).toList(),
      cast: rawCast.map((c) => CastMember.fromJson(Map<String, dynamic>.from(c))).toList(),
      seasons: rawSeasons.map((s) => TvSeason.fromJson(Map<String, dynamic>.from(s))).toList(),
      externalIds: json['external_ids'] != null
          ? Map<String, dynamic>.from(json['external_ids'])
          : {},
    );
  }

  String get posterUrl => posterPath.isNotEmpty
      ? 'https://image.tmdb.org/t/p/w342$posterPath'
      : 'https://via.placeholder.com/342x513?text=No+Image';

  String get backdropUrl => backdropPath.isNotEmpty
      ? 'https://image.tmdb.org/t/p/w780$backdropPath'
      : '';

  String get formattedRuntime {
    if (runtime == null || runtime! <= 0) return '';
    final hours = runtime! ~/ 60;
    final minutes = runtime! % 60;
    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${minutes}m';
    }
  }

  String get genreNamesString {
    if (genres.isEmpty) return '';
    return genres.map((g) => g.name).join(' • ');
  }

  String get year => releaseDate.isNotEmpty ? releaseDate.split('-')[0] : '';
  String get releaseYear => year;
}
