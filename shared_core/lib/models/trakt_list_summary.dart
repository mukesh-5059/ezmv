class TraktListSummary {
  final int id;
  final String name;
  final String description;
  final String userName;
  final String slug;
  final int itemCount;
  final int likes;
  final String? sortBy;
  final String? sortHow;

  const TraktListSummary({
    required this.id,
    required this.name,
    this.description = '',
    this.userName = '',
    this.slug = '',
    this.itemCount = 0,
    this.likes = 0,
    this.sortBy,
    this.sortHow,
  });

  factory TraktListSummary.fromJson(Map<String, dynamic> json) {
    final listObj = (json['list'] is Map<String, dynamic>)
        ? json['list'] as Map<String, dynamic>
        : json;

    final userObj = listObj['user'];
    final userName = userObj is Map<String, dynamic>
        ? (userObj['username'] as String? ?? '')
        : (listObj['user_name'] as String? ??
            listObj['username'] as String? ??
            json['user_name'] as String? ??
            '');

    final idsObj = listObj['ids'];
    final slug = idsObj is Map<String, dynamic>
        ? (idsObj['slug'] as String? ?? '')
        : (listObj['slug'] as String? ?? json['slug'] as String? ?? '');

    final id = (idsObj is Map<String, dynamic> ? idsObj['trakt'] : null) as int? ??
        (listObj['id'] as num?)?.toInt() ??
        (json['id'] as num?)?.toInt() ??
        0;

    final likes = (json['like_count'] as num?)?.toInt() ??
        (json['likes'] as num?)?.toInt() ??
        (listObj['likes'] as num?)?.toInt() ??
        (listObj['like_count'] as num?)?.toInt() ??
        0;

    return TraktListSummary(
      id: id,
      name: listObj['name'] as String? ?? json['name'] as String? ?? '',
      description: listObj['description'] as String? ?? json['description'] as String? ?? '',
      userName: userName,
      slug: slug,
      itemCount: (listObj['item_count'] as num?)?.toInt() ??
          (listObj['itemCount'] as num?)?.toInt() ??
          (json['item_count'] as num?)?.toInt() ??
          (json['itemCount'] as num?)?.toInt() ??
          0,
      likes: likes,
      sortBy: listObj['sort_by'] as String? ??
          listObj['sortBy'] as String? ??
          json['sort_by'] as String? ??
          json['sortBy'] as String?,
      sortHow: listObj['sort_how'] as String? ??
          listObj['sortHow'] as String? ??
          listObj['sort_order'] as String? ??
          json['sort_how'] as String? ??
          json['sortHow'] as String? ??
          json['sort_order'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'user_name': userName,
    'slug': slug,
    'item_count': itemCount,
    'likes': likes,
    if (sortBy != null) 'sort_by': sortBy,
    if (sortHow != null) 'sort_how': sortHow,
  };

  TraktListSummary copyWith({
    int? id,
    String? name,
    String? description,
    String? userName,
    String? slug,
    int? itemCount,
    int? likes,
    String? sortBy,
    String? sortHow,
  }) {
    return TraktListSummary(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      userName: userName ?? this.userName,
      slug: slug ?? this.slug,
      itemCount: itemCount ?? this.itemCount,
      likes: likes ?? this.likes,
      sortBy: sortBy ?? this.sortBy,
      sortHow: sortHow ?? this.sortHow,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraktListSummary &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

typedef TraktList = TraktListSummary;
