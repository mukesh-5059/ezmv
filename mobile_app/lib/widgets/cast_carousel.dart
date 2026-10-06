import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../screens/actor_screen.dart';

class CastCarousel extends StatelessWidget {
  final List<CastMember> cast;

  const CastCarousel({super.key, required this.cast});

  @override
  Widget build(BuildContext context) {
    if (cast.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Cast & Crew',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: MobileTheme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
        ),
        SizedBox(
          height: 130,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: cast.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final member = cast[index];
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  if (member.id <= 0) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ActorScreen.fromActor(
                        actor: Actor(
                          id: member.id,
                          name: member.name,
                          profilePath: member.profilePath,
                        ),
                      ),
                    ),
                  );
                },
                child: SizedBox(
                  width: 80,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: MobileTheme.surfaceElevated,
                        backgroundImage: member.profileUrl.isNotEmpty
                            ? NetworkImage(member.profileUrl)
                            : null,
                        child: member.profileUrl.isEmpty
                            ? const Icon(Icons.person_rounded, color: Colors.white38, size: 28)
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        member.name,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: MobileTheme.textPrimary,
                        ),
                      ),
                      if (member.character.isNotEmpty)
                        Text(
                          member.character,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: MobileTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
