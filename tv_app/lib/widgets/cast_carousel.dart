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
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: cast.length,
            itemBuilder: (context, index) {
              final member = cast[index];
              return Container(
                width: 90,
                margin: const EdgeInsets.only(right: 14),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(45),
                      child: Container(
                        width: 70,
                        height: 70,
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
                    const SizedBox(height: 8),
                    Text(
                      member.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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
              );
            },
          ),
        ),
      ],
    );
  }
}
