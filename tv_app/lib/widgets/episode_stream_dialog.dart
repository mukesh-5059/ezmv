import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import 'tv_shortcuts.dart';

class EpisodeStreamDialog extends StatefulWidget {
  final String imdbId;
  final String showTitle;
  final int seasonNumber;
  final TvEpisode episode;
  final bool autoPlay;
  final String? originalLanguage;
  final void Function(StreamSource stream)? onStreamSelected;
  final void Function(StreamSource stream, List<StreamSource> allStreams)? onStreamSelectedWithAll;

  const EpisodeStreamDialog({
    super.key,
    required this.imdbId,
    required this.showTitle,
    required this.seasonNumber,
    required this.episode,
    this.autoPlay = true,
    this.originalLanguage,
    this.onStreamSelected,
    this.onStreamSelectedWithAll,
  });

  @override
  State<EpisodeStreamDialog> createState() => _EpisodeStreamDialogState();
}

class _EpisodeStreamDialogState extends State<EpisodeStreamDialog> {
  List<StreamSource> _streams = [];
  bool _isLoading = true;
  bool _isRanking = false;
  String _statusMessage = 'Connecting to scrapers...';
  StreamSubscription<StreamProgressEvent>? _sseSubscription;
  final Map<String, ({StreamProgressStatus status, int count})> _providerStatuses = {};
  int _totalStreamsDiscovered = 0;

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
    _sseSubscription?.cancel();
    _firstStreamFocusNode.dispose();
    _retryFocusNode.dispose();
    _closeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchStreams() async {
    _sseSubscription?.cancel();
    setState(() {
      _isLoading = true;
      _providerStatuses.clear();
      _totalStreamsDiscovered = 0;
      _statusMessage = 'Connecting to scrapers for S${widget.seasonNumber}E${widget.episode.episodeNumber}...';
    });

    _sseSubscription = ApiClient.instance.getStreamsProgressive(
      'tv',
      widget.imdbId,
      season: widget.seasonNumber,
      episode: widget.episode.episodeNumber,
      originalLanguage: widget.originalLanguage,
    ).listen(
      (event) {
        if (!mounted) return;
        if (event.isDone) {
          final resolvedStreams = event.streams ?? [];
          if (resolvedStreams.isEmpty) {
            setState(() {
              _streams = [];
              _isLoading = false;
              _isRanking = false;
              _statusMessage = 'No streams found for this episode.';
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _retryFocusNode.requestFocus();
            });
            return;
          }

          _isRanking = true;
          setState(() {
            _isLoading = true;
            _statusMessage = 'Analyzing streams for optimal playback...';
          });

          StreamRanker.rankStreams(
            resolvedStreams,
            runtimeMinutes: widget.episode.runtime,
            onProgress: (msg, probed, qual) {
              if (mounted) setState(() => _statusMessage = msg);
            },
          ).then((ranked) {
            if (!mounted) return;
            final allStreams = [
              ranked.topStream,
              ...ranked.fallbackStreams,
              ...ranked.unprobedStreams,
            ];
            if (widget.autoPlay) {
              Navigator.of(context).pop();
              if (widget.onStreamSelectedWithAll != null) {
                widget.onStreamSelectedWithAll!(ranked.topStream, allStreams);
              } else {
                widget.onStreamSelected?.call(ranked.topStream);
              }
              return;
            }
            setState(() {
              _streams = allStreams;
              _isLoading = false;
              _isRanking = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_streams.isNotEmpty) {
                _firstStreamFocusNode.requestFocus();
              } else {
                _retryFocusNode.requestFocus();
              }
            });
          }).catchError((_) {
            if (!mounted) return;
            if (widget.autoPlay && resolvedStreams.isNotEmpty) {
              Navigator.of(context).pop();
              if (widget.onStreamSelectedWithAll != null) {
                widget.onStreamSelectedWithAll!(resolvedStreams.first, resolvedStreams);
              } else {
                widget.onStreamSelected?.call(resolvedStreams.first);
              }
              return;
            }
            setState(() {
              _streams = resolvedStreams;
              _isLoading = false;
              _isRanking = false;
            });
          });
          return;
        }

        if (event.status == StreamProgressStatus.error) {
          if (event.provider != 'all') {
            setState(() {
              _providerStatuses[event.provider] = (status: StreamProgressStatus.error, count: 0);
            });
          }
          return;
        }

        if (event.provider != 'all') {
          setState(() {
            _providerStatuses[event.provider] = (
              status: event.status,
              count: event.count ?? _providerStatuses[event.provider]?.count ?? 0,
            );
            if (event.status == StreamProgressStatus.searching) {
              _statusMessage = 'Searching ${event.provider}...';
            } else if (event.status == StreamProgressStatus.resolved) {
              _statusMessage = '${event.provider}: ${event.count ?? 0} stream(s) found';
              _totalStreamsDiscovered = _providerStatuses.values.fold(0, (acc, p) => acc + p.count);
            }
          });
        }
      },
      onError: (err) {
        if (!mounted) return;
        _isRanking = false;
        StreamRanker.checkInternetReachability().then((isOnline) {
          if (!mounted) return;
          final displayErr = !isOnline
              ? 'Network error: Please check your Wi-Fi or Ethernet connection.'
              : 'Streaming providers are temporarily slow or unavailable ($err).';
          setState(() {
            _isLoading = false;
            _statusMessage = displayErr;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _retryFocusNode.requestFocus();
          });
        });
      },
      onDone: () {
        if (!mounted) return;
        if (_isLoading && !_isRanking && _streams.isEmpty) {
          setState(() => _isLoading = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _retryFocusNode.requestFocus();
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sStr = widget.seasonNumber.toString().padLeft(2, '0');
    final eStr = widget.episode.episodeNumber.toString().padLeft(2, '0');
    final epCode = 'S${sStr}E$eStr';
    final stillUrl = widget.episode.stillUrl;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        width: 780,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0D12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black87,
              blurRadius: 32,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Episode Banner
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Episode Still Thumbnail
                if (stillUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 160,
                      height: 95,
                      color: TVTheme.surface,
                      child: Image.network(
                        stillUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.tv, size: 36, color: Colors.white24),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 160,
                    height: 95,
                    decoration: BoxDecoration(
                      color: TVTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.tv, size: 36, color: Colors.white24),
                  ),
                const SizedBox(width: 18),

                // Episode Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: TVTheme.primary,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              epCode,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.showTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (widget.episode.airDate != null && widget.episode.airDate!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              widget.episode.airDate!,
                              style: const TextStyle(color: TVTheme.textMuted, fontSize: 12),
                            ),
                          ],
                          if (widget.episode.formattedRuntime.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              '• ${widget.episode.formattedRuntime}',
                              style: const TextStyle(color: TVTheme.textMuted, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.episode.name.isNotEmpty
                            ? widget.episode.name
                            : 'Episode ${widget.episode.episodeNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (widget.episode.overview.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.episode.overview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Close Button
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
                          color: focused ? TVTheme.primary : Colors.white60,
                          size: 26,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 14),

            // Sources Header
            Row(
              children: [
                const Icon(Icons.stream_rounded, color: TVTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  _isLoading
                      ? 'Searching Sources...'
                      : 'Available Sources (${_streams.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Sources List / Loading / Empty
            if (_isLoading)
              Container(
                height: 200,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: TVTheme.primary,
                            strokeWidth: 2.5,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Flexible(
                          child: Text(
                            _statusMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (_totalStreamsDiscovered > 0) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: TVTheme.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: TVTheme.primary.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              '$_totalStreamsDiscovered found',
                              style: const TextStyle(
                                color: TVTheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        minHeight: 4,
                        color: TVTheme.primary,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_providerStatuses.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: _providerStatuses.entries.map((entry) {
                          final provider = entry.key;
                          final info = entry.value;
                          final isSearching = info.status == StreamProgressStatus.searching;
                          final isResolved = info.status == StreamProgressStatus.resolved;

                          final badgeColor = isSearching
                              ? Colors.white.withValues(alpha: 0.08)
                              : (isResolved && info.count > 0
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.04));

                          final icon = isSearching
                              ? const SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 1.5),
                                )
                              : Icon(
                                  info.count > 0 ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
                                  size: 13,
                                  color: info.count > 0 ? Colors.greenAccent : Colors.white38,
                                );

                          final text = isSearching
                              ? '$provider: searching...'
                              : (info.count > 0 ? '$provider: ${info.count}' : '$provider: none');

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                icon,
                                const SizedBox(width: 6),
                                Text(
                                  text,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isResolved && info.count > 0 ? Colors.greenAccent : Colors.white70,
                                    fontWeight: isResolved && info.count > 0 ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              )
            else if (_streams.isEmpty)
              Container(
                height: 160,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 40, color: TVTheme.textMuted),
                    const SizedBox(height: 10),
                    const Text(
                      'No playable sources found for this episode.',
                      style: TextStyle(color: TVTheme.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 14),
                    Focus(
                      focusNode: _retryFocusNode,
                      onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(event, onActivate: _fetchStreams),
                      child: Builder(
                        builder: (ctx) {
                          final focused = Focus.of(ctx).hasFocus;
                          return ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: focused ? Colors.white : TVTheme.surface,
                              foregroundColor: focused ? Colors.black : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            onPressed: _fetchStreams,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Retry Fetching'),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _streams.length,
                  itemBuilder: (ctx, idx) {
                    final stream = _streams[idx];
                    return _EpisodeStreamCard(
                      stream: stream,
                      autofocus: idx == 0,
                      focusNode: idx == 0 ? _firstStreamFocusNode : null,
                      onSelect: () {
                        Navigator.of(context).pop(stream);
                        widget.onStreamSelected?.call(stream);
                        widget.onStreamSelectedWithAll?.call(stream, _streams);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeStreamCard extends StatefulWidget {
  final StreamSource stream;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback onSelect;

  const _EpisodeStreamCard({
    required this.stream,
    this.autofocus = false,
    this.focusNode,
    required this.onSelect,
  });

  @override
  State<_EpisodeStreamCard> createState() => _EpisodeStreamCardState();
}

class _EpisodeStreamCardState extends State<_EpisodeStreamCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stream;
    final langs = s.languages.isNotEmpty ? s.languages.join(', ') : 'Default';
    final provider = s.provider.isNotEmpty ? s.provider.toUpperCase() : 'DIRECT';

    return Focus(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(event, onActivate: widget.onSelect),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedScale(
          scale: _isFocused ? 1.015 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _isFocused ? TVTheme.surfaceElevated : const Color(0xFF14151C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isFocused ? Colors.white : Colors.white12,
                width: _isFocused ? 2 : 1,
              ),
              boxShadow: _isFocused ? TVTheme.focusShadows : TVTheme.restingShadows,
            ),
            child: Row(
              children: [
                // Quality Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: s.quality.toLowerCase().contains('1080')
                        ? TVTheme.primary
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    s.quality.isNotEmpty ? s.quality : 'HD',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Stream Metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              provider,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (s.headroomRatio != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: s.headroomRatio! >= 1.4
                                    ? Colors.green.withValues(alpha: 0.2)
                                    : Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: s.headroomRatio! >= 1.4 ? Colors.greenAccent : Colors.amberAccent,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                '${s.headroomRatio!.toStringAsFixed(1)}x',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: s.headroomRatio! >= 1.4 ? Colors.greenAccent : Colors.amberAccent,
                                ),
                              ),
                            ),
                          ],
                          if (s.formattedSize != null && s.formattedSize!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.folder_outlined, size: 13, color: _isFocused ? Colors.white70 : Colors.white54),
                            const SizedBox(width: 3),
                            Text(
                              s.formattedSize!,
                              style: TextStyle(
                                color: _isFocused ? Colors.white : Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          if (langs.isNotEmpty && langs != 'Default') ...[
                            const SizedBox(width: 8),
                            Icon(Icons.volume_up_outlined, size: 13, color: _isFocused ? Colors.white70 : Colors.white54),
                            const SizedBox(width: 3),
                            Text(
                              langs,
                              style: TextStyle(
                                color: _isFocused ? Colors.white70 : Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (s.filename != null && s.filename!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          s.filename!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: _isFocused ? Colors.white70 : Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 10),
                Icon(
                  Icons.play_circle_filled,
                  size: 24,
                  color: _isFocused ? TVTheme.primary : Colors.white38,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
