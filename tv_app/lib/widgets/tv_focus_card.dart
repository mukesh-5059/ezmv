import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import 'tv_shortcuts.dart';

/// Standard 10-Foot Focusable Poster Card for Android TV.
///
/// Features:
/// - 10dp rounded corners with [ClipRRect].
/// - Memory-capped image downsampling (300x450 memCache) to prevent LMK on 1.5GB RAM TVs.
/// - Smooth 200ms 1.08x scale and dual-layer focus shadow elevation on D-pad navigation.
/// - Auto-centering scroll alignment on focus.
/// - Optional rating badge, TV series badge, and resume progress bar.
class TvFocusCard extends StatefulWidget {
  final String posterUrl;
  final String title;
  final VoidCallback onTap;
  final double? rating;
  final double? progress;
  final bool isTv;
  final String? qualityBadge;
  final String? year;
  final double width;
  final double? height;
  final bool showTitleBelow;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChanged;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;
  final EdgeInsetsGeometry? margin;

  const TvFocusCard({
    super.key,
    required this.posterUrl,
    required this.title,
    required this.onTap,
    this.rating,
    this.progress,
    this.isTv = false,
    this.qualityBadge,
    this.year,
    this.width = 150,
    this.height,
    this.showTitleBelow = false,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChanged,
    this.onKeyEvent,
    this.margin,
  });

  @override
  State<TvFocusCard> createState() => _TvFocusCardState();
}

class _TvFocusCardState extends State<TvFocusCard> {
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
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.movie_filter_outlined,
            size: 36,
            color: TVTheme.textSecondary,
          ),
          const SizedBox(height: 10),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: TVTheme.textPrimary,
              height: 1.2,
            ),
          ),
          if (widget.year != null && widget.year!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.year!,
              style: const TextStyle(
                fontSize: 12,
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
    final cardHeight = widget.height ?? (widget.width * 1.5);

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: TVTheme.focusDuration,
            curve: Curves.easeInOut,
          );
        }
        widget.onFocusChanged?.call(focused);
      },
      onKeyEvent: (node, event) {
        if (widget.onKeyEvent != null) {
          final res = widget.onKeyEvent!(node, event);
          if (res != KeyEventResult.ignored) return res;
        }
        return TvShortcuts.handleKeyEvent(
          event,
          onActivate: widget.onTap,
        );
      },
      child: RepaintBoundary(
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
          scale: _isFocused ? TVTheme.focusScale : 1.0,
          duration: TVTheme.focusDuration,
          curve: TVTheme.focusCurve,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: widget.width,
                height: cardHeight,
                margin: widget.margin ?? const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: TVTheme.focusDecoration(
                  _isFocused,
                  radius: TVTheme.radiusMd,
                  backgroundColor: TVTheme.surface,
                ),
                child: ClipRRect(
                  borderRadius: TVTheme.borderRadiusMd,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Poster Image with Strict Downsampling
                      if (widget.posterUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: widget.posterUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 300,
                          memCacheHeight: 450,
                          maxWidthDiskCache: 300,
                          placeholder: (context, url) => Container(
                            color: TVTheme.surface,
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: TVTheme.primary,
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => _buildFallbackCard(),
                        )
                      else
                        _buildFallbackCard(),

                      // Top-Left Badges (TV Series & Quality)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.isTv)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: TVTheme.primary.withValues(alpha: 0.92),
                                  borderRadius: TVTheme.borderRadiusSm,
                                ),
                                child: const Text(
                                  'TV',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            if (widget.qualityBadge != null && widget.qualityBadge!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: TVTheme.borderRadiusSm,
                                ),
                                child: Text(
                                  widget.qualityBadge!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Top-Right Rating Badge
                      if (widget.rating != null && widget.rating! > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.78),
                              borderRadius: TVTheme.borderRadiusSm,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 13,
                                  color: Color(0xFFFFD700),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  widget.rating!.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Bottom Progress Bar (Continue Watching)
                      if (widget.progress != null && widget.progress! > 0)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 4,
                            color: Colors.black54,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: widget.progress!.clamp(0.0, 1.0),
                              child: Container(
                                color: TVTheme.primary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Optional Title & Year Beneath Card
              if (widget.showTitleBelow)
                Padding(
                  padding: const EdgeInsets.only(left: 6, right: 6, top: 4),
                  child: SizedBox(
                    width: widget.width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: _isFocused ? FontWeight.w700 : FontWeight.w500,
                            color: _isFocused ? TVTheme.textPrimary : TVTheme.textSecondary,
                          ),
                        ),
                        if (widget.year != null && widget.year!.isNotEmpty)
                          Text(
                            widget.year!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: TVTheme.textMuted,
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
    ),
  );
  }
}
