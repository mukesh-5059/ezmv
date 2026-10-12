import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../screens/lane_grid_screen.dart';
import '../theme.dart';
import 'movie_card.dart';

class MovieLane extends StatelessWidget {
  final String title;
  final List<Movie> movies;
  final String? laneId;
  final String? language;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool isLoadingMore;
  final double cardWidth;
  final double cardHeight;

  const MovieLane({
    super.key,
    required this.title,
    required this.movies,
    this.laneId,
    this.language,
    this.subtitle,
    this.onSeeAll,
    this.onLoadMore,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.cardWidth = 120,
    this.cardHeight = 180,
  });

  void _navigateToGrid(BuildContext context) {
    if (onSeeAll != null) {
      onSeeAll!();
    } else if (laneId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LaneGridScreen(
            title: title,
            laneId: laneId!,
            language: language ?? 'en',
            initialMovies: movies,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) return const SizedBox.shrink();

    final canOpenGrid = onSeeAll != null || laneId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with title and trailing arrow indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: MobileTheme.textPrimary,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: MobileTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (canOpenGrid)
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _navigateToGrid(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: MobileTheme.accent,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Horizontal Scrollable Cards List
        SizedBox(
          height: cardHeight + 42,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 150) {
                if (hasMore && !isLoadingMore && onLoadMore != null) {
                  onLoadMore!();
                }
              }
              return false;
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: movies.length + (hasMore || isLoadingMore ? 1 : 0),
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (index >= movies.length) {
                  return Container(
                    width: 60,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: MobileTheme.accent,
                      ),
                    ),
                  );
                }
                final movie = movies[index];
                return MovieCard(
                  movie: movie,
                  width: cardWidth,
                  height: cardHeight,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
