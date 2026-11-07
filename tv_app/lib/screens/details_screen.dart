import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/cast_carousel.dart';
import '../widgets/episode_stream_dialog.dart';
import '../widgets/stream_selector.dart';
import '../widgets/tv_focus_button.dart';
import '../widgets/tv_shortcuts.dart';
import 'player_screen.dart';

class DetailsScreen extends StatefulWidget {
  final String imdbId;
  final String mediaType;
  final int? tmdbId;
  final MovieSummary? initialMovie;

  DetailsScreen({
    super.key,
    String? imdbId,
    String? mediaType,
    int? tmdbId,
    MovieSummary? movie,
    MovieSummary? initialMovie,
  })  : imdbId = imdbId ?? movie?.imdbId ?? initialMovie?.imdbId ?? '',
        mediaType = mediaType ?? movie?.mediaType ?? initialMovie?.mediaType ?? 'movie',
        tmdbId = tmdbId ?? movie?.tmdbId ?? initialMovie?.tmdbId,
        initialMovie = initialMovie ?? movie;

  factory DetailsScreen.fromMovie(MovieSummary movie, {Key? key}) {
    return DetailsScreen(
      key: key,
      imdbId: movie.imdbId,
      mediaType: movie.mediaType,
      tmdbId: movie.tmdbId,
      initialMovie: movie,
    );
  }

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  MovieDetails? _details;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isInWatchlist = false;

  // Streams state
  List<StreamSource> _streams = [];

  // TV state
  int _selectedSeasonNumber = 1;
  TvSeason? _currentSeason;
  bool _isLoadingSeason = false;

  final ScrollController _scrollController = ScrollController();
  final FocusNode _playButtonFocusNode = FocusNode();
  final FocusNode _watchlistButtonFocusNode = FocusNode();
  final FocusNode _sourcesButtonFocusNode = FocusNode();

  bool get _isTv => widget.mediaType == 'tv';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _playButtonFocusNode.dispose();
    _watchlistButtonFocusNode.dispose();
    _sourcesButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    // Check watchlist status
    if (widget.imdbId.isNotEmpty) {
      final isWatchlisted = await StorageService.instance.isWatchlisted(widget.imdbId);
      if (mounted) setState(() => _isInWatchlist = isWatchlisted);
    }

    try {
      final id = (widget.tmdbId != null && widget.tmdbId! > 0)
          ? widget.tmdbId
          : (widget.initialMovie?.tmdbId != null && widget.initialMovie!.tmdbId! > 0)
              ? widget.initialMovie!.tmdbId
              : widget.imdbId;
      final details = await ApiClient.instance.getMovieDetails(
        widget.mediaType,
        id,
        initialMovie: widget.initialMovie,
      );
      if (mounted) {
        setState(() {
          _details = details;
          _isLoading = false;
        });

        // If TV, load initial season
        if (_isTv && details.seasons.isNotEmpty) {
          final firstSeasonNum = details.seasons.first.seasonNumber;
          final resolvedTmdbId = details.tmdbId ?? widget.tmdbId ?? widget.initialMovie?.tmdbId ?? 0;
          _loadSeason(firstSeasonNum, resolvedTmdbId);
        }
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

  Future<void> _loadSeason(int seasonNum, int tmdbId) async {
    if (tmdbId <= 0) return;
    setState(() {
      _selectedSeasonNumber = seasonNum;
      _isLoadingSeason = true;
    });

    try {
      final season = await ApiClient.instance.getTvSeason(tmdbId, seasonNum);
      if (mounted) {
        setState(() {
          _currentSeason = season;
          _isLoadingSeason = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingSeason = false);
    }
  }

  Future<void> _toggleWatchlist() async {
    final movie = _details ?? widget.initialMovie;
    if (movie == null) return;
    final inList = await StorageService.instance.toggleWatchlist(movie);
    if (mounted) {
      setState(() => _isInWatchlist = inList);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(inList ? 'Added to Watchlist' : 'Removed from Watchlist'),
          backgroundColor: inList ? Colors.green.shade800 : Colors.red.shade800,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  DateTime? _lastResumedFromPlayerAt;

  Future<void> _playTopStream() async {
    if (_streams.isNotEmpty) {
      _launchPlayer(_streams.first, _streams);
      return;
    }

    final selected = await StreamSelector.showModal(
      context: context,
      title: _details?.title ?? widget.initialMovie?.title ?? 'Playback',
      streams: _streams,
      imdbId: widget.imdbId,
      mediaType: widget.mediaType,
      autoPlay: true,
      onStreamsLoaded: (streams) {
        if (mounted) setState(() => _streams = streams);
      },
      onError: (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to fetch streams: $err'),
              backgroundColor: Colors.red.shade800,
            ),
          );
        }
      },
    );

    if (selected != null && mounted) {
      _launchPlayer(selected, _streams);
    }
  }

  void _openManualSources() async {
    final selected = await StreamSelector.showModal(
      context: context,
      title: _details?.title ?? widget.initialMovie?.title ?? 'Playback',
      streams: _streams,
      imdbId: widget.imdbId,
      mediaType: widget.mediaType,
      autoPlay: false,
      onStreamsLoaded: (streams) {
        if (mounted) setState(() => _streams = streams);
      },
    );

    if (selected != null && mounted) {
      _launchPlayer(selected, _streams);
    }
  }

  Future<void> _launchPlayer(StreamSource stream, List<StreamSource> allStreams, {int? season, int? episode}) async {
    final title = _details?.title ?? widget.initialMovie?.title ?? 'Playback';
    final poster = _details?.posterPath ?? widget.initialMovie?.posterPath;
    final backdrop = _details?.backdropPath ?? widget.initialMovie?.backdropPath;

    int initialPosSec = 0;
    try {
      final savedEntry = await StorageService.instance.getContinueWatchingEntry(widget.imdbId);
      if (savedEntry != null && savedEntry.progress < 0.92) {
        if (!_isTv || (savedEntry.season == season && savedEntry.episode == episode)) {
          initialPosSec = savedEntry.positionMs ~/ 1000;
        }
      }
    } catch (_) {}

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: stream.url,
          headers: stream.headers,
          movieTitle: title,
          imdbId: widget.imdbId,
          tmdbId: _details?.tmdbId ?? widget.initialMovie?.tmdbId,
          mediaType: widget.mediaType,
          season: season,
          episode: episode,
          initialPositionSeconds: initialPosSec,
          posterPath: poster,
          backdropPath: backdrop,
          availableStreams: allStreams,
          provider: stream.provider,
          quality: stream.quality,
          seasons: _details?.seasons,
        ),
      ),
    );
    _lastResumedFromPlayerAt = DateTime.now();
  }

  void _playEpisode(TvEpisode episode) async {
    final showTitle = _details?.title ?? widget.initialMovie?.title ?? 'TV Show';
    showDialog(
      context: context,
      builder: (ctx) => EpisodeStreamDialog(
        imdbId: widget.imdbId,
        showTitle: showTitle,
        seasonNumber: _selectedSeasonNumber,
        episode: episode,
        onStreamSelected: (stream) {
          _launchPlayer(
            stream,
            [stream],
            season: _selectedSeasonNumber,
            episode: episode.episodeNumber,
          );
        },
        onStreamSelectedWithAll: (stream, allStreams) {
          _launchPlayer(
            stream,
            allStreams,
            season: _selectedSeasonNumber,
            episode: episode.episodeNumber,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _details?.title ?? widget.initialMovie?.title ?? '';
    final backdropUrl = _details?.backdropUrl.isNotEmpty == true
        ? _details!.backdropUrl
        : (widget.initialMovie?.backdropUrl ?? '');
    final posterUrl = _details?.posterUrl.isNotEmpty == true
        ? _details!.posterUrl
        : (widget.initialMovie?.posterUrl ?? '');
    final rating = _details?.ratingScore ?? widget.initialMovie?.ratingScore ?? 0.0;
    final voteCount = _details?.voteCount ?? widget.initialMovie?.voteCount ?? 0;
    final year = _details?.year.isNotEmpty == true
        ? _details!.year
        : (widget.initialMovie?.year ?? '');
    final runtime = _details?.formattedRuntime ?? '';
    final overview = _details?.overview.isNotEmpty == true
        ? _details!.overview
        : (widget.initialMovie?.overview ?? '');
    final genres = _details?.genreNamesString ??
        widget.initialMovie?.genres.map((g) => g.name).join(', ') ?? '';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastResumedFromPlayerAt != null &&
            now.difference(_lastResumedFromPlayerAt!).inMilliseconds < 500) {
          return;
        }
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      backgroundColor: TVTheme.background,
      body: _isLoading && _details == null && widget.initialMovie == null
          ? const Center(
              child: CircularProgressIndicator(color: TVTheme.primary),
            )
          : _errorMessage != null && _details == null && widget.initialMovie == null
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
                        onPressed: _loadInitialData,
                      ),
                    ],
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
          // Background Backdrop Layer
          if (backdropUrl.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: backdropUrl,
                fit: BoxFit.cover,
                memCacheWidth: 1280,
                memCacheHeight: 720,
                maxWidthDiskCache: 1280,
                maxHeightDiskCache: 720,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),

          // Dark Gradient Scrim Layer
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.82),
                    TVTheme.background,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // Main Scrollable Content
          SafeArea(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(
                horizontal: TVTheme.overscanMargin,
                vertical: 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Poster & Metadata
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Poster
                      if (posterUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: TVTheme.borderRadiusMd,
                          child: Container(
                            width: 200,
                            height: 300,
                            color: TVTheme.surface,
                            child: CachedNetworkImage(
                              imageUrl: posterUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 400,
                              memCacheHeight: 600,
                              maxWidthDiskCache: 400,
                              maxHeightDiskCache: 600,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              errorWidget: (_, __, ___) => const Center(
                                child: Icon(Icons.movie, size: 54, color: Colors.white38),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 36),

                      // Metadata column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 38,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -0.6,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Badges Row
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                if (rating > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF5C518),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star, size: 14, color: Colors.black),
                                        const SizedBox(width: 4),
                                        Text(
                                          rating.toStringAsFixed(1),
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (voteCount > 0)
                                  Text(
                                    '($voteCount votes)',
                                    style: const TextStyle(color: TVTheme.textSecondary, fontSize: 13),
                                  ),
                                if (year.isNotEmpty)
                                  Text(
                                    year,
                                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                                  ),
                                if (runtime.isNotEmpty)
                                  Text(
                                    runtime,
                                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.white38),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    widget.mediaType.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Genres
                            if (genres.isNotEmpty)
                              Text(
                                genres,
                                style: const TextStyle(
                                  color: TVTheme.textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            const SizedBox(height: 14),

                            // Overview
                            if (overview.isNotEmpty)
                              Text(
                                overview,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  height: 1.45,
                                ),
                              ),
                            const SizedBox(height: 24),

                            // Action Buttons Row
                            Row(
                              children: [
                                TvFocusButton(
                                  focusNode: _playButtonFocusNode,
                                  autofocus: true,
                                  label: _isTv ? '⚡ Browse Episodes' : '⚡ Play Now',
                                  isPrimary: true,
                                  icon: Icons.play_arrow,
                                  onPressed: () {
                                    if (_isTv) {
                                      _scrollController.jumpTo(340);
                                    } else {
                                      _playTopStream();
                                    }
                                  },
                                ),
                                const SizedBox(width: 16),
                                TvFocusButton(
                                  focusNode: _watchlistButtonFocusNode,
                                  label: _isInWatchlist ? '✓ In Watchlist' : '➕ Watchlist',
                                  isPrimary: false,
                                  icon: _isInWatchlist ? Icons.check : Icons.bookmark_add_outlined,
                                  onPressed: _toggleWatchlist,
                                ),
                                const SizedBox(width: 16),
                                if (!_isTv)
                                  TvFocusButton(
                                    focusNode: _sourcesButtonFocusNode,
                                    label: '⚙ Sources',
                                    isPrimary: false,
                                    icon: Icons.tune,
                                    onPressed: _openManualSources,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),

                  // TV Section: Season Tab Selector and Episode List
                  if (_isTv && _details?.seasons.isNotEmpty == true) ...[
                    _buildTvSeasonSelector(),
                    const SizedBox(height: 20),
                    _buildTvEpisodesList(),
                    const SizedBox(height: 36),
                  ],

                  // Cast Carousel Row
                  if (_details?.cast.isNotEmpty == true) ...[
                    CastCarousel(cast: _details!.cast),
                    const SizedBox(height: 32),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildTvSeasonSelector() {
    final seasons = _details?.seasons ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Seasons',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: seasons.length,
            itemBuilder: (context, index) {
              final s = seasons[index];
              final isSelected = s.seasonNumber == _selectedSeasonNumber;
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: TvFocusButton(
                  label: s.name.isNotEmpty ? s.name : 'Season ${s.seasonNumber}',
                  isPrimary: isSelected,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  fontSize: 14,
                  onPressed: () {
                    _loadSeason(s.seasonNumber, _details?.tmdbId ?? 0);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTvEpisodesList() {
    if (_isLoadingSeason) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: CircularProgressIndicator(color: TVTheme.primary),
        ),
      );
    }

    final episodes = _currentSeason?.episodes ?? [];
    if (episodes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'No episodes found for this season.',
          style: TextStyle(color: TVTheme.textSecondary, fontSize: 14),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Episodes (${episodes.length})',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 250,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final ep = episodes[index];
              return _EpisodeCard(
                episode: ep,
                onTap: () => _playEpisode(ep),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EpisodeCard extends StatefulWidget {
  final TvEpisode episode;
  final VoidCallback onTap;

  const _EpisodeCard({
    required this.episode,
    required this.onTap,
  });

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final stillUrl = ep.stillUrl;

    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Focus(
        onFocusChange: (f) {
          setState(() => _isFocused = f);
          if (f) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: Duration.zero,
            );
          }
        },
        onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(event, onActivate: widget.onTap),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isFocused ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 160),
            curve: TVTheme.focusCurve,
            child: Container(
              width: 280,
              decoration: BoxDecoration(
                color: _isFocused ? TVTheme.surfaceElevated : TVTheme.surface,
                borderRadius: TVTheme.borderRadiusMd,
                border: Border.all(
                  color: _isFocused ? Colors.white : Colors.white12,
                  width: _isFocused ? 2.5 : 1.0,
                ),
                boxShadow: _isFocused ? TVTheme.focusShadows : TVTheme.restingShadows,
              ),
              child: ClipRRect(
                borderRadius: TVTheme.borderRadiusMd,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Still Image
                    SizedBox(
                      height: 125,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (stillUrl.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: stillUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 420,
                              memCacheHeight: 236,
                              maxWidthDiskCache: 420,
                              maxHeightDiskCache: 236,
                              placeholder: (_, __) => Container(
                                color: TVTheme.surfaceElevated,
                                child: const Center(
                                  child: Icon(Icons.tv, size: 36, color: TVTheme.textMuted),
                                ),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: TVTheme.surfaceElevated,
                                child: const Center(
                                  child: Icon(Icons.tv, size: 36, color: TVTheme.textMuted),
                                ),
                              ),
                            )
                          else
                            Container(
                              color: TVTheme.surfaceElevated,
                              child: const Center(
                                child: Icon(Icons.tv, size: 36, color: TVTheme.textMuted),
                              ),
                            ),
                          if (!ep.isReleased)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade900,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Upcoming',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: 6,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'EP ${ep.episodeNumber}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          if (ep.formattedRuntime.isNotEmpty)
                            Positioned(
                              bottom: 6,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  ep.formattedRuntime,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Title & Air Date
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              ep.name.isNotEmpty ? ep.name : 'Episode ${ep.episodeNumber}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _isFocused ? Colors.white : Colors.white,
                                fontSize: 13,
                                fontWeight: _isFocused ? FontWeight.bold : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (ep.airDate != null && ep.airDate!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              ep.airDate!,
                              style: const TextStyle(
                                color: TVTheme.textMuted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Synopsis Snippet
                    if (ep.overview.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                        child: Text(
                          ep.overview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _isFocused ? Colors.white70 : TVTheme.textSecondary,
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
