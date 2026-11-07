import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import '../../theme.dart';
import '../tv_shortcuts.dart';
import '../tv_unified_header_strip.dart';

/// Bottom Shelf Actors Lane for Tamil Dashboard.
///
/// Features:
/// - Only rendered when active dashboard is `tamil`.
/// - Queries favorite actors from [StorageService.instance.getFavoriteActorIds],
///   falling back to default actor catalog from [ApiClient.instance.getActors].
/// - 80dp circular portrait cards with name label beneath.
/// - 10-foot TV focus scale (1.1x) with high-contrast border and ambient halo.
/// - Selecting an actor triggers [onActorTap].
class TvActorsLane extends StatefulWidget {
  final void Function(ActorSummary actor) onActorTap;
  final FocusNode? headerFocusNode;
  final VoidCallback? onNavigateUpFromHeader;

  const TvActorsLane({
    super.key,
    required this.onActorTap,
    this.headerFocusNode,
    this.onNavigateUpFromHeader,
  });

  @override
  State<TvActorsLane> createState() => _TvActorsLaneState();
}

class _TvActorsLaneState extends State<TvActorsLane>
    with AutomaticKeepAliveClientMixin {
  List<ActorSummary> _actors = [];
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
    _loadActors();
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

  Future<void> _loadActors() async {
    try {
      final allActors = await ApiClient.instance.getActors();
      final favIds = await StorageService.instance.getFavoriteActorIds();

      List<ActorSummary> displayActors;
      if (favIds.isNotEmpty) {
        // Prioritize favorite actors, then append the rest
        final favs = allActors.where((a) => favIds.contains(a.tmdbId)).toList();
        final others = allActors.where((a) => !favIds.contains(a.tmdbId)).toList();
        displayActors = [...favs, ...others];
      } else {
        displayActors = allActors;
      }

      if (mounted) {
        setState(() {
          _actors = displayActors;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _actors = [];
          _isLoading = false;
        });
      }
    }
  }

  FocusNode get _effectiveHeaderFocusNode => widget.headerFocusNode ?? _headerFocusNode;

  KeyEventResult _handleHeaderKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (_actors.isNotEmpty) {
          final targetIndex = _lastFocusedIndex.clamp(0, _actors.length - 1);
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

  KeyEventResult _handleCardKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _effectiveHeaderFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading || _actors.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TVTheme.overscanMargin),
          child: TvUnifiedHeaderStrip(
            title: 'Popular Tamil Actors',
            count: _actors.length,
            focusNode: _effectiveHeaderFocusNode,
            onKeyEvent: (node, event) => _handleHeaderKeyEvent(event),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 155,
          child: ListView.builder(
            key: const PageStorageKey('lane_tamil_actors'),
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: TVTheme.overscanMargin),
            itemCount: _actors.length,
            itemBuilder: (context, index) {
              final actor = _actors[index];

              return Padding(
                padding: const EdgeInsets.only(right: 18),
                child: _ActorCircleCard(
                  focusNode: _getFocusNode(index),
                  actor: actor,
                  onFocusChanged: (focused) {
                    if (focused) _lastFocusedIndex = index;
                  },
                  onKeyEvent: (node, event) => _handleCardKeyEvent(event),
                  onTap: () => widget.onActorTap(actor),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _ActorCircleCard extends StatefulWidget {
  final FocusNode focusNode;
  final ActorSummary actor;
  final ValueChanged<bool> onFocusChanged;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final VoidCallback onTap;

  const _ActorCircleCard({
    required this.focusNode,
    required this.actor,
    required this.onFocusChanged,
    required this.onKeyEvent,
    required this.onTap,
  });

  @override
  State<_ActorCircleCard> createState() => _ActorCircleCardState();
}

class _ActorCircleCardState extends State<_ActorCircleCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: Duration.zero,
          );
        }
        widget.onFocusChanged(focused);
      },
      onKeyEvent: (node, event) {
        final res = widget.onKeyEvent(node, event);
        if (res != KeyEventResult.ignored) return res;
        return TvShortcuts.handleKeyEvent(event, onActivate: widget.onTap);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.10 : 1.0,
          duration: TVTheme.focusDuration,
          curve: TVTheme.focusCurve,
          child: SizedBox(
            width: 96,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: TVTheme.surfaceElevated,
                    border: Border.all(
                      color: _isFocused ? Colors.white : Colors.transparent,
                      width: TVTheme.focusBorderWidth,
                    ),
                    boxShadow: _isFocused
                        ? [
                            ...TVTheme.focusShadows,
                            BoxShadow(
                              color: TVTheme.accentGlow.withValues(alpha: 0.35),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ]
                        : TVTheme.restingShadows,
                  ),
                  child: ClipOval(
                    child: widget.actor.profileUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.actor.profileUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 160,
                            memCacheHeight: 160,
                            placeholder: (context, url) => Container(
                              color: TVTheme.surface,
                              child: const Icon(
                                Icons.person_rounded,
                                size: 36,
                                color: TVTheme.textSecondary,
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: TVTheme.surface,
                              child: const Icon(
                                Icons.person_rounded,
                                size: 36,
                                color: TVTheme.textSecondary,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.person_rounded,
                            size: 36,
                            color: TVTheme.textSecondary,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.actor.name,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _isFocused ? FontWeight.w700 : FontWeight.w500,
                    color: _isFocused ? TVTheme.textPrimary : TVTheme.textSecondary,
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
