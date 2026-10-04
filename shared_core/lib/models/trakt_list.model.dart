class TraktList {
  final String id;
  final String name;
  final String description;
  final int itemCount;
  final int likes;
  final String userName;
  final String slug;

  const TraktList({
    required this.id,
    required this.name,
    this.description = '',
    this.itemCount = 0,
    this.likes = 0,
    this.userName = '',
    this.slug = '',
  });

  factory TraktList.fromJson(Map<String, dynamic> json) {
    return TraktList(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      userName: json['user_name'] ?? '',
      slug: json['slug'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'item_count': itemCount,
      'likes': likes,
      'user_name': userName,
      'slug': slug,
    };
  }
}
