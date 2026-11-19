import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../screens/actor_screen.dart';
import '../theme.dart';
import 'tv_shortcuts.dart';

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
          height: 180,
          child: ListView.builder(
            key: const PageStorageKey('details_cast_carousel'),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            cacheExtent: 220.0,
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
    if (widget.member.tmdbId <= 0) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActorScreen(
          tmdbId: widget.member.tmdbId,
          actorName: widget.member.name,
          profilePath: widget.member.profilePath,
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
        onFocusChange: (focused) {
          setState(() => _isFocused = focused);
          if (focused) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: Duration.zero,
            );
          }
        },
        onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(
          event,
          onActivate: _openActor,
        ),
        child: GestureDetector(
          onTap: _openActor,
          child: AnimatedScale(
            scale: _isFocused ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: SizedBox(
              width: 110,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isFocused ? TVTheme.primary : Colors.transparent,
                        width: 3.0,
                      ),
                      boxShadow: _isFocused
                          ? [
                              BoxShadow(
                                color: TVTheme.primary.withValues(alpha: 0.45),
                                blurRadius: 0,
                                spreadRadius: 2,
                              ),
                            ]
                          : const [],
                    ),
                    child: ClipOval(
                      child: Container(
                        color: TVTheme.surface,
                        child: member.profileUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: member.profileUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 88,
                                memCacheHeight: 88,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                errorWidget: (context, url, error) => const Icon(
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
                    member.name,
                    style: TextStyle(
                      color: _isFocused ? Colors.white : Colors.white70,
                      fontSize: 13,
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
                      fontSize: 11,
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
