import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie_details.model.dart';
import '../screens/actor_screen.dart';
import '../theme.dart';

class CastCarousel extends StatelessWidget {
  final List<CastMember> cast;

  const CastCarousel({super.key, required this.cast});

  @override
  Widget build(BuildContext context) {
    if (cast.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cast & Crew',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 145,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: cast.length,
            itemBuilder: (context, index) {
              return _CastCard(member: cast[index]);
            },
          ),
        ),
      ],
    );
  }
}

class _CastCard extends StatefulWidget {
  final CastMember member;

  const _CastCard({required this.member});

  @override
  State<_CastCard> createState() => _CastCardState();
}

class _CastCardState extends State<_CastCard> {
  bool _isFocused = false;

  void _openActor() {
    if (widget.member.id <= 0) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActorScreen(
          actorId: widget.member.id,
          initialActorName: widget.member.name,
          initialProfilePath: widget.member.profilePath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;

    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Focus(
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        onKey: (node, event) {
          if (event is RawKeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              _openActor();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: _openActor,
          child: AnimatedScale(
            scale: _isFocused ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: SizedBox(
              width: 88,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isFocused ? TVTheme.accent : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: _isFocused
                          ? [
                              BoxShadow(
                                color: TVTheme.accent.withValues(alpha: 0.5),
                                blurRadius: 14,
                                spreadRadius: 2,
                              ),
                            ]
                          : [],
                    ),
                    child: ClipOval(
                      child: Container(
                        color: TVTheme.surface,
                        child: member.profileUrl.isNotEmpty
                            ? Image.network(
                                member.profileUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person,
                                  color: Colors.white54,
                                  size: 36,
                                ),
                              )
                            : const Icon(
                                Icons.person,
                                color: Colors.white54,
                                size: 36,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    member.name,
                    style: TextStyle(
                      color: _isFocused ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight: _isFocused ? FontWeight.bold : FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    member.character,
                    style: const TextStyle(
                      color: TVTheme.textSecondary,
                      fontSize: 10,
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
