import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.model.dart';
import '../theme.dart';
import 'movie_card.dart';

class MovieLane extends StatelessWidget {
  final String rowKey;
  final String title;
  final List<Movie> movies;
  final void Function(Movie movie) onMovieTap;
  final void Function(Movie movie) onMovieFocused;
  final VoidCallback? onLoadMore;
  final VoidCallback? onClear;
  final FocusNode? clearFocusNode;
  final FocusNode Function(String rowKey, int index) getFocusNode;
  final KeyEventResult Function(String rowKey, int index, int itemCount, RawKeyEvent event) onKeyNav;
  final void Function(String rowKey, int index) onFocusedIndexChanged;

  const MovieLane({
    super.key,
    required this.rowKey,
    required this.title,
    required this.movies,
    required this.onMovieTap,
    required this.onMovieFocused,
    this.onLoadMore,
    this.onClear,
    this.clearFocusNode,
    required this.getFocusNode,
    required this.onKeyNav,
    required this.onFocusedIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final showClear = onClear != null;
    if (movies.isEmpty && !showClear) {
      return SizedBox.shrink(key: ValueKey('${rowKey}_empty'));
    }

    final hasLoadMore = onLoadMore != null && movies.isNotEmpty;
    final itemCount = movies.length + (hasLoadMore ? 1 : 0);

    return Builder(
      builder: (rowContext) {
        return Column(
          key: ValueKey(rowKey),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 24.0, top: 16.0, bottom: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  if (showClear && clearFocusNode != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 24.0),
                      child: Focus(
                        focusNode: clearFocusNode,
                        onKey: (node, event) {
                          if (event is RawKeyDownEvent) {
                            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                              getFocusNode(rowKey, 0).requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey == LogicalKeyboardKey.select ||
                                event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                event.logicalKey == LogicalKeyboardKey.space) {
                              onClear!();
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(
                          builder: (context) {
                            final focused = Focus.of(context).hasFocus;
                            return TextButton.icon(
                              style: TextButton.styleFrom(
                                backgroundColor: focused ? TVTheme.accent : Colors.transparent,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('Clear Search', style: TextStyle(fontSize: 12)),
                              onPressed: onClear,
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 240,
              child: movies.isEmpty && showClear
                  ? const Center(
                      child: Text(
                        'No search results found.',
                        style: TextStyle(color: TVTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        if (hasLoadMore && index == movies.length) {
                          final node = getFocusNode(rowKey, index);
                          return Focus(
                            focusNode: node,
                            onFocusChange: (focused) {
                              if (focused) {
                                onFocusedIndexChanged(rowKey, index);
                                if (node.context != null) {
                                  Scrollable.ensureVisible(
                                    node.context!,
                                    duration: const Duration(milliseconds: 300),
                                    alignment: 0.5,
                                    curve: Curves.easeInOut,
                                  );
                                  Scrollable.ensureVisible(
                                    rowContext,
                                    duration: const Duration(milliseconds: 300),
                                    alignment: 0.5,
                                    curve: Curves.easeInOut,
                                  );
                                }
                              }
                            },
                            onKey: (node, event) {
                              final navResult = onKeyNav(rowKey, index, itemCount, event);
                              if (navResult != KeyEventResult.ignored) {
                                return navResult;
                              }
                              if (event is RawKeyDownEvent) {
                                if (event.logicalKey == LogicalKeyboardKey.select ||
                                    event.logicalKey == LogicalKeyboardKey.enter ||
                                    event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                    event.logicalKey == LogicalKeyboardKey.space) {
                                  onLoadMore!();
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (context) {
                                final isFocused = Focus.of(context).hasFocus;
                                return GestureDetector(
                                  onTap: onLoadMore,
                                  child: AnimatedScale(
                                    scale: isFocused ? 1.06 : 1.0,
                                    duration: const Duration(milliseconds: 150),
                                    curve: Curves.easeInOut,
                                    child: Container(
                                      width: 130,
                                      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                      decoration: TVTheme.focusDecoration(isFocused),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(5),
                                        child: AspectRatio(
                                          aspectRatio: 2 / 3,
                                          child: Container(
                                            color: TVTheme.surface,
                                            child: Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.arrow_forward,
                                                    color: isFocused ? Colors.white : Colors.white70,
                                                    size: 32,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    'Load More',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: isFocused ? Colors.white : Colors.white70,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        }

                        final movie = movies[index];
                        final node = getFocusNode(rowKey, index);
                        return MovieCard(
                          key: ValueKey('${rowKey}_${movie.tmdbId}_$index'),
                          movie: movie,
                          focusNode: node,
                          onFocusChanged: (focused) {
                            if (focused) {
                              onMovieFocused(movie);
                              onFocusedIndexChanged(rowKey, index);
                              if (node.context != null) {
                                Scrollable.ensureVisible(
                                  node.context!,
                                  duration: const Duration(milliseconds: 300),
                                  alignment: 0.5,
                                  curve: Curves.easeInOut,
                                );
                                Scrollable.ensureVisible(
                                  rowContext,
                                  duration: const Duration(milliseconds: 300),
                                  alignment: 0.5,
                                  curve: Curves.easeInOut,
                                );
                              }
                            }
                          },
                          onKey: (node, event) => onKeyNav(rowKey, index, itemCount, event),
                          onTap: () => onMovieTap(movie),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
