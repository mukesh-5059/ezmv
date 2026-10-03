import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api_client.dart';
import '../models/actor.model.dart';
import '../models/movie.model.dart';
import '../theme.dart';
import '../widgets/movie_lane.dart';
import 'details_screen.dart';

class ActorScreen extends StatefulWidget {
  final int actorId;
  final String? initialActorName;
  final String? initialProfilePath;

  const ActorScreen({
    super.key,
    required this.actorId,
    this.initialActorName,
    this.initialProfilePath,
  });

  @override
  State<ActorScreen> createState() => _ActorScreenState();
}

class _ActorScreenState extends State<ActorScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  ActorFilmography? _filmography;
  Movie? _focusedMovie;

  final FocusNode _backButtonFocusNode = FocusNode();
  final Map<String, List<FocusNode>> _rowFocusNodes = {
    'recent': [],
    'popular': [],
  };
  final Map<String, int> _rowLastFocusedIndex = {
    'recent': 0,
    'popular': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadFilmography();
  }

  @override
  void dispose() {
    _backButtonFocusNode.dispose();
    for (final nodes in _rowFocusNodes.values) {
      for (final n in nodes) {
        n.dispose();
      }
    }
    super.dispose();
  }

  FocusNode _getFocusNode(String rowKey, int index) {
    final nodes = _rowFocusNodes.putIfAbsent(rowKey, () => []);
    while (nodes.length <= index) {
      nodes.add(FocusNode(debugLabel: '$rowKey#${nodes.length}'));
    }
    return nodes[index];
  }

  List<String> get _visibleRowKeys {
    if (_filmography == null) return [];
    final keys = <String>[];
    if (_filmography!.recent.isNotEmpty) keys.add('recent');
    if (_filmography!.popular.isNotEmpty) keys.add('popular');
    return keys;
  }

  int _getRowItemCount(String rowKey) {
    if (_filmography == null) return 0;
    if (rowKey == 'recent') return _filmography!.recent.length;
    if (rowKey == 'popular') return _filmography!.popular.length;
    return 0;
  }

  KeyEventResult _handleRowKeyNavigation(
    String rowKey,
    int index,
    int itemCount,
    RawKeyEvent event,
  ) {
    if (event is! RawKeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final visibleRows = _visibleRowKeys;
    final currentVisibleRowIndex = visibleRows.indexOf(rowKey);

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _getFocusNode(rowKey, index - 1).requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (index < itemCount - 1) {
        _getFocusNode(rowKey, index + 1).requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (currentVisibleRowIndex >= 0 && currentVisibleRowIndex < visibleRows.length - 1) {
        final nextRowKey = visibleRows[currentVisibleRowIndex + 1];
        final nextRowCount = _getRowItemCount(nextRowKey);
        if (nextRowCount > 0) {
          var destIndex = _rowLastFocusedIndex[nextRowKey] ?? 0;
          if (destIndex >= nextRowCount) destIndex = nextRowCount - 1;
          _getFocusNode(nextRowKey, destIndex).requestFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (currentVisibleRowIndex > 0) {
        final prevRowKey = visibleRows[currentVisibleRowIndex - 1];
        final prevRowCount = _getRowItemCount(prevRowKey);
        if (prevRowCount > 0) {
          var destIndex = _rowLastFocusedIndex[prevRowKey] ?? 0;
          if (destIndex >= prevRowCount) destIndex = prevRowCount - 1;
          _getFocusNode(prevRowKey, destIndex).requestFocus();
          return KeyEventResult.handled;
        }
      } else if (currentVisibleRowIndex == 0) {
        _backButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  Future<void> _loadFilmography() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final filmo = await ApiClient.getActorFilmography(widget.actorId);
      if (mounted) {
        Movie? firstMovie;
        if (filmo != null) {
          if (filmo.recent.isNotEmpty) {
            firstMovie = filmo.recent.first;
          } else if (filmo.popular.isNotEmpty) {
            firstMovie = filmo.popular.first;
          }
        }

        setState(() {
          _filmography = filmo;
          _focusedMovie = firstMovie;
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final visibleRows = _visibleRowKeys;
            if (visibleRows.isNotEmpty) {
              _getFocusNode(visibleRows.first, 0).requestFocus();
            } else {
              _backButtonFocusNode.requestFocus();
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load actor filmography: $e';
        });
      }
    }
  }

  void _openMovieDetails(Movie movie) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(movie: movie),
      ),
    );
  }

  Widget _buildBillboard() {
    final actorName = _filmography?.name ?? widget.initialActorName ?? 'Actor';
    final profileUrl = _filmography?.profileUrl ??
        (widget.initialProfilePath != null && widget.initialProfilePath!.isNotEmpty
            ? 'https://image.tmdb.org/t/p/w185${widget.initialProfilePath}'
            : '');
    final department = _filmography?.knownForDepartment ?? 'Acting';
    final movie = _focusedMovie;

    return Container(
      height: 250,
      width: double.infinity,
      color: TVTheme.surfaceElevated,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Dynamic Movie Backdrop with AnimatedSwitcher
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: movie != null && movie.backdropUrl.isNotEmpty
                ? Image.network(
                    movie.backdropUrl,
                    key: ValueKey('backdrop_${movie.tmdbId}'),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  )
                : const SizedBox.shrink(key: ValueKey('empty_backdrop')),
          ),

          // Cinematic Gradient Overlays
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  TVTheme.background,
                  TVTheme.background.withValues(alpha: 0.85),
                  TVTheme.background.withValues(alpha: 0.4),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.35, 0.7, 1.0],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.4),
                  Colors.transparent,
                  TVTheme.background.withValues(alpha: 0.9),
                  TVTheme.background,
                ],
                stops: const [0.0, 0.3, 0.75, 1.0],
              ),
            ),
          ),

          // Content Layer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Back Button & Actor Identification Badge
                Row(
                  children: [
                    Focus(
                      focusNode: _backButtonFocusNode,
                      onKey: (node, event) {
                        if (event is RawKeyDownEvent) {
                          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                            final visibleRows = _visibleRowKeys;
                            if (visibleRows.isNotEmpty) {
                              final firstRowKey = visibleRows.first;
                              final maxCount = _getRowItemCount(firstRowKey);
                              if (maxCount > 0) {
                                var destIndex = _rowLastFocusedIndex[firstRowKey] ?? 0;
                                if (destIndex >= maxCount) destIndex = maxCount - 1;
                                _getFocusNode(firstRowKey, destIndex).requestFocus();
                                return KeyEventResult.handled;
                              }
                            }
                          }
                          if (event.logicalKey == LogicalKeyboardKey.select ||
                              event.logicalKey == LogicalKeyboardKey.enter ||
                              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                              event.logicalKey == LogicalKeyboardKey.space) {
                            Navigator.of(context).pop();
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Builder(
                        builder: (context) {
                          final focused = Focus.of(context).hasFocus;
                          return InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: focused ? TVTheme.accent : TVTheme.surface.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: focused ? Colors.white : Colors.white12,
                                  width: focused ? 1.5 : 1.0,
                                ),
                                boxShadow: focused
                                    ? [
                                        BoxShadow(
                                          color: TVTheme.accent.withValues(alpha: 0.5),
                                          blurRadius: 10,
                                        ),
                                      ]
                                    : [],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_back, size: 16, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text(
                                    'Back',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Actor Profile Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: TVTheme.surface.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (profileUrl.isNotEmpty) ...[
                            ClipOval(
                              child: Image.network(
                                profileUrl,
                                width: 22,
                                height: 22,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person,
                                  size: 16,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            actorName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '• $department',
                            style: const TextStyle(
                              color: TVTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),

                // Focused Movie Showcase in Hero
                if (movie != null) ...[
                  Text(
                    movie.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      shadows: [
                        Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (movie.voteAverage > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade700,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, size: 12, color: Colors.black),
                              const SizedBox(width: 3),
                              Text(
                                movie.voteAverage.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (movie.year.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: TVTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            movie.year,
                            style: const TextStyle(
                              color: TVTheme.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: TVTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          movie.isTv ? 'TV SERIES' : 'MOVIE',
                          style: const TextStyle(
                            color: TVTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (movie.overview.isNotEmpty)
                    SizedBox(
                      width: 580,
                      child: Text(
                        movie.overview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TVTheme.textSecondary,
                          fontSize: 13,
                          height: 1.3,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TVTheme.background,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: TVTheme.accent),
              )
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadFilmography,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBillboard(),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          children: [
                            if (_filmography != null && _filmography!.recent.isNotEmpty)
                              MovieLane(
                                rowKey: 'recent',
                                title: 'Recent Releases',
                                movies: _filmography!.recent,
                                onMovieTap: _openMovieDetails,
                                onMovieFocused: (m) => setState(() => _focusedMovie = m),
                                getFocusNode: _getFocusNode,
                                onKeyNav: _handleRowKeyNavigation,
                                onFocusedIndexChanged: (k, idx) => _rowLastFocusedIndex[k] = idx,
                              ),
                            if (_filmography != null && _filmography!.popular.isNotEmpty)
                              MovieLane(
                                rowKey: 'popular',
                                title: 'Top & Popular Movies',
                                movies: _filmography!.popular,
                                onMovieTap: _openMovieDetails,
                                onMovieFocused: (m) => setState(() => _focusedMovie = m),
                                getFocusNode: _getFocusNode,
                                onKeyNav: _handleRowKeyNavigation,
                                onFocusedIndexChanged: (k, idx) => _rowLastFocusedIndex[k] = idx,
                              ),
                            if (_filmography != null &&
                                _filmography!.popular.isEmpty &&
                                _filmography!.recent.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(32.0),
                                child: Center(
                                  child: Text(
                                    'No movies found for this actor.',
                                    style: TextStyle(color: TVTheme.textSecondary),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
