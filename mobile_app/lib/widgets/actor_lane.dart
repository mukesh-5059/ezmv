import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../screens/actor_screen.dart';

class ActorLane extends StatelessWidget {
  final String title;
  final List<Actor> actors;

  const ActorLane({
    super.key,
    required this.title,
    required this.actors,
  });

  @override
  Widget build(BuildContext context) {
    if (actors.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: MobileTheme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: actors.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final actor = actors[index];
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ActorScreen.fromActor(actor: actor),
                    ),
                  );
                },
                child: SizedBox(
                  width: 76,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: MobileTheme.surfaceElevated,
                        backgroundImage: actor.profileUrl.isNotEmpty
                            ? NetworkImage(actor.profileUrl)
                            : null,
                        child: actor.profileUrl.isEmpty
                            ? const Icon(Icons.person_rounded, color: Colors.white38, size: 30)
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        actor.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: MobileTheme.textPrimary,
                          height: 1.1,
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
