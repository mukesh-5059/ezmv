import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';

class ActorLane extends StatelessWidget {
  final String rowKey;
  final String title;
  final List<Actor> actors;
  final void Function(Actor actor) onActorTap;
  final void Function(Actor actor)? onActorFocused;
  final FocusNode Function(String rowKey, int index) getFocusNode;
  final KeyEventResult Function(String rowKey, int index, int itemCount, RawKeyEvent event) onKeyNav;
  final void Function(String rowKey, int index) onFocusedIndexChanged;

  const ActorLane({
    super.key,
    required this.rowKey,
    required this.title,
    required this.actors,
    required this.onActorTap,
    this.onActorFocused,
    required this.getFocusNode,
    required this.onKeyNav,
    required this.onFocusedIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (actors.isEmpty) {
      return SizedBox.shrink(key: ValueKey('${rowKey}_empty'));
    }

    final itemCount = actors.length;

    return Builder(
      builder: (rowContext) {
        return Column(
          key: ValueKey(rowKey),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 24.0, top: 16.0, bottom: 6.0),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            SizedBox(
              height: 180,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  final actor = actors[index];
                  final node = getFocusNode(rowKey, index);
                  return _ActorCardItem(
                    key: ValueKey('${rowKey}_${actor.id}_$index'),
                    actor: actor,
                    focusNode: node,
                    onFocusChanged: (focused) {
                      if (focused) {
                        onActorFocused?.call(actor);
                        onFocusedIndexChanged(rowKey, index);
                        if (node.context != null) {
                          Scrollable.ensureVisible(
                            node.context!,
                            duration: const Duration(milliseconds: 250),
                            alignment: 0.5,
                            curve: Curves.easeInOut,
                          );
                        }
                      }
                    },
                    onKey: (node, event) => onKeyNav(rowKey, index, itemCount, event),
                    onTap: () => onActorTap(actor),
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

class _ActorCardItem extends StatefulWidget {
  final Actor actor;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChanged;
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, RawKeyEvent)? onKey;

  const _ActorCardItem({
    super.key,
    required this.actor,
    required this.onTap,
    this.onFocusChanged,
    required this.focusNode,
    this.onKey,
  });

  @override
  State<_ActorCardItem> createState() => _ActorCardItemState();
}

class _ActorCardItemState extends State<_ActorCardItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final actor = widget.actor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) {
          setState(() => _isFocused = focused);
          widget.onFocusChanged?.call(focused);
        },
        onKey: (node, event) {
          if (event is RawKeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              widget.onTap();
              return KeyEventResult.handled;
            }
          }
          if (widget.onKey != null) {
            return widget.onKey!(node, event);
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isFocused ? 1.10 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: SizedBox(
              width: 110,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isFocused ? TVTheme.accent : Colors.white24,
                        width: _isFocused ? 3.0 : 1.0,
                      ),
                      boxShadow: _isFocused
                          ? [
                              BoxShadow(
                                color: TVTheme.accent.withValues(alpha: 0.25),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.8),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                    ),
                    child: ClipOval(
                      child: Container(
                        color: TVTheme.surfaceElevated,
                        child: actor.profileUrl.isNotEmpty
                            ? Image.network(
                                actor.profileUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person,
                                  color: Colors.white54,
                                  size: 44,
                                ),
                              )
                            : const Icon(
                                Icons.person,
                                color: Colors.white54,
                                size: 44,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    actor.name,
                    style: TextStyle(
                      color: _isFocused ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: _isFocused ? FontWeight.bold : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
