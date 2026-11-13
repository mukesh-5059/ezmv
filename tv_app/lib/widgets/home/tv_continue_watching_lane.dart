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
  final FocusNode? headerFocusNode;
  final VoidCallback? onNavigateUpFromHeader;
  final VoidCallback? onNavigateDownFromCard;

  const TvContinueWatchingLane({
    super.key,
    required this.onResume,
    this.onWatchHistoryCleared,
    this.headerFocusNode,
    this.onNavigateUpFromHeader,
    this.onNavigateDownFromCard,
  });

  @override
  State<TvContinueWatchingLane> createState() => TvContinueWatchingLaneState();
}

class TvContinueWatchingLaneState extends State<TvContinueWatchingLane> with AutomaticKeepAliveClientMixin {
  List<ContinueWatchingEntry> _entries = [];
  bool _isLoading = true;
  bool get hasEntries => !_isLoading && _entries.isNotEmpty;
  final FocusNode _headerFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<FocusNode> _itemFocusNodes = [];
  int _lastFocusedIndex = 0;
  int _lastCardRepeatMs = 0;

  FocusNode get _effectiveHeaderFocusNode => widget.headerFocusNode ?? _headerFocusNode;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final saved = PageStorage.maybeOf(context)?.readState(
      context,
      identifier: 'cw_lane_focus',
    );
    if (saved is int) _lastFocusedIndex = saved;
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

  void _onCardFocused(int index) {
    _lastFocusedIndex = index;
    PageStorage.maybeOf(context)?.writeState(
      context,
      index,
      identifier: 'cw_lane_focus',
    );
  }

  void _focusTargetCard() {
    if (_entries.isEmpty) return;

    if (_lastFocusedIndex >= 0 && _lastFocusedIndex < _entries.length) {
      final node = _getFocusNode(_lastFocusedIndex);
      if (node.parent != null) {
        node.requestFocus();
        return;
      }
    }

    int target = 0;
    if (_scrollController.hasClients) {
      target = (_scrollController.offset / 162.0).round().clamp(0, _entries.length - 1);
      final node = _getFocusNode(target);
      if (node.parent != null) {
        _onCardFocused(target);
        node.requestFocus();
        return;
      }
    }

    for (int i = 0; i < _entries.length; i++) {
      if (i < _itemFocusNodes.length && _itemFocusNodes[i].parent != null) {
        _onCardFocused(i);
        _itemFocusNodes[i].requestFocus();
        return;
      }
    }

    _onCardFocused(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _getFocusNode(target).requestFocus();
    });
  }

  FocusNode _getFocusNode(int index) {
    while (_itemFocusNodes.length <= index) {
      _itemFocusNodes.add(FocusNode());
    }
    return _itemFocusNodes[index];
  }

  KeyEventResult _handleHeaderKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _focusTargetCard();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (event is KeyDownEvent && widget.onNavigateUpFromHeader != null) {
          widget.onNavigateUpFromHeader!();
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
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
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (event is KeyDownEvent) {
          _effectiveHeaderFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (event is KeyDownEvent && widget.onNavigateDownFromCard != null) {
          widget.onNavigateDownFromCard!();
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft && index == 0) {
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
          index == _entries.length - 1) {
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (event is KeyRepeatEvent) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastCardRepeatMs < 140) return KeyEventResult.handled;
          _lastCardRepeatMs = now;
        }
      }
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
          child: TvUnifiedHeaderStrip(
            title: 'Continue Watching',
            count: _entries.length,
            focusNode: _effectiveHeaderFocusNode,
            onKeyEvent: (node, event) => _handleHeaderKeyEvent(event),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
        const SizedBox(height: 8),
        FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: SizedBox(
            height: 290,
            child: ListView.builder(
              key: const PageStorageKey('lane_continue_watching'),
              controller: _scrollController,
              clipBehavior: Clip.none,
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
                      if (focused) _onCardFocused(index);
                    },
                    onKeyEvent: (node, event) => _handleCardKeyEvent(event, index),
                    onTap: () => widget.onResume(entry),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
