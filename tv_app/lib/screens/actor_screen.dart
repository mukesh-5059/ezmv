import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/tv_focus_button.dart';
import '../widgets/tv_focus_card.dart';
import 'details_screen.dart';

class ActorScreen extends StatefulWidget {
  final int tmdbId;
  final String actorName;
  final String? profilePath;

  const ActorScreen({
    super.key,
    required this.tmdbId,
    required this.actorName,
    this.profilePath,
  });

  @override
  State<ActorScreen> createState() => _ActorScreenState();
}

class _ActorScreenState extends State<ActorScreen> {
  ActorProfile? _profile;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isFavorite = false;

  final ScrollController _scrollController = ScrollController();
  final FocusNode _favButtonFocusNode = FocusNode();
  final FocusNode _firstCardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _favButtonFocusNode.dispose();
    _firstCardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final isFav = await StorageService.instance.isActorFavorite(widget.tmdbId);
    if (mounted) setState(() => _isFavorite = isFav);

    try {
      final profile = await ApiClient.instance.getActorProfile(widget.tmdbId);
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load actor profile: $e';
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final newFav = await StorageService.instance.toggleFavoriteActor(widget.tmdbId);
    if (mounted) {
      setState(() => _isFavorite = newFav);
    }
  }

  void _navigateToDetails(MovieSummary movie) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          imdbId: movie.imdbId,
          mediaType: movie.mediaType,
          initialMovie: movie,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actorName = _profile?.name.isNotEmpty == true ? _profile!.name : widget.actorName;
    final profileUrl = _profile?.profileUrl.isNotEmpty == true
        ? _profile!.profileUrl
        : (widget.profilePath != null && widget.profilePath!.isNotEmpty
            ? 'https://image.tmdb.org/t/p/w500${widget.profilePath}'
            : '');

    return Scaffold(
      backgroundColor: TVTheme.background,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: TVTheme.primary),
            )
          : _errorMessage != null && _profile == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: TVTheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      TvFocusButton(
                        label: 'Retry',
                        onPressed: _loadData,
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: TVTheme.overscanMargin,
                    vertical: 36,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Section
                      _buildHeader(actorName, profileUrl),
                      const SizedBox(height: 36),

                      // Shelf 1: Popular Works
                      if (_profile != null && _profile!.popular.isNotEmpty) ...[
                        _buildShelf(
                          title: 'Popular Works',
                          movies: _profile!.popular,
                          isFirstShelf: true,
                        ),
                        const SizedBox(height: 32),
                      ],

                      // Shelf 2: Recent Releases
                      if (_profile != null && _profile!.recent.isNotEmpty) ...[
                        _buildShelf(
                          title: 'Recent Releases',
                          movies: _profile!.recent,
                          isFirstShelf: false,
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader(String name, String profileUrl) {
    final bio = _profile?.biography ?? '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Actor Portrait
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipOval(
            child: profileUrl.isNotEmpty
                ? Image.network(
                    profileUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: TVTheme.surfaceElevated,
                      child: const Icon(Icons.person, size: 64, color: Colors.white54),
                    ),
                  )
                : Container(
                    color: TVTheme.surfaceElevated,
                    child: const Icon(Icons.person, size: 64, color: Colors.white54),
                  ),
          ),
        ),
        const SizedBox(width: 32),

        // Info & Bio
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              if (bio.isNotEmpty) ...[
                Text(
                  bio,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: TVTheme.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  TvFocusButton(
                    focusNode: _favButtonFocusNode,
                    label: _isFavorite ? '★ Favorited' : '☆ Favorite',
                    isPrimary: _isFavorite,
                    icon: _isFavorite ? Icons.star : Icons.star_border,
                    onPressed: _toggleFavorite,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShelf({
    required String title,
    required List<MovieSummary> movies,
    required bool isFirstShelf,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 285,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: movies.length,
            itemBuilder: (context, index) {
              final movie = movies[index];
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 140,
                  child: TvFocusCard(
                    focusNode: (isFirstShelf && index == 0) ? _firstCardFocusNode : null,
                    posterUrl: movie.posterUrl,
                    title: movie.title,
                    rating: movie.ratingScore > 0 ? movie.ratingScore : null,
                    year: movie.year.isNotEmpty ? movie.year : null,
                    isTv: movie.isTv,
                    width: 140,
                    height: 210,
                    showTitleBelow: true,
                    onTap: () => _navigateToDetails(movie),
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
