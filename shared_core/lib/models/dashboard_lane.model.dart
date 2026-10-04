import 'movie.model.dart';

class DashboardLane {
  final String id;
  final String title;
  List<Movie> items;
  bool hasMore;
  int? nextPage;

  DashboardLane({
    required this.id,
    required this.title,
    required this.items,
    this.hasMore = false,
    this.nextPage,
  });

  factory DashboardLane.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? [];
    return DashboardLane(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      items: rawItems.map((e) => Movie.fromJson(e)).toList(),
      hasMore: json['has_more'] ?? false,
      nextPage: json['next_page'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'items': items.map((e) => e.toJson()).toList(),
      'has_more': hasMore,
      'next_page': nextPage,
    };
  }
}
