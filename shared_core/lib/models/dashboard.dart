import 'dashboard_lane.dart';
import 'movie_summary.dart';

class DashboardMeta {
  final String id;
  final String title;

  const DashboardMeta({
    required this.id,
    required this.title,
  });

  factory DashboardMeta.fromJson(Map<String, dynamic> json) => DashboardMeta(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
  };
}

class Dashboard {
  final String id;
  final String title;
  final List<MovieSummary> billboard;
  final List<DashboardLane> lanes;

  const Dashboard({
    required this.id,
    required this.title,
    this.billboard = const [],
    required this.lanes,
  });

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    final rawLanes = json['lanes'] as List? ?? [];
    final rawBillboard = json['billboard'] as List? ?? [];
    return Dashboard(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      billboard: rawBillboard
          .map((item) => MovieSummary.fromJson(item as Map<String, dynamic>))
          .toList(),
      lanes: rawLanes
          .map((lane) => DashboardLane.fromJson(lane as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'billboard': billboard.map((m) => m.toJson()).toList(),
    'lanes': lanes.map((l) => l.toJson()).toList(),
  };
}
