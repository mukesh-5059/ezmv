class TraktListSummary {
  final int id;
  final String name;
  final int itemCount;
  final int likes;

  const TraktListSummary({
    required this.id,
    required this.name,
    this.itemCount = 0,
    this.likes = 0,
  });

  factory TraktListSummary.fromJson(Map<String, dynamic> json) => TraktListSummary(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
    likes: (json['likes'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'item_count': itemCount,
    'likes': likes,
  };
}

typedef TraktList = TraktListSummary;
