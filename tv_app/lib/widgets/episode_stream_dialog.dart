import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.model.dart';
import '../models/tv_episode.model.dart';
import '../core/api_client.dart';
import '../theme.dart';
import 'stream_selector.dart';

class EpisodeStreamDialog extends StatefulWidget {
  final Movie movie;
  final int seasonNumber;
  final TvEpisode episode;
  final void Function(Map<String, dynamic> stream)? onStreamSelected;

  const EpisodeStreamDialog({
    super.key,
    required this.movie,
    required this.seasonNumber,
    required this.episode,
    this.onStreamSelected,
  });

  @override
  State<EpisodeStreamDialog> createState() => _EpisodeStreamDialogState();
}

class _EpisodeStreamDialogState extends State<EpisodeStreamDialog> {
  List<Map<String, dynamic>> _streams = [];
  bool _isLoading = true;
  int _cacheExpiresIn = 0;
  String _statusMessage = 'Connecting to scrapers...';
  Timer? _cacheTimer;

  final FocusNode _firstStreamFocusNode = FocusNode();
  final FocusNode _retryFocusNode = FocusNode();
  final FocusNode _closeFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _fetchStreams();
  }

  @override
  void dispose() {
    _cacheTimer?.cancel();
    _firstStreamFocusNode.dispose();
    _retryFocusNode.dispose();
    _closeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchStreams({bool bypassCache = false}) async {
    _cacheTimer?.cancel();
    setState(() {
      _isLoading = true;
      _cacheExpiresIn = 0;
      _statusMessage = 'Connecting to scrapers...';
    });

    final response = await ApiClient.getStreamLinksWithProgress(
      widget.movie.tmdbId,
      mediaType: 'tv',
      season: widget.seasonNumber,
      episode: widget.episode.episodeNumber,
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
      _isLoading = false;
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
      if (!mounted) return;
      if (_streams.isNotEmpty) {
        _firstStreamFocusNode.requestFocus();
      } else {
        _retryFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sStr = widget.seasonNumber.toString().padLeft(2, '0');
    final eStr = widget.episode.episodeNumber.toString().padLeft(2, '0');
    final epCode = 'S${sStr}E$eStr';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Container(
        width: 860,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF161618),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black87,
              blurRadius: 30,
              spreadRadius: 10,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: TVTheme.accent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      epCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.episode.name.isNotEmpty ? widget.episode.name : 'Episode ${widget.episode.episodeNumber}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.movie.title}${widget.episode.formattedRuntime.isNotEmpty ? ' • ${widget.episode.formattedRuntime}' : ''}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Focus(
                    focusNode: _closeFocusNode,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          (event.logicalKey == LogicalKeyboardKey.select ||
                              event.logicalKey == LogicalKeyboardKey.enter ||
                              event.logicalKey == LogicalKeyboardKey.space)) {
                        Navigator.of(context).pop();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (ctx) {
                        final focused = Focus.of(ctx).hasFocus;
                        return IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(
                            Icons.close_rounded,
                            color: focused ? TVTheme.accent : Colors.white60,
                            size: 26,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (widget.episode.overview.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  widget.episode.overview,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white60,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 20),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 20),
              StreamSelector(
                streams: _streams,
                isLoading: _isLoading,
                statusMessage: _statusMessage,
                cacheExpiresIn: _cacheExpiresIn,
                onRetry: () => _fetchStreams(bypassCache: false),
                onForceRescrape: () => _fetchStreams(bypassCache: true),
                onStreamSelected: (stream) {
                  Navigator.of(context).pop(stream);
                  widget.onStreamSelected?.call(stream);
                },
                firstStreamFocusNode: _firstStreamFocusNode,
                retryFocusNode: _retryFocusNode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
