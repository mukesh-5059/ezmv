import 'movie_summary.dart';

class ActorSummary {
  final int tmdbId;
  final String name;
  final String biography;
  final String? profilePath;

  const ActorSummary({
    required this.tmdbId,
    required this.name,
    required this.biography,
    this.profilePath,
  });

  String get profileUrl {
    if (profilePath == null || profilePath!.isEmpty) return '';
    if (profilePath!.startsWith('http')) return profilePath!;
    return 'https://image.tmdb.org/t/p/w500$profilePath';
  }

  factory ActorSummary.fromJson(Map<String, dynamic> json) => ActorSummary(
    tmdbId: (json['tmdb_id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    biography: json['biography'] as String? ?? '',
    profilePath: json['profile_path'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'tmdb_id': tmdbId,
    'name': name,
    'biography': biography,
    'profile_path': profilePath,
  };
}

class ActorProfile {
  final int tmdbId;
  final String name;
  final String biography;
  final String? profilePath;
  final List<MovieSummary> popular;
  final List<MovieSummary> recent;

  const ActorProfile({
    required this.tmdbId,
    required this.name,
    required this.biography,
    this.profilePath,
    this.popular = const [],
    this.recent = const [],
  });

  String get profileUrl {
    if (profilePath == null || profilePath!.isEmpty) return '';
    if (profilePath!.startsWith('http')) return profilePath!;
    return 'https://image.tmdb.org/t/p/w500$profilePath';
  }

  factory ActorProfile.fromJson(Map<String, dynamic> json) {
    final rawPopular = json['popular'] as List? ?? [];
    final rawRecent = json['recent'] as List? ?? [];

    return ActorProfile(
      tmdbId: (json['tmdb_id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      biography: json['biography'] as String? ?? '',
      profilePath: json['profile_path'] as String?,
      popular: rawPopular
          .map((item) => MovieSummary.fromJson(item as Map<String, dynamic>))
          .toList(),
      recent: rawRecent
          .map((item) => MovieSummary.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'tmdb_id': tmdbId,
    'name': name,
    'biography': biography,
    'profile_path': profilePath,
    'popular': popular.map((m) => m.toJson()).toList(),
    'recent': recent.map((m) => m.toJson()).toList(),
  };
}

typedef ActorFilmography = ActorProfile;
