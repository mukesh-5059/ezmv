import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../../theme.dart';
import '../tv_focus_button.dart';

/// 10-Foot Hero Billboard Carousel for Android TV.
///
/// Features:
/// - Selection heuristic:
///   1. Intersect `new_ott` ∩ `trending` with `comedy` genre.
///   2. Fallback: `trending` with `comedy` genre.
///   3. Fallback: top items in `trending`.
///   4. Fallback: first available high-rated titles.
/// - Auto-scroll timer with auto-pause on focus and cancel on vertical scroll.
/// - Display typography (38sp bold), rating badge, release year, overview.
/// - Dual CTA: "Play Now" (primary red) and "Details" (tonal).
class TvBillboard extends StatefulWidget {
  final List<DashboardLane> lanes;
  final bool isVisible;
  final void Function(MovieSummary movie) onPlay;
  final void Function(MovieSummary movie) onDetails;

  const TvBillboard({
    super.key,
    required this.lanes,
    this.isVisible = true,
    required this.onPlay,
    required this.onDetails,
  });

  @override
  State<TvBillboard> createState() => _TvBillboardState();
}

class _TvBillboardState extends State<TvBillboard> {
  List<MovieSummary> _featuredMovies = [];
  int _currentIndex = 0;
  Timer? _autoScrollTimer;
  bool _hasFocus = false;

  final FocusNode _billboardScopeNode = FocusNode();
  final FocusNode _playButtonFocusNode = FocusNode();
  final FocusNode _detailsButtonFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _computeFeaturedMovies();
    _billboardScopeNode.addListener(_onFocusScopeChange);
    _playButtonFocusNode.addListener(_onFocusScopeChange);
    _detailsButtonFocusNode.addListener(_onFocusScopeChange);
    _resetTimer();
  }

  @override
  void didUpdateWidget(covariant TvBillboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lanes != widget.lanes) {
      _computeFeaturedMovies();
    }
    if (oldWidget.isVisible != widget.isVisible) {
      if (widget.isVisible) {
        _resetTimer();
      } else {
        _stopTimer();
      }
    }
  }

  @override
  void dispose() {
    _stopTimer();
    _billboardScopeNode.removeListener(_onFocusScopeChange);
    _playButtonFocusNode.removeListener(_onFocusScopeChange);
    _detailsButtonFocusNode.removeListener(_onFocusScopeChange);
    _billboardScopeNode.dispose();
    _playButtonFocusNode.dispose();
    _detailsButtonFocusNode.dispose();
    super.dispose();
  }

  void _onFocusScopeChange() {
    final hasFocusNow = _billboardScopeNode.hasFocus ||
        _playButtonFocusNode.hasFocus ||
        _detailsButtonFocusNode.hasFocus;

    if (_hasFocus != hasFocusNow) {
      setState(() => _hasFocus = hasFocusNow);
      if (_hasFocus) {
        // MUST pause timer when focus enters Billboard
        _stopTimer();
      } else if (widget.isVisible) {
        // Resume timer when focus leaves Billboard (if still visible)
        _resetTimer();
      }
    }
  }

  void _computeFeaturedMovies() {
    if (widget.lanes.isEmpty) {
      _featuredMovies = [];
      return;
    }

    DashboardLane? newOttLane;
    DashboardLane? trendingLane;

    for (final lane in widget.lanes) {
      final id = lane.id.toLowerCase();
      if (id == 'new_ott' || id.contains('new_ott') || id.contains('releases')) {
        newOttLane = lane;
      }
      if (id == 'trending' || id.contains('trending')) {
        trendingLane = lane;
      }
    }

    bool isComedy(MovieSummary m) {
      return m.genres.any((g) {
        final name = g.name.toLowerCase();
        final slug = g.slug.toLowerCase();
        return name == 'comedy' || slug == 'comedy';
      });
    }

    List<MovieSummary> candidates = [];

    // Heuristic 1: Intersect new_ott ∩ trending with comedy genre
    if (newOttLane != null && trendingLane != null) {
      final trendingMap = {for (final m in trendingLane.items) m.imdbId: m};
      for (final m in newOttLane.items) {
        if (trendingMap.containsKey(m.imdbId) && isComedy(m)) {
          candidates.add(m);
        }
      }
    }

    // Heuristic 2: Fallback: trending with comedy genre
    if (candidates.isEmpty && trendingLane != null) {
      candidates = trendingLane.items.where(isComedy).toList();
    }

    // Heuristic 3: Fallback: top items in trending
    if (candidates.isEmpty && trendingLane != null && trendingLane.items.isNotEmpty) {
      candidates = trendingLane.items.take(5).toList();
    }

    // Heuristic 4: Fallback: first available high-rated titles across all lanes
    if (candidates.isEmpty) {
      final allItems = <MovieSummary>[];
      final seenIds = <String>{};
      for (final lane in widget.lanes) {
        for (final item in lane.items) {
          if (seenIds.add(item.imdbId)) {
            allItems.add(item);
          }
        }
      }
      allItems.sort((a, b) {
        final cmp = b.voteCount.compareTo(a.voteCount);
        if (cmp != 0) return cmp;
        return b.ratingScore.compareTo(a.ratingScore);
      });
      candidates = allItems.take(5).toList();
    }

    // Sort all billboard candidates primarily by popularity (voteCount descending)
    candidates.sort((a, b) {
      final cmp = b.voteCount.compareTo(a.voteCount);
      if (cmp != 0) return cmp;
      return b.ratingScore.compareTo(a.ratingScore);
    });

    _featuredMovies = candidates.take(5).toList();
    if (_currentIndex >= _featuredMovies.length) {
      _currentIndex = 0;
    }
  }

  void _resetTimer() {
    _stopTimer();
    if (!widget.isVisible || _hasFocus || _featuredMovies.length <= 1) return;

    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !widget.isVisible || _hasFocus) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _featuredMovies.length;
      });
    });
  }

  void _stopTimer() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_featuredMovies.isEmpty) return const SizedBox.shrink();

    final movie = _featuredMovies[_currentIndex];

    return Focus(
      focusNode: _billboardScopeNode,
      child: Container(
        height: 460,
        margin: const EdgeInsets.only(bottom: 16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop Image with Smooth Cross-Fade
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 700),
              switchInCurve: Curves.easeIn,
              switchOutCurve: Curves.easeOut,
              child: SizedBox(
                key: ValueKey<String>(movie.imdbId),
                width: double.infinity,
                height: double.infinity,
                child: movie.backdropUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: movie.backdropUrl,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        memCacheWidth: 1280,
                        memCacheHeight: 720,
                        maxWidthDiskCache: 1280,
                        errorWidget: (context, url, error) => Container(
                          color: TVTheme.surfaceElevated,
                        ),
                      )
                    : Container(color: TVTheme.surfaceElevated),
              ),
            ),

            // Left-to-Right Obsidian Cinematic Dark Gradient (Ensures text legibility)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: const [0.0, 0.45, 0.75, 1.0],
                    colors: [
                      TVTheme.background,
                      TVTheme.background.withValues(alpha: 0.92),
                      TVTheme.background.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Bottom-to-Top Gradient (Seamless blend into lower lanes)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    stops: const [0.0, 0.25, 0.6, 1.0],
                    colors: [
                      TVTheme.background,
                      TVTheme.background.withValues(alpha: 0.85),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.25),
                    ],
                  ),
                ),
              ),
            ),

            // Foreground Content Layout
            Positioned(
              left: TVTheme.overscanMargin,
              bottom: 32,
              right: 160,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title Typography (Display 38sp bold)
                  Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      color: TVTheme.textPrimary,
                      letterSpacing: -0.5,
                      height: 1.15,
                      shadows: [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Metadata Badges Row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Rating Badge
                      if (movie.ratingScore > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: TVTheme.borderRadiusSm,
                            border: Border.all(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: Color(0xFFFFD700),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                movie.formattedRating,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              if (movie.formattedVoteCount.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '(${movie.formattedVoteCount})',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: TVTheme.textMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],

                      // Release Year
                      if (movie.year.isNotEmpty) ...[
                        Text(
                          movie.year,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: TVTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],

                      // Media Type Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: TVTheme.surfaceElevated,
                          borderRadius: TVTheme.borderRadiusSm,
                        ),
                        child: Text(
                          movie.isTv ? 'TV SERIES' : 'MOVIE',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: TVTheme.textSecondary,
                          ),
                        ),
                      ),

                      // Primary Genres
                      if (movie.genres.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(
                          movie.genres.take(3).map((g) => g.name).join(' • '),
                          style: const TextStyle(
                            fontSize: 13,
                            color: TVTheme.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Overview (max 3 lines)
                  if (movie.overview.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Text(
                        movie.overview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: TVTheme.textSecondary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),

                  // Action Buttons Row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TvFocusButton(
                        focusNode: _playButtonFocusNode,
                        label: 'Play Now',
                        icon: Icons.play_arrow_rounded,
                        isPrimary: true,
                        onPressed: () => widget.onPlay(movie),
                      ),
                      const SizedBox(width: 16),
                      TvFocusButton(
                        focusNode: _detailsButtonFocusNode,
                        label: 'Details',
                        icon: Icons.info_outline_rounded,
                        isPrimary: false,
                        onPressed: () => widget.onDetails(movie),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Carousel Slide Indicators (Bottom Right)
            if (_featuredMovies.length > 1)
              Positioned(
                right: TVTheme.overscanMargin,
                bottom: 36,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_featuredMovies.length, (index) {
                    final isActive = index == _currentIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 22 : 8,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isActive
                            ? TVTheme.primary
                            : Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: TVTheme.primary.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
