import 'movie.model.dart';

class Actor {
  final int id;
  final String name;
  final String? profilePath;
  final String knownForDepartment;

  Actor({
    required this.id,
    required this.name,
    this.profilePath,
    this.knownForDepartment = 'Acting',
  });

  factory Actor.fromJson(Map<String, dynamic> json) {
    return Actor(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      profilePath: json['profile_path'],
      knownForDepartment: json['known_for_department'] ?? 'Acting',
    );
  }

  String get profileUrl => (profilePath != null && profilePath!.isNotEmpty)
      ? 'https://image.tmdb.org/t/p/w185$profilePath'
      : '';
}

class ActorFilmography {
  final int id;
  final String name;
  final String biography;
  final String? profilePath;
  final String knownForDepartment;
  final String? birthday;
  final String? placeOfBirth;
  final List<Movie> popular;
  final List<Movie> recent;

  ActorFilmography({
    required this.id,
    required this.name,
    this.biography = '',
    this.profilePath,
    this.knownForDepartment = 'Acting',
    this.birthday,
    this.placeOfBirth,
    this.popular = const [],
    this.recent = const [],
  });

  factory ActorFilmography.fromJson(Map<String, dynamic> json) {
    final rawPopular = json['popular'] as List? ?? [];
    final rawRecent = json['recent'] as List? ?? [];
    return ActorFilmography(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      biography: json['biography'] ?? '',
      profilePath: json['profile_path'],
      knownForDepartment: json['known_for_department'] ?? 'Acting',
      birthday: json['birthday'],
      placeOfBirth: json['place_of_birth'],
      popular: rawPopular.map((m) => Movie.fromJson(m)).toList(),
      recent: rawRecent.map((m) => Movie.fromJson(m)).toList(),
    );
  }

  String get profileUrl => (profilePath != null && profilePath!.isNotEmpty)
      ? 'https://image.tmdb.org/t/p/w185$profilePath'
      : '';
}
