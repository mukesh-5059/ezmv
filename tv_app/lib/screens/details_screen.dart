import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/cast_carousel.dart';
import '../widgets/stream_selector.dart';
import '../widgets/episode_stream_dialog.dart';
import 'player_screen.dart';

String _formatTime(int totalSeconds) {
  if (totalSeconds <= 0) return '0:00';
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  final String secStr = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final String minStr = minutes.toString().padLeft(2, '0');
    return '$hours:$minStr:$secStr';
  }
  return '$minutes:$secStr';
}

class DetailsScreen extends StatefulWidget {
  final Movie movie;

  const DetailsScreen({super.key, required this.movie});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  MovieDetails? _details;
  List<Map<String, dynamic>> _streams = [];
  bool _isLoadingStreams = true;
  int _cacheExpiresIn = 0;
  int _savedProgressSeconds = 0;
  String _statusMessage = 'Connecting to scrapers...';
  Timer? _cacheTimer;

  // TV Series State
  int _selectedSeasonNumber = 1;
  TvSeason? _currentSeasonData;
  bool _isLoadingSeason = false;
  Map<String, dynamic>? _tvLastWatched;
  Map<int, int> _episodeProgress = {};

  bool get _isTv => widget.movie.isTv || (_details?.isTv ?? false);

  final FocusNode _playResumeFocusNode = FocusNode();
  final FocusNode _startOverFocusNode = FocusNode();
  final FocusNode _firstStreamFocusNode = FocusNode();
  final FocusNode _retryFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _episodesSectionKey = GlobalKey();
  final GlobalKey _streamsSectionKey = GlobalKey();

  void _scrollToTop() {
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _playResumeFocusNode.addListener(() {
      if (_playResumeFocusNode.hasFocus) _scrollToTop();
    });
    _startOverFocusNode.addListener(() {
      if (_startOverFocusNode.hasFocus) _scrollToTop();
    });
    _fetchDetails();
    _loadProgress();
    if (!widget.movie.isTv) {
      _fetchStreams();
    }
  }

  @override
  void dispose() {
    _cacheTimer?.cancel();
    _playResumeFocusNode.dispose();
    _startOverFocusNode.dispose();
    _firstStreamFocusNode.dispose();
    _retryFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    final pos = await LocalStorage.getProgress(widget.movie.tmdbId);
    final tvLast = await LocalStorage.getTvLastWatched(widget.movie.tmdbId);
    if (mounted) {
      setState(() {
        _savedProgressSeconds = pos;
        _tvLastWatched = tvLast;
      });
      _loadCurrentSeasonProgress();
    }
  }

  Future<void> _loadCurrentSeasonProgress() async {
    if (_currentSeasonData == null) return;
    final Map<int, int> progressMap = {};
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
    if (mounted) {
      setState(() {
        _episodeProgress = progressMap;
      });
    }
  }

  Future<void> _fetchDetails() async {
    final details = await ApiClient.getMovieDetails(widget.movie.tmdbId, mediaType: widget.movie.mediaType);
    if (mounted && details != null) {
      setState(() {
        _details = details;
      });

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
        _fetchSeasonEpisodes(initialSeason, autoFocusPlay: true);
      }
    }
  }

  Future<void> _fetchSeasonEpisodes(int seasonNumber, {bool autoFocusPlay = false}) async {
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
      if (autoFocusPlay) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _playResumeFocusNode.canRequestFocus) {
            _playResumeFocusNode.requestFocus();
          }
        });
      }
    }
  }

  Future<void> _openEpisodeStreams(TvEpisode episode) async {
    final stream = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => EpisodeStreamDialog(
        movie: widget.movie,
        seasonNumber: _selectedSeasonNumber,
        episode: episode,
      ),
    );
    if (stream != null && mounted) {
      final title =
          '${widget.movie.title} - S${_selectedSeasonNumber.toString().padLeft(2, '0')}E${episode.episodeNumber.toString().padLeft(2, '0')}: ${episode.name}';
      final resumeSeconds = await LocalStorage.getProgress(
        widget.movie.tmdbId,
        mediaType: 'tv',
        season: _selectedSeasonNumber,
        episode: episode.episodeNumber,
      );
      if (mounted) {
        _startPlayback(
          stream,
          overrideTitle: title,
          initialSeconds: resumeSeconds > 5 ? resumeSeconds : 0,
          mediaType: 'tv',
          season: _selectedSeasonNumber,
          episode: episode.episodeNumber,
        );
      }
    }
  }

  Future<void> _handleTvResume() async {
    if (_tvLastWatched == null) return;
    final season = _tvLastWatched!['season'] as int? ?? 1;
    final epNum = _tvLastWatched!['episode'] as int? ?? 1;

    if (_selectedSeasonNumber != season || _currentSeasonData == null) {
      await _fetchSeasonEpisodes(season);
    }

    TvEpisode? targetEpisode;
    if (_currentSeasonData != null) {
      targetEpisode = _currentSeasonData!.episodes.cast<TvEpisode?>().firstWhere(
            (e) => e?.episodeNumber == epNum,
            orElse: () => null,
          );
    }

    final ep = targetEpisode ??
        TvEpisode(
          id: 0,
          name: 'Episode $epNum',
          overview: '',
          episodeNumber: epNum,
          seasonNumber: season,
          stillPath: '',
          airDate: '',
          voteAverage: 0.0,
          runtime: 0,
        );

    if (mounted) {
      await _openEpisodeStreams(ep);
    }
  }

  Future<void> _handleTvStartFirstEpisode() async {
    int targetSeason = 1;
    if (_details?.seasons.isNotEmpty == true) {
      final firstSeason = _details!.seasons.firstWhere(
        (s) => s.seasonNumber > 0,
        orElse: () => _details!.seasons.first,
      );
      targetSeason = firstSeason.seasonNumber;
    }

    if (_selectedSeasonNumber != targetSeason || _currentSeasonData == null) {
      await _fetchSeasonEpisodes(targetSeason);
    }

    TvEpisode? firstEp;
    if (_currentSeasonData != null && _currentSeasonData!.episodes.isNotEmpty) {
      firstEp = _currentSeasonData!.episodes.first;
    }

    final ep = firstEp ??
        TvEpisode(
          id: 0,
          name: 'Episode 1',
          overview: '',
          episodeNumber: 1,
          seasonNumber: targetSeason,
          stillPath: '',
          airDate: '',
          voteAverage: 0.0,
          runtime: 0,
        );

    if (mounted) {
      await _openEpisodeStreams(ep);
    }
  }

  Future<void> _fetchStreams({bool bypassCache = false}) async {
    _cacheTimer?.cancel();
    setState(() {
      _isLoadingStreams = true;
      _cacheExpiresIn = 0;
      _statusMessage = 'Connecting to scrapers...';
    });

    final response = await ApiClient.getStreamLinksWithProgress(
      widget.movie.tmdbId,
      bypassCache: bypassCache,
      onProgress: (msg) {
        if (!mounted) return;
        setState(() {
          _statusMessage = msg;
        });
      },
    );

    if (!mounted) return;

    setState(() {
      final List streamList = response['streams'] ?? [];
      _streams = List<Map<String, dynamic>>.from(streamList);
      _streams.sort((a, b) => ((a['priority'] as num?) ?? 100).compareTo((b['priority'] as num?) ?? 100));
      _cacheExpiresIn = response['cache_expires_in'] ?? 0;
      _isLoadingStreams = false;
    });

    if (_cacheExpiresIn > 0) {
      _cacheTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          if (_cacheExpiresIn > 0) {
            _cacheExpiresIn--;
          } else {
            timer.cancel();
          }
        });
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_streams.isNotEmpty) {
        if (_playResumeFocusNode.canRequestFocus) {
          _playResumeFocusNode.requestFocus();
        } else if (_firstStreamFocusNode.canRequestFocus) {
          _firstStreamFocusNode.requestFocus();
        }
      } else if (_streams.isEmpty && _retryFocusNode.canRequestFocus) {
        _retryFocusNode.requestFocus();
      }
    });
  }

  Future<void> _handlePlayOrResume({int initialSeconds = 0}) async {
    if (_isLoadingStreams) return;

    if (_streams.isEmpty) {
      await _fetchStreams(bypassCache: false);
    }

    if (mounted && _streams.isNotEmpty) {
      _startPlayback(_streams.first, initialSeconds: initialSeconds);
    }
  }

  Future<void> _handleStreamSelected(Map<String, dynamic> stream) async {
    if (_isLoadingStreams) return;

    final targetUrl = stream['url'];
    final targetQuality = stream['quality']?.toString();
    final targetProvider = stream['provider']?.toString();

    if (_streams.isEmpty) {
      await _fetchStreams(bypassCache: false);
    }

    if (mounted && _streams.isNotEmpty) {
      final matching = _streams.firstWhere(
        (s) => s['url'] == targetUrl,
        orElse: () => _streams.firstWhere(
          (s) => s['quality']?.toString() == targetQuality && s['provider']?.toString() == targetProvider,
          orElse: () => _streams.firstWhere(
            (s) => s['quality']?.toString() == targetQuality,
            orElse: () => _streams.first,
          ),
        ),
      );
      _startPlayback(matching, initialSeconds: _savedProgressSeconds > 15 ? _savedProgressSeconds : 0);
    }
  }

  void _startPlayback(
    Map<String, dynamic> stream, {
    int initialSeconds = 0,
    String? overrideTitle,
    String mediaType = 'movie',
    int? season,
    int? episode,
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
    ).then((_) {
      _loadProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final backdropUrl = _details?.backdropUrl.isNotEmpty == true
        ? _details!.backdropUrl
        : widget.movie.backdropUrl;
    final posterUrl = _details?.posterUrl.isNotEmpty == true
        ? _details!.posterUrl
        : widget.movie.posterUrl;
    final releaseYear = (_details?.releaseDate.isNotEmpty == true
            ? _details!.releaseDate
            : widget.movie.releaseDate)
        .split('-')[0];
    final rating = _details?.voteAverage ?? widget.movie.voteAverage;
    final overview = _details?.overview.isNotEmpty == true
        ? _details!.overview
        : widget.movie.overview;
    final genreText = _details?.genreNamesString.isNotEmpty == true
        ? _details!.genreNamesString
        : widget.movie.genreTags;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Backdrop Image
          if (backdropUrl.isNotEmpty)
            Positioned.fill(
              child: Image.network(
                backdropUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          // Horizontal Gradient Scrim (OLED black on left transitioning smoothly into backdrop image)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    TVTheme.background,
                    TVTheme.background.withValues(alpha: 0.95),
                    TVTheme.background.withValues(alpha: 0.60),
                    TVTheme.background.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.35, 0.60, 0.85, 1.0],
                ),
              ),
            ),
          ),
          // Vertical Gradient Scrim (Top header fade, clear backdrop window, fading to solid black bottom)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    TVTheme.background.withValues(alpha: 0.35),
                    Colors.transparent,
                    TVTheme.background.withValues(alpha: 0.70),
                    TVTheme.background,
                  ],
                  stops: const [0.0, 0.22, 0.65, 1.0],
                ),
              ),
            ),
          ),
          // Screen Content
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 20.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: size.width * 0.22,
                          child: AspectRatio(
                            aspectRatio: 2 / 3,
                            child: Image.network(
                              posterUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: TVTheme.surface),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.movie.title,
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                            ),
                            if (_details?.tagline != null && _details!.tagline!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                '"${_details!.tagline}"',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                if (releaseYear.isNotEmpty)
                                  _buildBadge(Icons.calendar_today, releaseYear),
                                if (_isTv && _details != null && _details!.numberOfSeasons > 0)
                                  _buildBadge(
                                    Icons.layers_outlined,
                                    '${_details!.numberOfSeasons} ${_details!.numberOfSeasons == 1 ? "Season" : "Seasons"}',
                                  )
                                else if (!_isTv && _details?.formattedRuntime.isNotEmpty == true)
                                  _buildBadge(Icons.timer_outlined, _details!.formattedRuntime),
                                _buildBadge(
                                  Icons.language,
                                  widget.movie.originalLanguage.toUpperCase(),
                                ),
                                _buildBadge(Icons.star, rating.toStringAsFixed(1), iconColor: Colors.amber),
                                if (genreText.isNotEmpty)
                                  _buildBadge(Icons.movie_filter_outlined, genreText),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              overview,
                              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                            ),
                            const SizedBox(height: 24),
                            if (_isTv) ...[
                              Row(
                                children: [
                                  if (_tvLastWatched != null && (_tvLastWatched!['position'] as int? ?? 0) > 15) ...[
                                    _buildActionButton(
                                      icon: Icons.play_arrow_rounded,
                                      label:
                                          'Resume S${_tvLastWatched!['season']}E${_tvLastWatched!['episode']} (${_formatTime(_tvLastWatched!['position'] as int)})',
                                      focusNode: _playResumeFocusNode,
                                      isPrimary: true,
                                      onPressed: _handleTvResume,
                                    ),
                                    const SizedBox(width: 14),
                                    _buildActionButton(
                                      icon: Icons.replay_rounded,
                                      label: 'Play S1:E1',
                                      focusNode: _startOverFocusNode,
                                      isPrimary: false,
                                      onPressed: _handleTvStartFirstEpisode,
                                    ),
                                  ] else ...[
                                    _buildActionButton(
                                      icon: Icons.play_arrow_rounded,
                                      label: 'Play S1:E1',
                                      focusNode: _playResumeFocusNode,
                                      isPrimary: true,
                                      onPressed: _handleTvStartFirstEpisode,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 24),
                            ] else ...[
                              // Primary In-Line Play / Resume Action Row (Movie Only)
                              Row(
                                children: [
                                  if (_savedProgressSeconds > 15) ...[
                                    _buildActionButton(
                                      icon: _isLoadingStreams ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded,
                                      label: _isLoadingStreams
                                          ? 'Resume (Loading...)'
                                          : (_streams.isEmpty ? 'Resume (No Streams)' : 'Resume (${_formatTime(_savedProgressSeconds)})'),
                                      focusNode: _playResumeFocusNode,
                                      isPrimary: true,
                                      isEnabled: !_isLoadingStreams && _streams.isNotEmpty,
                                      onPressed: () => _handlePlayOrResume(initialSeconds: _savedProgressSeconds),
                                    ),
                                    const SizedBox(width: 14),
                                    _buildActionButton(
                                      icon: Icons.replay_rounded,
                                      label: 'Start Over',
                                      focusNode: _startOverFocusNode,
                                      isPrimary: false,
                                      isEnabled: !_isLoadingStreams && _streams.isNotEmpty,
                                      onPressed: () async {
                                        await LocalStorage.clearProgress(widget.movie.tmdbId);
                                        setState(() => _savedProgressSeconds = 0);
                                        _handlePlayOrResume(initialSeconds: 0);
                                      },
                                    ),
                                  ] else ...[
                                    _buildActionButton(
                                      icon: _isLoadingStreams ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded,
                                      label: _isLoadingStreams
                                          ? 'Play (Loading...)'
                                          : (_streams.isEmpty ? 'Play (No Streams)' : 'Play'),
                                      focusNode: _playResumeFocusNode,
                                      isPrimary: true,
                                      isEnabled: !_isLoadingStreams && _streams.isNotEmpty,
                                      onPressed: () => _handlePlayOrResume(initialSeconds: 0),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 24),
                            ],
                            if (_details != null && _details!.cast.isNotEmpty) ...[
                              CastCarousel(cast: _details!.cast),
                              const SizedBox(height: 28),
                            ],
                            if (_isTv)
                              _buildTvSeasonsAndEpisodesSection()
                            else
                              StreamSelector(
                                key: _streamsSectionKey,
                                streams: _streams,
                                isLoading: _isLoadingStreams,
                                statusMessage: _statusMessage,
                                cacheExpiresIn: _cacheExpiresIn,
                                onRetry: () => _fetchStreams(bypassCache: false),
                                onForceRescrape: () => _fetchStreams(bypassCache: true),
                                onStreamSelected: (stream) => _handleStreamSelected(stream),
                                firstStreamFocusNode: _firstStreamFocusNode,
                                retryFocusNode: _retryFocusNode,
                                onSectionFocused: () {
                                  if (_streamsSectionKey.currentContext != null) {
                                    Scrollable.ensureVisible(
                                      _streamsSectionKey.currentContext!,
                                      alignment: 0.25,
                                      duration: const Duration(milliseconds: 280),
                                      curve: Curves.easeOutCubic,
                                    );
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTvSeasonsAndEpisodesSection() {
    final seasons = _details?.seasons ?? [];

    return Container(
      key: _episodesSectionKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          const Text(
            'Episodes',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 14),

          // Season Chips Selector
          if (seasons.isNotEmpty) ...[
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final season = seasons[index];
                  final isSelected = season.seasonNumber == _selectedSeasonNumber;
                  return _buildSeasonChip(season, isSelected);
                },
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Episodes Container / Loader
          if (_isLoadingSeason)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32.0),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: TVTheme.accent),
                    ),
                    SizedBox(width: 14),
                    Text('Loading episodes...', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
            )
          else if (_currentSeasonData == null || _currentSeasonData!.episodes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Text(
                'No episodes found for Season $_selectedSeasonNumber.',
                style: const TextStyle(color: Colors.white60, fontSize: 14),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _currentSeasonData!.episodes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final ep = _currentSeasonData!.episodes[index];
                return _buildEpisodeTile(ep);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSeasonChip(TvSeason season, bool isSelected) {
    return Focus(
      onFocusChange: (focused) {
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
          if (_episodesSectionKey.currentContext != null) {
            Scrollable.ensureVisible(
              _episodesSectionKey.currentContext!,
              alignment: 0.05,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            );
          }
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          if (_selectedSeasonNumber != season.seasonNumber) {
            _fetchSeasonEpisodes(season.seasonNumber);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              if (_selectedSeasonNumber != season.seasonNumber) {
                _fetchSeasonEpisodes(season.seasonNumber);
              }
            },
            child: AnimatedScale(
              scale: focused ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 140),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (focused ? Colors.white : TVTheme.accent)
                      : (focused ? Colors.white24 : const Color(0xFF222226)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: focused ? Colors.white : (isSelected ? TVTheme.accent : Colors.white12),
                    width: focused ? 3.0 : 1.0,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: (isSelected ? TVTheme.accent : Colors.white).withValues(alpha: 0.2),
                            blurRadius: 8,
                            spreadRadius: 0,
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    season.name.isNotEmpty ? season.name : 'Season ${season.seasonNumber}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected && focused ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEpisodeTile(TvEpisode episode) {
    final progressSecs = _episodeProgress[episode.episodeNumber] ?? 0;

    return Focus(
      onFocusChange: (focused) {
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.45,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          _openEpisodeStreams(episode);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => _openEpisodeStreams(episode),
            child: AnimatedScale(
              scale: focused ? 1.02 : 1.0,
              duration: const Duration(milliseconds: 140),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: focused ? const Color(0xFF25252A) : const Color(0xFF19191C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: focused ? TVTheme.accent : Colors.white12,
                    width: focused ? 3.0 : 1.0,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: TVTheme.accent.withValues(alpha: 0.25),
                            blurRadius: 8,
                            spreadRadius: 0,
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Still / Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: [
                          Container(
                            width: 130,
                            height: 74,
                            color: const Color(0xFF2C2C32),
                            child: episode.stillUrl.isNotEmpty
                                ? Image.network(
                                    episode.stillUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(Icons.tv_rounded, color: Colors.white30, size: 28),
                                    ),
                                  )
                                : const Center(
                                    child: Icon(Icons.tv_rounded, color: Colors.white30, size: 28),
                                  ),
                          ),
                          Positioned(
                            bottom: progressSecs > 15 ? 8 : 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'EP ${episode.episodeNumber}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          if (progressSecs > 15)
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 3,
                                color: Colors.white24,
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: ((episode.runtime != null && episode.runtime! > 0)
                                          ? (progressSecs / (episode.runtime! * 60))
                                          : 0.5)
                                      .clamp(0.0, 1.0),
                                  child: Container(color: TVTheme.accent),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Title, Info & Overview
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
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: focused ? TVTheme.accent : Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (episode.formattedRuntime.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  episode.formattedRuntime,
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                              if (episode.voteAverage > 0) ...[
                                const SizedBox(width: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                                    const SizedBox(width: 2),
                                    Text(
                                      episode.voteAverage.toStringAsFixed(1),
                                      style: const TextStyle(
                                          color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                              if (progressSecs > 15) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: TVTheme.accent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: TVTheme.accent.withValues(alpha: 0.6), width: 0.8),
                                  ),
                                  child: Text(
                                    'Resume ${_formatTime(progressSecs)}',
                                    style: const TextStyle(
                                      color: TVTheme.accent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (episode.overview.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              episode.overview,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.play_circle_fill_rounded,
                      color: focused ? TVTheme.accent : Colors.white38,
                      size: 36,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required FocusNode focusNode,
    required bool isPrimary,
    required VoidCallback onPressed,
    bool isEnabled = true,
  }) {
    return Focus(
      focusNode: focusNode,
      autofocus: isPrimary,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            if (isEnabled) {
              onPressed();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _scrollToTop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: isEnabled ? onPressed : null,
            child: AnimatedScale(
              scale: focused ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 140),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: !isEnabled
                      ? (focused ? Colors.white24 : Colors.white10)
                      : (isPrimary
                          ? (focused ? Colors.white : TVTheme.accent)
                          : (focused ? Colors.white24 : Colors.white10)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: focused ? Colors.white : Colors.transparent,
                    width: 3.0,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: (!isEnabled
                                    ? Colors.white
                                    : (isPrimary ? TVTheme.accent : Colors.white))
                                .withValues(alpha: 0.22),
                            blurRadius: 8,
                            spreadRadius: 0,
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: !isEnabled
                          ? (focused ? Colors.white70 : Colors.white38)
                          : (isPrimary
                              ? (focused ? Colors.black : Colors.white)
                              : Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: !isEnabled
                            ? (focused ? Colors.white70 : Colors.white38)
                            : (isPrimary
                                ? (focused ? Colors.black : Colors.white)
                                : Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBadge(IconData icon, String text, {Color iconColor = TVTheme.textSecondary}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: TVTheme.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}
