import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import '../../theme.dart';
import '../tv_focus_card.dart';
import '../tv_unified_header_strip.dart';

/// Row 0 Continue Watching Lane for 10-foot Android TV interface.
///
/// Dynamically hidden if watch history is empty. Loads watch entries from
/// [StorageService.instance.getContinueWatching] with visual playback progress bars.
class TvContinueWatchingLane extends StatefulWidget {
  final void Function(ContinueWatchingEntry entry) onResume;
  final VoidCallback? onWatchHistoryCleared;

  const TvContinueWatchingLane({
    super.key,
    required this.onResume,
    this.onWatchHistoryCleared,
  });

  @override
  State<TvContinueWatchingLane> createState() => TvContinueWatchingLaneState();
}

class TvContinueWatchingLaneState extends State<TvContinueWatchingLane>
    with AutomaticKeepAliveClientMixin {
  List<ContinueWatchingEntry> _entries = [];
  bool _isLoading = true;
  final FocusNode _headerFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<FocusNode> _itemFocusNodes = [];
  int _lastFocusedIndex = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

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
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_entries.isNotEmpty) {
        final targetIndex = _lastFocusedIndex.clamp(0, _entries.length - 1);
        _getFocusNode(targetIndex).requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> refresh() async {
    try {
      final items = await StorageService.instance.getContinueWatching();
      if (mounted) {
        setState(() {
          _entries = items.where((e) => !e.isCompleted).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = [];
          _isLoading = false;
        });
      }
    }
  }

  KeyEventResult _handleCardKeyEvent(KeyEvent event, int index) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _headerFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading || _entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TVTheme.overscanMargin),
          child: Focus(
            onKeyEvent: (node, event) => _handleHeaderKeyEvent(event),
            child: TvUnifiedHeaderStrip(
              title: 'Continue Watching',
              count: _entries.length,
              focusNode: _headerFocusNode,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 290,
          child: ListView.builder(
            key: const PageStorageKey('lane_continue_watching'),
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: TVTheme.overscanMargin),
            itemCount: _entries.length,
            itemBuilder: (context, index) {
              final entry = _entries[index];
              final subtitle = entry.isTv && entry.season != null
                  ? 'S${entry.season} E${entry.episode ?? 1}'
                  : null;

              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TvFocusCard(
                  focusNode: _getFocusNode(index),
                  posterUrl: entry.posterUrl,
                  title: entry.title,
                  width: 150,
                  height: 225,
                  isTv: entry.isTv,
                  progress: entry.progress,
                  year: subtitle,
                  showTitleBelow: true,
                  onFocusChanged: (focused) {
                    if (focused) _lastFocusedIndex = index;
                  },
                  onKeyEvent: (node, event) => _handleCardKeyEvent(event, index),
                  onTap: () => widget.onResume(entry),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
