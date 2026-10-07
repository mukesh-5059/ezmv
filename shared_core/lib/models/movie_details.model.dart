import 'tv_season.model.dart';
import 'movie.model.dart';

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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'character': character,
      'profile_path': profilePath,
      'order': order,
    };
  }
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
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

  factory MovieDetails.fromMovie(Movie movie) {
    return MovieDetails(
      tmdbId: movie.tmdbId,
      imdbId: movie.imdbId,
      title: movie.title,
      overview: movie.overview,
      releaseDate: movie.releaseDate,
      posterPath: movie.posterPath,
      backdropPath: movie.backdropPath,
      voteAverage: movie.voteAverage,
      voteCount: 0,
      mediaType: movie.mediaType,
    );
  }

  factory MovieDetails.fromJson(Map<String, dynamic> json) {
    final rawGenres = json['genres'] as List? ?? [];
    final rawCast = json['cast'] as List? ??
        (json['credits'] != null && json['credits']['cast'] is List
            ? json['credits']['cast'] as List
            : []);
    final rawSeasons = json['seasons'] as List? ?? [];

    String? imdb;
    if (json['imdb_id'] != null && json['imdb_id'].toString().isNotEmpty) {
      imdb = json['imdb_id'].toString();
    } else if (json['external_ids'] != null && json['external_ids']['imdb_id'] != null) {
      imdb = json['external_ids']['imdb_id'].toString();
    }

    int? computedRuntime = json['runtime'];
    if (computedRuntime == null && json['episode_run_time'] is List && (json['episode_run_time'] as List).isNotEmpty) {
      computedRuntime = json['episode_run_time'][0];
    }

    final detectedMediaType = json['media_type'] ??
        (json['seasons'] != null || json['number_of_seasons'] != null || json['name'] != null ? 'tv' : 'movie');

    return MovieDetails(
      tmdbId: json['tmdb_id'] ?? json['id'] ?? 0,
      imdbId: imdb,
      title: json['title'] ?? json['name'] ?? '',
      overview: json['overview'] ?? '',
      releaseDate: json['release_date'] ?? json['first_air_date'] ?? '',
      posterPath: json['poster_path'] ?? '',
      backdropPath: json['backdrop_path'] ?? '',
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['vote_count'] ?? 0,
      runtime: computedRuntime,
      tagline: json['tagline'],
      mediaType: detectedMediaType,
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

  Map<String, dynamic> toJson() {
    return {
      'tmdb_id': tmdbId,
      'imdb_id': imdbId,
      'title': title,
      'overview': overview,
      'release_date': releaseDate,
      'poster_path': posterPath,
      'backdrop_path': backdropPath,
      'vote_average': voteAverage,
      'vote_count': voteCount,
      'runtime': runtime,
      'tagline': tagline,
      'media_type': mediaType,
      'number_of_seasons': numberOfSeasons,
      'number_of_episodes': numberOfEpisodes,
      'genres': genres.map((g) => g.toJson()).toList(),
      'cast': cast.map((c) => c.toJson()).toList(),
      'seasons': seasons.map((s) => s.toJson()).toList(),
      'external_ids': externalIds,
    };
  }
}
