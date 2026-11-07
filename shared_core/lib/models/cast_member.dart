class CastMember {
  final int tmdbId;
  final String name;
  final String character;
  final String? profilePath;
  final int? order;

  const CastMember({
    required this.tmdbId,
    required this.name,
    required this.character,
    this.profilePath,
    this.order,
  });

  int get id => tmdbId;

  String get profileUrl {
    if (profilePath == null || profilePath!.isEmpty) return '';
    if (profilePath!.startsWith('http')) return profilePath!;
    return 'https://image.tmdb.org/t/p/w185$profilePath';
  }

  factory CastMember.fromJson(Map<String, dynamic> json) => CastMember(
    tmdbId: (json['tmdb_id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    character: json['character'] as String? ?? '',
    profilePath: json['profile_path'] as String?,
    order: (json['order'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'tmdb_id': tmdbId,
    'name': name,
    'character': character,
    'profile_path': profilePath,
    'order': order,
  };
}
