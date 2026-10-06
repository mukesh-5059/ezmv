import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/movie_lane.dart';

class ActorScreen extends StatefulWidget {
  final int actorId;
  final String? initialActorName;
  final String? initialProfilePath;

  const ActorScreen({
    super.key,
    required this.actorId,
    this.initialActorName,
    this.initialProfilePath,
  });

  ActorScreen.fromActor({
    super.key,
    required Actor actor,
  })  : actorId = actor.id,
        initialActorName = actor.name,
        initialProfilePath = actor.profilePath;

  @override
  State<ActorScreen> createState() => _ActorScreenState();
}

class _ActorScreenState extends State<ActorScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  ActorFilmography? _filmography;
  bool _isBioExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadFilmography();
  }

  Future<void> _loadFilmography() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final filmography = await ApiClient.getActorFilmography(widget.actorId);
      if (!mounted) return;

      if (filmography == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load actor details.';
        });
        return;
      }

      setState(() {
        _filmography = filmography;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load details: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final actorName = _filmography?.name ?? widget.initialActorName ?? 'Actor';
    final profileUrl = _filmography?.profileUrl.isNotEmpty == true
        ? _filmography!.profileUrl
        : (widget.initialProfilePath != null && widget.initialProfilePath!.isNotEmpty
            ? 'https://image.tmdb.org/t/p/w500${widget.initialProfilePath}'
            : '');

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // App Bar
          SliverAppBar(
            pinned: true,
            title: Text(actorName),
            backgroundColor: MobileTheme.background,
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: MobileTheme.accent),
              ),
            )
          else if (_errorMessage != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.white38, size: 48),
                    const SizedBox(height: 12),
                    Text(_errorMessage!, style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _loadFilmography,
                      style: FilledButton.styleFrom(backgroundColor: MobileTheme.accent),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Profile & Bio Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 46,
                      backgroundColor: MobileTheme.surfaceElevated,
                      backgroundImage: profileUrl.isNotEmpty ? NetworkImage(profileUrl) : null,
                      child: profileUrl.isEmpty
                          ? const Icon(Icons.person_rounded, size: 40, color: Colors.white38)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _filmography!.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          if (_filmography!.knownForDepartment.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              _filmography!.knownForDepartment,
                              style: const TextStyle(color: MobileTheme.accent, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                          if ((_filmography!.placeOfBirth?.isNotEmpty ?? false) ||
                              (_filmography!.birthday?.isNotEmpty ?? false)) ...[
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (_filmography!.birthday?.isNotEmpty ?? false) _filmography!.birthday!,
                                if (_filmography!.placeOfBirth?.isNotEmpty ?? false) _filmography!.placeOfBirth!,
                              ].join(' • '),
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Biography
            if (_filmography!.biography.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: InkWell(
                    onTap: () => setState(() => _isBioExpanded = !_isBioExpanded),
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _filmography!.biography,
                          maxLines: _isBioExpanded ? null : 4,
                          overflow: _isBioExpanded ? null : TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isBioExpanded ? 'Show less' : 'Read more',
                          style: const TextStyle(
                            color: MobileTheme.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            // Known For & Popular Filmography
            if (_filmography!.popular.isNotEmpty)
              SliverToBoxAdapter(
                child: MovieLane(
                  title: 'Popular Works',
                  movies: _filmography!.popular,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            // Recent Filmography
            if (_filmography!.recent.isNotEmpty)
              SliverToBoxAdapter(
                child: MovieLane(
                  title: 'Recent Releases',
                  movies: _filmography!.recent,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ],
      ),
    );
  }
}
