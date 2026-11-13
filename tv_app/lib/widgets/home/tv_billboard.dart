import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import '../../theme.dart';

/// 10-Foot Hero Billboard Carousel for Android TV.
///
/// Features:
/// - Hero items sourced directly from backend pre-computed billboard, with minimal lane fallback.
/// - Auto-scroll timer with auto-pause on focus and cancel on vertical scroll.
/// - Display typography (38sp bold), rating badge, release year, overview.
/// - Carousel continuous cycling via Left / Right D-pad arrows when focused.
/// - Full card focusable button: brightens on focus, dims on unfocus.
class TvBillboard extends StatefulWidget {
  final List<DashboardLane> lanes;
  final List<MovieSummary>? items;
  final bool isVisible;
  final void Function(MovieSummary movie)? onSelect;
  final void Function(MovieSummary movie)? onPlay;
  final void Function(MovieSummary movie)? onDetails;
  final FocusNode? focusNode;
  final FocusNode? playButtonFocusNode;
  final FocusNode? detailsButtonFocusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final bool autofocus;

  const TvBillboard({
    super.key,
    required this.lanes,
    this.items,
    this.isVisible = true,
    this.onSelect,
    this.onPlay,
    this.onDetails,
    this.focusNode,
    this.playButtonFocusNode,
    this.detailsButtonFocusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.autofocus = false,
  });

  @override
  State<TvBillboard> createState() => _TvBillboardState();
}

class _TvBillboardState extends State<TvBillboard> {
  List<MovieSummary> _featuredMovies = [];
  int _currentIndex = 0;
  Timer? _autoScrollTimer;
  bool _hasFocus = false;
  int _lastRepeatMs = 0;

  final FocusNode _localFocusNode = FocusNode(debugLabel: 'TvBillboard');
  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? widget.playButtonFocusNode ?? _localFocusNode;

  @override
  void initState() {
    super.initState();
    _computeFeaturedMovies();
    _effectiveFocusNode.addListener(_onFocusChange);
    _resetTimer();
  }

  @override
  void didUpdateWidget(covariant TvBillboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lanes != widget.lanes) {
      _computeFeaturedMovies();
    }
    final oldEffective = oldWidget.focusNode ?? oldWidget.playButtonFocusNode;
    final newEffective = widget.focusNode ?? widget.playButtonFocusNode;
    if (oldEffective != newEffective) {
      oldEffective?.removeListener(_onFocusChange);
      _effectiveFocusNode.addListener(_onFocusChange);
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
    _effectiveFocusNode.removeListener(_onFocusChange);
    _localFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final hasFocusNow = _effectiveFocusNode.hasFocus;
    if (_hasFocus != hasFocusNow) {
      setState(() => _hasFocus = hasFocusNow);
      if (_hasFocus) {
        _stopTimer();
      } else if (widget.isVisible) {
        _resetTimer();
      }
    }
  }

  void _previousMovie() {
    if (_featuredMovies.length <= 1) return;
    setState(() {
      _currentIndex = (_currentIndex - 1 + _featuredMovies.length) % _featuredMovies.length;
    });
    _stopTimer();
  }

  void _nextMovie() {
    if (_featuredMovies.length <= 1) return;
    setState(() {
      _currentIndex = (_currentIndex + 1) % _featuredMovies.length;
    });
    _stopTimer();
  }

  void _handleSelect(MovieSummary movie) {
    if (widget.onSelect != null) {
      widget.onSelect!(movie);
    } else if (widget.onDetails != null) {
      widget.onDetails!(movie);
    } else if (widget.onPlay != null) {
      widget.onPlay!(movie);
    }
  }

  void _computeFeaturedMovies() {
    if (widget.items != null && widget.items!.isNotEmpty) {
      _featuredMovies = widget.items!.take(5).toList();
      if (_currentIndex >= _featuredMovies.length) _currentIndex = 0;
      return;
    }

    if (widget.lanes.isEmpty) {
      _featuredMovies = [];
      return;
    }

    final allItems = <MovieSummary>[];
    final seenIds = <String>{};
    for (final lane in widget.lanes) {
      for (final item in lane.items) {
        if (seenIds.add(item.imdbId)) allItems.add(item);
      }
    }

    _featuredMovies = allItems.take(5).toList();
    if (_currentIndex >= _featuredMovies.length) _currentIndex = 0;
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
      focusNode: _effectiveFocusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (_hasFocus != focused) {
          setState(() => _hasFocus = focused);
          if (_hasFocus) {
            _stopTimer();
          } else if (widget.isVisible) {
            _resetTimer();
          }
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            final now = DateTime.now().millisecondsSinceEpoch;
            if (event is KeyDownEvent || now - _lastRepeatMs > 180) {
              _lastRepeatMs = now;
              _previousMovie();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            final now = DateTime.now().millisecondsSinceEpoch;
            if (event is KeyDownEvent || now - _lastRepeatMs > 180) {
              _lastRepeatMs = now;
              _nextMovie();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            if (event is KeyDownEvent && widget.onNavigateUp != null) {
              widget.onNavigateUp!();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (event is KeyDownEvent && widget.onNavigateDown != null) {
              widget.onNavigateDown!();
            }
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            _handleSelect(movie);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => _handleSelect(movie),
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

              // Dimming Scrim: Darkens when out of focus, clears when in focus
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  color: Colors.black.withValues(alpha: _hasFocus ? 0.0 : 0.42),
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
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _hasFocus ? 1.0 : 0.75,
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
                  const SizedBox(height: 16),

                  // Action Hint Pill (Revealed when focused)
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _hasFocus ? 1.0 : 0.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: TVTheme.primary,
                        borderRadius: TVTheme.borderRadiusMd,
                        boxShadow: [
                          BoxShadow(
                            color: TVTheme.primary.withValues(alpha: 0.45),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'View Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

            // Carousel Slide Indicators (Bottom Right)
            if (_featuredMovies.length > 1)
              Positioned(
                right: TVTheme.overscanMargin,
                bottom: 36,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _hasFocus ? 1.0 : 0.6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_hasFocus) ...[
                        Icon(
                          Icons.chevron_left_rounded,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(_featuredMovies.length, (index) {
                          final isActive = index == _currentIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: isActive ? 22 : 8,
                            height: 5,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? TVTheme.primary
                                  : Colors.white.withValues(alpha: _hasFocus ? 0.4 : 0.2),
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
                      if (_hasFocus) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
}
