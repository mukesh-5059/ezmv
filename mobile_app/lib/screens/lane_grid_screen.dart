import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/movie_grid.dart';

class LaneGridScreen extends StatelessWidget {
  final String title;
  final String laneId;
  final String language;
  final List<Movie> initialMovies;

  const LaneGridScreen({
    super.key,
    required this.title,
    required this.laneId,
    this.language = 'en',
    this.initialMovies = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isLatest = laneId.toLowerCase().contains('latest') ||
        title.toLowerCase().contains('latest') ||
        laneId.toLowerCase().contains('new');

    return Scaffold(
      backgroundColor: MobileTheme.background,
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: MovieGrid(
        initialMovies: initialMovies,
        endlessYearPaging: isLatest,
        onFetchPage: (page, {genreId, year}) async {
          if (genreId != null || year != null) {
            return await ApiClient.discoverMovies(
              language: language,
              genreId: genreId,
              year: year,
              page: page,
            );
          }

          final resp = await ApiClient.getDashboardLane(
            laneId: laneId,
            language: language,
            page: page,
          );

          if (resp != null && resp['items'] is List) {
            final items = resp['items'] as List;
            return items
                .map((i) => Movie.fromJson(Map<String, dynamic>.from(i)))
                .toList();
          }
          return [];
        },
      ),
    );
  }
}
