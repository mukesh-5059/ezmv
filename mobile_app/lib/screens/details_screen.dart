import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/cast_carousel.dart';
import '../widgets/stream_selector_bottom_sheet.dart';
import 'player_screen.dart';

class DetailsScreen extends StatefulWidget {
  final Movie movie;

  const DetailsScreen({super.key, required this.movie});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  MovieDetails? _details;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isOverviewExpanded = false;

  // TV Series State
  int _selectedSeasonNumber = 1;
  TvSeason? _currentSeasonData;
  bool _isLoadingSeason = false;
  Map<String, dynamic>? _tvLastWatched;
  Map<int, int> _episodeProgress = {};
  bool _isMovieWatched = false;
  Set<int> _watchedEpisodes = {};
  Map<int, bool> _seasonWatchedMap = {};
  int _savedProgressSeconds = 0;

  bool get _isTv => widget.movie.isTv || (_details?.isTv ?? false);

  @override
  void initState() {
    super.initState();
    _fetchDetails();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final pos = await LocalStorage.getProgress(widget.movie.tmdbId);
    final tvLast = await LocalStorage.getTvLastWatched(widget.movie.tmdbId);
    final isWatched = await LocalStorage.isWatched(widget.movie.tmdbId, mediaType: widget.movie.mediaType);
    if (mounted) {
      setState(() {
        _savedProgressSeconds = pos;
        _tvLastWatched = tvLast;
        _isMovieWatched = isWatched;
      });
      _loadCurrentSeasonProgress();
      _checkSeasonsWatched();
    }
  }

  Future<void> _checkSeasonsWatched() async {
    if (_details == null || _details!.seasons.isEmpty) return;
    final Map<int, bool> map = {};
    for (final s in _details!.seasons) {
      if (s.episodeCount > 0) {
        final epList = List.generate(s.episodeCount, (i) => i + 1);
        final isWatched = await LocalStorage.isSeasonWatched(widget.movie.tmdbId, s.seasonNumber, epList);
        map[s.seasonNumber] = isWatched;
      }
    }
    if (mounted) {
      setState(() {
        _seasonWatchedMap = map;
      });
    }
  }

  Future<void> _loadCurrentSeasonProgress() async {
    if (_currentSeasonData == null) return;
    final Map<int, int> progressMap = {};
    final epNums = _currentSeasonData!.episodes.map((e) => e.episodeNumber).toList();
    for (final ep in _currentSeasonData!.episodes) {
      final p = await LocalStorage.getProgress(
        widget.movie.tmdbId,
        mediaType: 'tv',
        season: _selectedSeasonNumber,
        episode: ep.episodeNumber,
      );
      if (p > 0) {
        progressMap[ep.episodeNumber] = p;
      }
    }
    final watched = await LocalStorage.getWatchedEpisodes(
      widget.movie.tmdbId,
      _selectedSeasonNumber,
      epNums,
    );
    if (mounted) {
      setState(() {
        _episodeProgress = progressMap;
        _watchedEpisodes = watched;
        if (epNums.isNotEmpty) {
          _seasonWatchedMap[_selectedSeasonNumber] = (watched.length == epNums.length);
        }
      });
    }
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final details = await ApiClient.getMovieDetails(
        widget.movie.tmdbId,
        mediaType: widget.movie.mediaType,
        fallbackMovie: widget.movie,
      );
      if (!mounted) return;

      if (details == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load details.';
        });
        return;
      }

      setState(() {
        _details = details;
        _isLoading = false;
      });

      _checkSeasonsWatched();

      if (details.isTv || details.seasons.isNotEmpty) {
        int initialSeason = 1;
        if (details.seasons.isNotEmpty) {
          final regularSeasons = details.seasons.where((s) => s.seasonNumber > 0).toList();
          if (regularSeasons.isNotEmpty) {
            initialSeason = regularSeasons.first.seasonNumber;
          } else {
            initialSeason = details.seasons.first.seasonNumber;
          }
        }
        _fetchSeasonEpisodes(initialSeason);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load details: $e';
        });
      }
    }
  }

  Future<void> _fetchSeasonEpisodes(int seasonNumber) async {
    setState(() {
      _selectedSeasonNumber = seasonNumber;
      _isLoadingSeason = true;
    });

    final seasonData = await ApiClient.getTvSeason(widget.movie.tmdbId, seasonNumber);
    if (mounted) {
      setState(() {
        _currentSeasonData = seasonData;
        _isLoadingSeason = false;
      });
      _loadCurrentSeasonProgress();
    }
  }

  Future<void> _playMovieStream({int initialSeconds = 0}) async {
    final stream = await StreamSelectorBottomSheet.show(
      context: context,
      movie: widget.movie,
      mediaType: 'movie',
    );

    if (stream != null && mounted) {
      _navigateToPlayer(stream, initialSeconds: initialSeconds);
    }
  }

  Future<void> _playEpisodeStream(TvEpisode episode) async {
    final stream = await StreamSelectorBottomSheet.show(
      context: context,
      movie: widget.movie,
      title: '${widget.movie.title} - S${_selectedSeasonNumber}E${episode.episodeNumber}: ${episode.name}',
      mediaType: 'tv',
      season: _selectedSeasonNumber,
      episode: episode.episodeNumber,
    );

    if (stream != null && mounted) {
      final savedPos = _episodeProgress[episode.episodeNumber] ?? 0;
      _navigateToPlayer(
        stream,
        mediaType: 'tv',
        season: _selectedSeasonNumber,
        episode: episode.episodeNumber,
        overrideTitle: '${widget.movie.title} - S${_selectedSeasonNumber.toString().padLeft(2, '0')}E${episode.episodeNumber.toString().padLeft(2, '0')}: ${episode.name}',
        initialSeconds: savedPos,
      );
    }
  }

  void _navigateToPlayer(
    Map<String, dynamic> stream, {
    String mediaType = 'movie',
    int? season,
    int? episode,
    String? overrideTitle,
    int initialSeconds = 0,
  }) {
    LocalStorage.addToHistory(widget.movie);

    final rawHeaders = stream['headers'];
    Map<String, String>? headers;
    if (rawHeaders is Map) {
      headers = rawHeaders.map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    final provider = stream['provider']?.toString() ?? 'Direct';
    final quality = stream['quality']?.toString() ?? '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          streamUrl: stream['url'] ?? '',
          headers: headers,
          movieTitle: overrideTitle ?? widget.movie.title,
          tmdbId: widget.movie.tmdbId,
          mediaType: mediaType,
          season: season,
          episode: episode,
          provider: provider,
          quality: quality,
          initialPositionSeconds: initialSeconds,
        ),
      ),
    ).then((_) => _loadProgress());
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.movie.title)),
        body: const Center(
          child: CircularProgressIndicator(color: MobileTheme.accent),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.movie.title)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: MobileTheme.accent),
                onPressed: _fetchDetails,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final backdropUrl = _details?.backdropUrl.isNotEmpty == true
        ? _details!.backdropUrl
        : widget.movie.backdropUrl;
    final posterUrl = _details?.posterUrl.isNotEmpty == true
        ? _details!.posterUrl
        : widget.movie.posterUrl;
    final title = _details?.title ?? widget.movie.title;
    final overview = _details?.overview.isNotEmpty == true
        ? _details!.overview
        : widget.movie.overview;
    final releaseYear = _details?.releaseYear.isNotEmpty == true
        ? _details!.releaseYear
        : widget.movie.year;
    final rating = _details?.voteAverage ?? widget.movie.voteAverage;
    final genres = _details?.genres ?? [];

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Collapsible Backdrop Header
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: MobileTheme.background,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  backdropUrl.isNotEmpty
                      ? Image.network(
                          backdropUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: MobileTheme.surfaceElevated),
                        )
                      : Container(color: MobileTheme.surfaceElevated),
                  // Gradient Overlay
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.3),
                            Colors.transparent,
                            MobileTheme.background.withValues(alpha: 0.8),
                            MobileTheme.background,
                          ],
                          stops: const [0.0, 0.4, 0.85, 1.0],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Main Details Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Metadata
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Poster Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 85,
                          height: 125,
                          child: posterUrl.isNotEmpty
                              ? Image.network(
                                  posterUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(color: MobileTheme.surfaceElevated),
                                )
                              : Container(color: MobileTheme.surfaceElevated),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                            if (_details?.tagline?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 4),
                              Text(
                                '"${_details!.tagline}"',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (releaseYear.isNotEmpty)
                                  _buildBadge(Icons.calendar_today_rounded, releaseYear),
                                if (!_isTv && _details?.formattedRuntime.isNotEmpty == true)
                                  _buildBadge(Icons.timer_outlined, _details!.formattedRuntime),
                                if (_isTv && _details != null && _details!.numberOfSeasons > 0)
                                  _buildBadge(Icons.layers_outlined, '${_details!.numberOfSeasons} ${_details!.numberOfSeasons == 1 ? "Season" : "Seasons"}'),
                                if (rating > 0)
                                  _buildBadge(Icons.star_rounded, rating.toStringAsFixed(1), iconColor: Colors.amber),
                                if (!_isTv && _isMovieWatched)
                                  _buildBadge(Icons.check_circle_rounded, 'Watched', iconColor: MobileTheme.accent),
                              ],
                            ),
                            if (genres.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                genres.map((g) => g.name).join(' • '),
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Action Buttons (Play / Resume)
                  if (!_isTv) ...[
                    if (_savedProgressSeconds > 15) ...[
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: MobileTheme.accent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                                label: Text(
                                  'Resume (${_formatTime(_savedProgressSeconds)})',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => _playMovieStream(initialSeconds: _savedProgressSeconds),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 46,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24, width: 1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.replay_rounded, size: 20),
                              label: const Text('Start Over', style: TextStyle(fontSize: 14)),
                              onPressed: () async {
                                await LocalStorage.clearProgress(widget.movie.tmdbId);
                                setState(() => _savedProgressSeconds = 0);
                                _playMovieStream(initialSeconds: 0);
                              },
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: MobileTheme.accent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 24),
                          label: const Text(
                            'Play Movie',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => _playMovieStream(initialSeconds: 0),
                        ),
                      ),
                    ],
                  ] else if (_tvLastWatched != null && (_tvLastWatched!['position'] as int? ?? 0) > 15) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: MobileTheme.accent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 24),
                        label: Text(
                          'Resume S${_tvLastWatched!['season']}E${_tvLastWatched!['episode']} (${_formatTime(_tvLastWatched!['position'] as int)})',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          if (_currentSeasonData != null) {
                            final targetEp = _currentSeasonData!.episodes.cast<TvEpisode?>().firstWhere(
                                  (e) => e?.episodeNumber == _tvLastWatched!['episode'],
                                  orElse: () => null,
                                );
                            if (targetEp != null) {
                              _playEpisodeStream(targetEp);
                            }
                          }
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Overview Text
                  if (overview.isNotEmpty)
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _isOverviewExpanded = !_isOverviewExpanded),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            overview,
                            maxLines: _isOverviewExpanded ? null : 3,
                            overflow: _isOverviewExpanded ? null : TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isOverviewExpanded ? 'Show less' : 'Read more',
                            style: const TextStyle(color: MobileTheme.accent, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // Cast Carousel
          if (_details != null && _details!.cast.isNotEmpty)
            SliverToBoxAdapter(
              child: CastCarousel(cast: _details!.cast),
            ),

          // TV Seasons & Episodes Section
          if (_isTv) ...[
            SliverToBoxAdapter(
              child: _buildTvSeasonsSection(),
            ),
            if (_isLoadingSeason)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator(color: MobileTheme.accent)),
                ),
              )
            else if (_currentSeasonData == null || _currentSeasonData!.episodes.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('No episodes found for this season.', style: TextStyle(color: Colors.white54)),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final ep = _currentSeasonData!.episodes[index];
                      return _buildEpisodeTile(ep);
                    },
                    childCount: _currentSeasonData!.episodes.length,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, {Color? iconColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: MobileTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: iconColor ?? Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildTvSeasonsSection() {
    final seasons = _details?.seasons ?? [];
    if (seasons.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Seasons & Episodes',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: MobileTheme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: seasons.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final season = seasons[index];
                final isSelected = season.seasonNumber == _selectedSeasonNumber;
                final isSeasonComplete = _seasonWatchedMap[season.seasonNumber] ?? false;

                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSeasonComplete) ...[
                        Icon(Icons.check_circle_rounded, size: 13, color: isSelected ? Colors.white : MobileTheme.accent),
                        const SizedBox(width: 4),
                      ],
                      Text(season.name.isNotEmpty ? season.name : 'Season ${season.seasonNumber}'),
                    ],
                  ),
                  selected: isSelected,
                  selectedColor: MobileTheme.accent,
                  backgroundColor: MobileTheme.surfaceElevated,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  side: BorderSide.none,
                  onSelected: (selected) {
                    if (selected && _selectedSeasonNumber != season.seasonNumber) {
                      _fetchSeasonEpisodes(season.seasonNumber);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeTile(TvEpisode episode) {
    final progressSecs = _episodeProgress[episode.episodeNumber] ?? 0;
    final isEpisodeWatched = _watchedEpisodes.contains(episode.episodeNumber);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: MobileTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _playEpisodeStream(episode),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Still / Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 58,
                        color: const Color(0xFF222228),
                        child: episode.stillUrl.isNotEmpty
                            ? Image.network(
                                episode.stillUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.tv_rounded, color: Colors.white30, size: 24),
                                ),
                              )
                            : const Center(
                                child: Icon(Icons.tv_rounded, color: Colors.white30, size: 24),
                              ),
                      ),
                      Positioned(
                        bottom: progressSecs > 15 ? 6 : 3,
                        left: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'EP ${episode.episodeNumber}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      if (isEpisodeWatched)
                        Positioned(
                          top: 3,
                          right: 3,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              size: 12,
                              color: MobileTheme.accent,
                            ),
                          ),
                        ),
                      if (progressSecs > 15)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2.5,
                            color: Colors.white24,
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: ((episode.runtime != null && episode.runtime! > 0)
                                      ? (progressSecs / (episode.runtime! * 60))
                                      : 0.5)
                                  .clamp(0.0, 1.0),
                              child: Container(color: MobileTheme.accent),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              episode.name.isNotEmpty
                                  ? '${episode.episodeNumber}. ${episode.name}'
                                  : 'Episode ${episode.episodeNumber}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (episode.formattedRuntime.isNotEmpty)
                            Text(
                              episode.formattedRuntime,
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          if (episode.voteAverage > 0) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              episode.voteAverage.toStringAsFixed(1),
                              style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                          if (isEpisodeWatched) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: MobileTheme.accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: MobileTheme.accent.withValues(alpha: 0.6), width: 0.8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_rounded, size: 10, color: MobileTheme.accent),
                                  SizedBox(width: 3),
                                  Text(
                                    'Watched',
                                    style: TextStyle(
                                      color: MobileTheme.accent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (progressSecs > 15) ...[
                            const SizedBox(width: 6),
                            Text(
                              'Resume ${_formatTime(progressSecs)}',
                              style: const TextStyle(color: MobileTheme.accent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ],
                      ),
                      if (episode.overview.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          episode.overview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.play_circle_outline_rounded, color: MobileTheme.accent, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
