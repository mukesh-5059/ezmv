import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import '../../theme.dart';
import '../tv_focus_card.dart';
import '../tv_unified_header_strip.dart';

/// Standard Horizontal Content Movie Lane for 10-foot Android TV interface.
///
/// Features:
/// - Uses [TvUnifiedHeaderStrip] with title and "Show All (N) ›" CTA.
/// - Horizontal [ListView.builder] with [PageStorageKey] for preserving scroll offset.
/// - Implements [AutomaticKeepAliveClientMixin] (`wantKeepAlive = true`) to prevent Focus Amnesia!
/// - Auto-centers focused card horizontally at 50% viewport width.
/// - Remote D-pad: Pressing `Up` from any card enters [TvUnifiedHeaderStrip].
///   Pressing `Down` from header strip restores focus to the active card.
///   Pressing `OK/Select` on header strip triggers [onShowAll].
///   Selecting a movie card triggers [onMovieTap].
class TvMovieLane extends StatefulWidget {
  final DashboardLane lane;
  final void Function(MovieSummary movie) onMovieTap;
  final void Function(DashboardLane lane) onShowAll;
  final FocusNode? headerFocusNode;
  final VoidCallback? onNavigateUpFromHeader;
  final VoidCallback? onNavigateDownFromCard;

  const TvMovieLane({
    super.key,
    required this.lane,
    required this.onMovieTap,
    required this.onShowAll,
    this.headerFocusNode,
    this.onNavigateUpFromHeader,
    this.onNavigateDownFromCard,
  });

  @override
  State<TvMovieLane> createState() => _TvMovieLaneState();
}

class _TvMovieLaneState extends State<TvMovieLane>
    with AutomaticKeepAliveClientMixin {
  final FocusNode _headerFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<FocusNode> _itemFocusNodes = [];
  int _lastFocusedIndex = 0;

  FocusNode get _effectiveHeaderFocusNode => widget.headerFocusNode ?? _headerFocusNode;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _headerFocusNode.dispose();
    _scrollController.dispose();
    for (final node in _itemFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _getFocusNode(int index) {
    while (_itemFocusNodes.length <= index) {
      _itemFocusNodes.add(FocusNode());
    }
    return _itemFocusNodes[index];
  }

  KeyEventResult _handleHeaderKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (widget.lane.items.isNotEmpty) {
          final targetIndex = _lastFocusedIndex.clamp(0, widget.lane.items.length - 1);
          _getFocusNode(targetIndex).requestFocus();
          return KeyEventResult.handled;
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (widget.onNavigateUpFromHeader != null) {
          widget.onNavigateUpFromHeader!();
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCardKeyEvent(KeyEvent event, int index) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _effectiveHeaderFocusNode.requestFocus();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (widget.onNavigateDownFromCard != null) {
          widget.onNavigateDownFromCard!();
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.lane.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalCount = widget.lane.totalItems > 0
        ? widget.lane.totalItems
        : widget.lane.items.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Focusable Lane Header Strip
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TVTheme.overscanMargin),
          child: TvUnifiedHeaderStrip(
            title: widget.lane.title,
            count: totalCount,
            focusNode: _effectiveHeaderFocusNode,
            onShowAll: () => widget.onShowAll(widget.lane),
            onKeyEvent: (node, event) => _handleHeaderKeyEvent(event),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
        const SizedBox(height: 8),

        // Horizontal Card Carousel
        SizedBox(
          height: 290,
          child: ListView.builder(
            key: PageStorageKey('lane_${widget.lane.id}'),
            controller: _scrollController,
            cacheExtent: 320,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: TVTheme.overscanMargin),
            itemCount: widget.lane.items.length,
            itemBuilder: (context, index) {
              final movie = widget.lane.items[index];

              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TvFocusCard(
                  focusNode: _getFocusNode(index),
                  posterUrl: movie.posterUrl,
                  title: movie.title,
                  rating: movie.ratingScore > 0 ? movie.ratingScore : null,
                  isTv: movie.isTv,
                  year: movie.year,
                  width: 150,
                  height: 225,
                  showTitleBelow: true,
                  onFocusChanged: (focused) {
                    if (focused) _lastFocusedIndex = index;
                  },
                  onKeyEvent: (node, event) => _handleCardKeyEvent(event, index),
                  onTap: () => widget.onMovieTap(movie),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
