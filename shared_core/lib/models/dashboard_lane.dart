import 'movie_summary.dart';

class DashboardLane {
  final String id;
  final String title;
  final List<MovieSummary> items;
  final int page;
  final int totalPages;
  final int totalItems;
  final bool hasMore;
  final int? nextPage;

  const DashboardLane({
    required this.id,
    required this.title,
    required this.items,
    this.page = 1,
    this.totalPages = 1,
    this.totalItems = 0,
    this.hasMore = false,
    this.nextPage,
  });

  factory DashboardLane.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? [];
    return DashboardLane(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      items: rawItems
          .map((item) => MovieSummary.fromJson(item as Map<String, dynamic>))
          .toList(),
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 1,
      totalItems: (json['total_items'] as num?)?.toInt() ?? rawItems.length,
      hasMore: json['has_more'] as bool? ?? false,
      nextPage: (json['next_page'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'items': items.map((i) => i.toJson()).toList(),
    'page': page,
    'total_pages': totalPages,
    'total_items': totalItems,
    'has_more': hasMore,
    'next_page': nextPage,
  };
}
