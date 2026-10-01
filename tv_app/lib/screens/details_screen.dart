import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.model.dart';
import '../models/movie_details.model.dart';
import '../core/api_client.dart';
import '../core/local_storage.dart';
import '../theme.dart';
import '../widgets/cast_carousel.dart';
import '../widgets/stream_selector.dart';
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

  final FocusNode _playResumeFocusNode = FocusNode();
  final FocusNode _startOverFocusNode = FocusNode();
  final FocusNode _firstStreamFocusNode = FocusNode();
  final FocusNode _retryFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _fetchDetails();
    _loadProgress();
    _fetchStreams();
  }

  @override
  void dispose() {
    _cacheTimer?.cancel();
    _playResumeFocusNode.dispose();
    _startOverFocusNode.dispose();
    _firstStreamFocusNode.dispose();
    _retryFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    final pos = await LocalStorage.getProgress(widget.movie.tmdbId);
    if (mounted) {
      setState(() {
        _savedProgressSeconds = pos;
      });
    }
  }

  Future<void> _fetchDetails() async {
    final details = await ApiClient.getMovieDetails(widget.movie.tmdbId);
    if (mounted && details != null) {
      setState(() {
        _details = details;
      });
    }
  }

  Future<void> _fetchStreams({bool bypassCache = false, String? provider}) async {
    _cacheTimer?.cancel();
    setState(() {
      _isLoadingStreams = true;
      _cacheExpiresIn = 0;
      _statusMessage = provider != null ? 'Refreshing $provider...' : 'Connecting to scrapers...';
    });

    final response = await ApiClient.getStreamLinksWithProgress(
      widget.movie.tmdbId,
      provider: provider,
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
      final newStreams = List<Map<String, dynamic>>.from(streamList);
      if (provider != null && _streams.isNotEmpty) {
        final filtered = _streams.where((s) => (s['provider']?.toString().toLowerCase() != provider.toLowerCase())).toList();
        _streams = [...newStreams, ...filtered];
      } else {
        _streams = newStreams;
      }
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
      await _fetchStreams(bypassCache: true);
    } else {
      final topStream = _streams.first;
      final num? expiresAt = topStream['expires_at'] as num?;
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final bool isExpired = expiresAt != null && expiresAt > 0 && expiresAt <= nowSec;

      if (isExpired) {
        final String provider = topStream['provider']?.toString() ?? '';
        await _fetchStreams(bypassCache: true, provider: provider);
      }
    }

    if (mounted && _streams.isNotEmpty) {
      _startPlayback(_streams.first, initialSeconds: initialSeconds);
    }
  }

  void _startPlayback(Map<String, dynamic> stream, {int initialSeconds = 0}) {
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
          movieTitle: widget.movie.title,
          tmdbId: widget.movie.tmdbId,
          provider: provider,
          quality: quality,
          initialPositionSeconds: initialSeconds,
        ),
      ),
    ).then((_) {
      _loadProgress();
    });
  }

  Future<void> _refreshAndPlayProvider(String provider) async {
    await _fetchStreams(bypassCache: true, provider: provider);
    if (!mounted || _streams.isEmpty) return;

    final matching = _streams.firstWhere(
      (s) => s['provider']?.toString().toLowerCase() == provider.toLowerCase(),
      orElse: () => _streams.first,
    );
    _startPlayback(matching, initialSeconds: _savedProgressSeconds > 15 ? _savedProgressSeconds : 0);
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
          // Horizontal Gradient Scrim
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    TVTheme.background,
                    Color(0xF0121212),
                    Color(0x99121212),
                    Color(0x33121212),
                  ],
                  stops: [0.0, 0.45, 0.75, 1.0],
                ),
              ),
            ),
          ),
          // Vertical Gradient Scrim
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0x66121212),
                    TVTheme.background,
                  ],
                  stops: [0.0, 0.65, 1.0],
                ),
              ),
            ),
          ),
          // Screen Content
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
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
                                if (_details?.formattedRuntime.isNotEmpty == true)
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
                            // Primary In-Line Play / Resume Action Row
                            if (_streams.isNotEmpty) ...[
                              Row(
                                children: [
                                  if (_savedProgressSeconds > 15) ...[
                                    _buildActionButton(
                                      icon: Icons.play_arrow_rounded,
                                      label: 'Resume (${_formatTime(_savedProgressSeconds)})',
                                      focusNode: _playResumeFocusNode,
                                      isPrimary: true,
                                      onPressed: () => _handlePlayOrResume(initialSeconds: _savedProgressSeconds),
                                    ),
                                    const SizedBox(width: 14),
                                    _buildActionButton(
                                      icon: Icons.replay_rounded,
                                      label: 'Start Over',
                                      focusNode: _startOverFocusNode,
                                      isPrimary: false,
                                      onPressed: () async {
                                        await LocalStorage.clearProgress(widget.movie.tmdbId);
                                        setState(() => _savedProgressSeconds = 0);
                                        _handlePlayOrResume(initialSeconds: 0);
                                      },
                                    ),
                                  ] else ...[
                                    _buildActionButton(
                                      icon: Icons.play_arrow_rounded,
                                      label: 'Play',
                                      focusNode: _playResumeFocusNode,
                                      isPrimary: true,
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
                            StreamSelector(
                              streams: _streams,
                              isLoading: _isLoadingStreams,
                              statusMessage: _statusMessage,
                              cacheExpiresIn: _cacheExpiresIn,
                              onRetry: () => _fetchStreams(bypassCache: false),
                              onForceRescrape: () => _fetchStreams(bypassCache: true),
                              onRescrapeProvider: (provider) => _refreshAndPlayProvider(provider),
                              onStreamSelected: (stream) => _startPlayback(stream, initialSeconds: _savedProgressSeconds > 15 ? _savedProgressSeconds : 0),
                              firstStreamFocusNode: _firstStreamFocusNode,
                              retryFocusNode: _retryFocusNode,
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required FocusNode focusNode,
    required bool isPrimary,
    required VoidCallback onPressed,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onPressed,
            child: AnimatedScale(
              scale: focused ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 140),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: isPrimary
                      ? (focused ? Colors.white : TVTheme.accent)
                      : (focused ? Colors.white24 : Colors.white10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: focused ? Colors.white : Colors.transparent,
                    width: 2.0,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: (isPrimary ? TVTheme.accent : Colors.white).withOpacity(0.45),
                            blurRadius: 18,
                            spreadRadius: 2,
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: isPrimary
                          ? (focused ? Colors.black : Colors.white)
                          : Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isPrimary
                            ? (focused ? Colors.black : Colors.white)
                            : Colors.white,
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
