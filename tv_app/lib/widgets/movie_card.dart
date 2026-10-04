import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';

class MovieCard extends StatefulWidget {
  final Movie movie;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChanged;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;
  final KeyEventResult Function(FocusNode, RawKeyEvent)? onKey;
  final double? progress;

  const MovieCard({
    super.key,
    required this.movie,
    required this.onTap,
    this.onFocusChanged,
    this.focusNode,
    this.onKeyEvent,
    this.onKey,
    this.progress,
  });

  @override
  State<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<MovieCard> {
  bool _isFocused = false;

  Widget _buildFallbackCard() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            TVTheme.surfaceElevated,
            TVTheme.surface,
          ],
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.movie_filter_outlined,
            size: 32,
            color: TVTheme.textSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            widget.movie.title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: TVTheme.textPrimary,
            ),
          ),
          if (widget.movie.year.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.movie.year,
              style: const TextStyle(
                fontSize: 11,
                color: TVTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKey: widget.onKey,
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        }
        if (widget.onFocusChanged != null) {
          widget.onFocusChanged!(focused);
        }
      },
      onKeyEvent: (node, event) {
        if (widget.onKeyEvent != null) {
          final res = widget.onKeyEvent!(node, event);
          if (res != KeyEventResult.ignored) {
            return res;
          }
        }
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: Container(
            width: 130,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: TVTheme.focusDecoration(_isFocused, radius: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.movie.posterUrl.isNotEmpty)
                      Image.network(
                        widget.movie.posterUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _buildFallbackCard(),
                      )
                    else
                      _buildFallbackCard(),
                    if (widget.progress != null && widget.progress! > 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 3.5,
                          color: Colors.black54,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: widget.progress!.clamp(0.0, 1.0),
                            child: Container(
                              color: TVTheme.accent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
