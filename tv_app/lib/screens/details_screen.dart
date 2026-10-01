import 'dart:async';
import 'package:flutter/material.dart';
import '../models/movie.model.dart';
import '../models/movie_details.model.dart';
import '../core/api_client.dart';
import '../core/local_storage.dart';
import '../theme.dart';
import '../widgets/cast_carousel.dart';
import '../widgets/stream_selector.dart';
import 'player_screen.dart';

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
  String _statusMessage = 'Connecting to scrapers...';
  Timer? _cacheTimer;

  final FocusNode _firstStreamFocusNode = FocusNode();
  final FocusNode _retryFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _fetchDetails();
    _fetchStreams();
  }

  @override
  void dispose() {
    _cacheTimer?.cancel();
    _firstStreamFocusNode.dispose();
    _retryFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    final details = await ApiClient.getMovieDetails(widget.movie.tmdbId);
    if (mounted && details != null) {
      setState(() {
        _details = details;
      });
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
      if (_streams.isNotEmpty && _firstStreamFocusNode.canRequestFocus) {
        _firstStreamFocusNode.requestFocus();
      } else if (_streams.isEmpty && _retryFocusNode.canRequestFocus) {
        _retryFocusNode.requestFocus();
      }
    });
  }

  void _startPlayback(Map<String, dynamic> stream) {
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
        ),
      ),
    );
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
          if (backdropUrl.isNotEmpty)
            Positioned.fill(
              child: Image.network(
                backdropUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Positioned.fill(
            child: Container(
              color: TVTheme.background.withOpacity(0.88),
            ),
          ),
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
                            if (_details != null && _details!.cast.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              CastCarousel(cast: _details!.cast),
                            ],
                            const SizedBox(height: 28),
                            StreamSelector(
                              streams: _streams,
                              isLoading: _isLoadingStreams,
                              statusMessage: _statusMessage,
                              cacheExpiresIn: _cacheExpiresIn,
                              onRetry: () => _fetchStreams(bypassCache: false),
                              onForceRescrape: () => _fetchStreams(bypassCache: true),
                              onStreamSelected: _startPlayback,
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
