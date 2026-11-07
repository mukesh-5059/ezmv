class Genre {
  final String slug;
  final String name;

  const Genre({
    required this.slug,
    required this.name,
  });

  factory Genre.fromJson(Map<String, dynamic> json) => Genre(
    slug: json['slug'] as String? ?? '',
    name: json['name'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'name': name,
  };
}
