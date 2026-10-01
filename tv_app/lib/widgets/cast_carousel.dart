import 'package:flutter/material.dart';
import '../models/movie_details.model.dart';
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

  @override
  Widget build(BuildContext context) {
    final member = widget.member;

    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Focus(
        onFocusChange: (focused) => setState(() => _isFocused = focused),
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
                              color: TVTheme.accent.withOpacity(0.5),
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
    );
  }
}
