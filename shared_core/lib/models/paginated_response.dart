class PaginatedResponse<T> {
  final List<T> items;
  final int page;
  final int totalPages;
  final int totalItems;
  final bool hasMore;
  final int? nextPage;

  const PaginatedResponse({
    required this.items,
    this.page = 1,
    this.totalPages = 1,
    this.totalItems = 0,
    this.hasMore = false,
    this.nextPage,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) fromJsonT,
  ) {
    final rawItems = json['items'] as List? ?? [];
    return PaginatedResponse<T>(
      items: rawItems.map(fromJsonT).toList(),
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 1,
      totalItems: (json['total_items'] as num?)?.toInt() ?? rawItems.length,
      hasMore: json['has_more'] as bool? ?? false,
      nextPage: (json['next_page'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson(dynamic Function(T) toJsonT) => {
    'items': items.map(toJsonT).toList(),
    'page': page,
    'total_pages': totalPages,
    'total_items': totalItems,
    'has_more': hasMore,
    'next_page': nextPage,
  };
}
