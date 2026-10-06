import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import 'movie_card.dart';

class MovieLane extends StatelessWidget {
  final String title;
  final List<Movie> movies;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final double cardWidth;
  final double cardHeight;

  const MovieLane({
    super.key,
    required this.title,
    required this.movies,
    this.subtitle,
    this.onSeeAll,
    this.cardWidth = 120,
    this.cardHeight = 180,
  });

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
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
              if (onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See All',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: MobileTheme.accent,
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 16, color: MobileTheme.accent),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Horizontal Scrollable Cards List
        SizedBox(
          height: cardHeight + 42,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: movies.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final movie = movies[index];
              return MovieCard(
                movie: movie,
                width: cardWidth,
                height: cardHeight,
              );
            },
          ),
        ),
      ],
    );
  }
}
