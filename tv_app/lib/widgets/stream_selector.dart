import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import 'tv_shortcuts.dart';

class StreamSelector extends StatelessWidget {
  final List<StreamSource> streams;
  final bool isLoading;
  final String statusMessage;
  final VoidCallback onRetry;
  final ValueChanged<StreamSource> onStreamSelected;
  final FocusNode? firstStreamFocusNode;
  final FocusNode? retryFocusNode;
  final VoidCallback? onSectionFocused;

  const StreamSelector({
    super.key,
    required this.streams,
    required this.isLoading,
    required this.statusMessage,
    required this.onRetry,
    required this.onStreamSelected,
    this.firstStreamFocusNode,
    this.retryFocusNode,
    this.onSectionFocused,
  });

  /// Modal dialog for manual stream selection (quality, audio, provider)
  static Future<StreamSource?> showModal({
    required BuildContext context,
    required String title,
    List<StreamSource> streams = const [],
    String? imdbId,
    String mediaType = 'movie',
    int? season,
    int? episode,
    int? runtimeMinutes,
    bool autoPlay = false,
    ValueChanged<List<StreamSource>>? onStreamsLoaded,
    ValueChanged<String>? onError,
  }) {
    return showDialog<StreamSource>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) {
        return _StreamSelectorDialog(
          title: title,
          initialStreams: streams,
          imdbId: imdbId,
          mediaType: mediaType,
          season: season,
          episode: episode,
          runtimeMinutes: runtimeMinutes,
          autoPlay: autoPlay,
          onStreamsLoaded: onStreamsLoaded,
          onError: onError,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Available Streams',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        if (isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: TVTheme.primary, strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    statusMessage,
                    style: const TextStyle(color: TVTheme.textSecondary, fontSize: 14),
                  ),
                ),
              ],
            ),
          )
        else if (streams.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No streams found or failed to connect to backend server.',
                style: TextStyle(color: TVTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Focus(
                focusNode: retryFocusNode,
                onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(event, onActivate: onRetry),
                child: Builder(
                  builder: (ctx) {
                    final focused = Focus.of(ctx).hasFocus;
                    return ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: focused ? Colors.white : TVTheme.surface,
                        foregroundColor: focused ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry Fetching'),
                    );
                  },
                ),
              ),
            ],
          )
        else
          SizedBox(
            height: 56,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: streams.length,
              itemBuilder: (context, index) {
                final stream = streams[index];
                return _StreamItemButton(
                  key: ValueKey(stream.url),
                  stream: stream,
                  focusNode: index == 0 ? firstStreamFocusNode : null,
                  onSelect: () => onStreamSelected(stream),
                  onFocused: onSectionFocused,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _StreamItemButton extends StatefulWidget {
  final StreamSource stream;
  final FocusNode? focusNode;
  final VoidCallback onSelect;
  final VoidCallback? onFocused;

  const _StreamItemButton({
    super.key,
    required this.stream,
    this.focusNode,
    required this.onSelect,
    this.onFocused,
  });

  @override
  State<_StreamItemButton> createState() => _StreamItemButtonState();
}

class _StreamItemButtonState extends State<_StreamItemButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final stream = widget.stream;
    final provider = stream.provider.isNotEmpty ? stream.provider : 'Direct';
    final quality = stream.quality.isNotEmpty ? stream.quality : 'HD';
    final size = stream.formattedSize != null && stream.formattedSize!.isNotEmpty
        ? ' • ${stream.formattedSize}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(right: 14.0),
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) {
          setState(() => _isFocused = focused);
          if (focused) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
            );
            widget.onFocused?.call();
          }
        },
        onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(
          event,
          onActivate: widget.onSelect,
        ),
        child: GestureDetector(
          onTap: widget.onSelect,
          child: AnimatedScale(
            scale: _isFocused ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _isFocused ? TVTheme.surfaceElevated : TVTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isFocused ? Colors.white : Colors.white12,
                  width: _isFocused ? 2.0 : 1.0,
                ),
                boxShadow: _isFocused ? TVTheme.focusShadows : TVTheme.restingShadows,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 20,
                    color: _isFocused ? TVTheme.primary : Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$provider • $quality$size',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: _isFocused ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StreamSelectorDialog extends StatefulWidget {
  final String title;
  final List<StreamSource> initialStreams;
  final String? imdbId;
  final String mediaType;
  final int? season;
  final int? episode;
  final int? runtimeMinutes;
  final bool autoPlay;
  final ValueChanged<List<StreamSource>>? onStreamsLoaded;
  final ValueChanged<String>? onError;

  const _StreamSelectorDialog({
    required this.title,
    this.initialStreams = const [],
    this.imdbId,
    this.mediaType = 'movie',
    this.season,
    this.episode,
    this.runtimeMinutes,
    this.autoPlay = false,
    this.onStreamsLoaded,
    this.onError,
  });

  @override
  State<_StreamSelectorDialog> createState() => _StreamSelectorDialogState();
}

class _StreamSelectorDialogState extends State<_StreamSelectorDialog> {
  late List<StreamSource> _streams;
  late bool _isLoading;
  bool _isRanking = false;
  String _statusMessage = 'Connecting to scrapers...';
  StreamSubscription<StreamProgressEvent>? _sseSubscription;
  final Map<String, ({StreamProgressStatus status, int count})> _providerStatuses = {};
  final FocusNode _firstItemFocus = FocusNode();
  final FocusNode _retryFocus = FocusNode();
  final FocusNode _cancelFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _streams = List.of(widget.initialStreams);
    _isLoading = _streams.isEmpty && widget.imdbId != null && widget.imdbId!.isNotEmpty;
    if (_isLoading) _startFetching();
  }

  void _startFetching() {
    _sseSubscription?.cancel();
    setState(() {
      _isLoading = true;
      _providerStatuses.clear();
      _statusMessage = 'Connecting to scrapers for ${widget.title}...';
    });

    _sseSubscription = ApiClient.instance
        .getStreamsProgressive(
          widget.mediaType,
          widget.imdbId!,
          season: widget.season,
          episode: widget.episode,
        )
        .listen(
      (event) {
        if (!mounted) return;
        if (event.status == StreamProgressStatus.error) {
          if (event.provider != 'all') {
            setState(() {
              _providerStatuses[event.provider] = (status: StreamProgressStatus.error, count: 0);
            });
          } else {
            StreamRanker.checkInternetReachability().then((isOnline) {
              if (!mounted) return;
              final displayErr = !isOnline
                  ? 'Network error: Please check your Wi-Fi or Ethernet connection.'
                  : (event.error ?? 'Failed to load streams');
              if (widget.autoPlay) {
                Navigator.of(context).pop();
                widget.onError?.call(displayErr);
                return;
              }
              setState(() {
                _isLoading = false;
                _statusMessage = displayErr;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _retryFocus.requestFocus();
              });
            });
          }
          return;
        }

        if (event.isDone) {
          final resolvedStreams = event.streams ?? [];
          if (resolvedStreams.isEmpty) {
            _streams = [];
            _isLoading = false;
            _isRanking = false;
            widget.onStreamsLoaded?.call([]);
            setState(() {
              _statusMessage = 'No streams found for this title.';
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _retryFocus.requestFocus();
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
            runtimeMinutes: widget.runtimeMinutes,
            onProgress: (msg, probed, qual) {
              if (mounted) setState(() => _statusMessage = msg);
            },
          ).then((ranked) {
            if (!mounted) return;
            final ordered = [
              ranked.topStream,
              ...ranked.fallbackStreams,
              ...ranked.unprobedStreams,
            ];
            _streams = ordered;
            _isLoading = false;
            _isRanking = false;
            widget.onStreamsLoaded?.call(ordered);

            if (widget.autoPlay && mounted) {
              Navigator.of(context).pop(ranked.topStream);
              return;
            }

            setState(() {});
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_streams.isNotEmpty) {
                _firstItemFocus.requestFocus();
              } else {
                _retryFocus.requestFocus();
              }
            });
          }).catchError((_) {
            if (!mounted) return;
            _streams = resolvedStreams;
            _isLoading = false;
            _isRanking = false;
            widget.onStreamsLoaded?.call(resolvedStreams);
            if (widget.autoPlay && mounted) {
              Navigator.of(context).pop(resolvedStreams.first);
              return;
            }
            setState(() {});
          });
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
          if (widget.autoPlay) {
            Navigator.of(context).pop();
            widget.onError?.call(displayErr);
            return;
          }
          setState(() {
            _isLoading = false;
            _statusMessage = displayErr;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _retryFocus.requestFocus();
          });
        });
      },
      onDone: () {
        if (!mounted) return;
        if (_isLoading && !_isRanking && _streams.isEmpty) {
          setState(() => _isLoading = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _retryFocus.requestFocus();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _sseSubscription?.cancel();
    _firstItemFocus.dispose();
    _retryFocus.dispose();
    _cancelFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: TVTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: TVTheme.borderRadiusMd),
      child: Container(
        width: _isLoading ? 480 : 620,
        constraints: const BoxConstraints(maxHeight: 520),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  widget.autoPlay ? Icons.play_circle_filled : Icons.tune,
                  color: TVTheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.autoPlay ? 'Fetching Streams: ${widget.title}' : 'Select Stream: ${widget.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading) ...[
              Text(
                _statusMessage,
                style: const TextStyle(fontSize: 13, color: TVTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              const LinearProgressIndicator(
                color: TVTheme.primary,
                backgroundColor: Colors.white12,
              ),
              const SizedBox(height: 16),
              if (_providerStatuses.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _providerStatuses.entries.map((entry) {
                    final isResolved = entry.value.status == StreamProgressStatus.resolved;
                    final isSearching = entry.value.status == StreamProgressStatus.searching;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isResolved
                            ? TVTheme.primary.withValues(alpha: 0.2)
                            : isSearching
                                ? Colors.white12
                                : Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isResolved ? TVTheme.primary : Colors.white24,
                        ),
                      ),
                      child: Text(
                        '${entry.key}: ${isResolved ? "${entry.value.count} found" : isSearching ? "searching..." : "failed"}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isResolved ? TVTheme.primary : Colors.white70,
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ] else ...[
              const Text(
                'Select preferred quality, audio language, or source provider:',
                style: TextStyle(fontSize: 13, color: TVTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _streams.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'No playable streams found.',
                              style: TextStyle(color: TVTheme.textMuted, fontSize: 14),
                            ),
                            const SizedBox(height: 12),
                            if (widget.imdbId != null && widget.imdbId!.isNotEmpty)
                              ElevatedButton.icon(
                                focusNode: _retryFocus,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: TVTheme.primary,
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: _startFetching,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _streams.length,
                        itemBuilder: (ctx, idx) {
                          final s = _streams[idx];
                          return _DialogStreamRow(
                            stream: s,
                            autofocus: idx == 0,
                            focusNode: idx == 0 ? _firstItemFocus : null,
                            onSelect: () => Navigator.of(context).pop(s),
                          );
                        },
                      ),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                focusNode: _cancelFocus,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogStreamRow extends StatefulWidget {
  final StreamSource stream;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback onSelect;

  const _DialogStreamRow({
    required this.stream,
    required this.autofocus,
    this.focusNode,
    required this.onSelect,
  });

  @override
  State<_DialogStreamRow> createState() => _DialogStreamRowState();
}

class _DialogStreamRowState extends State<_DialogStreamRow> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stream;
    final langs = s.languages.isNotEmpty ? s.languages.join(', ') : 'Default';

    return Focus(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(event, onActivate: widget.onSelect),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isFocused ? TVTheme.primary.withValues(alpha: 0.25) : TVTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: TVTheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  s.quality,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              if (s.headroomRatio != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: s.headroomRatio! >= 1.4
                        ? Colors.green.withValues(alpha: 0.2)
                        : s.headroomRatio! >= 1.0
                            ? Colors.amber.withValues(alpha: 0.2)
                            : Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: s.headroomRatio! >= 1.4
                          ? Colors.greenAccent
                          : s.headroomRatio! >= 1.0
                              ? Colors.amberAccent
                              : Colors.redAccent,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${s.headroomRatio!.toStringAsFixed(1)}x',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: s.headroomRatio! >= 1.4
                          ? Colors.greenAccent
                          : s.headroomRatio! >= 1.0
                              ? Colors.amberAccent
                              : Colors.redAccent,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.filename ?? '${s.provider} Stream',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Provider: ${s.provider}  •  Audio: $langs${s.formattedSize != null ? "  •  Size: ${s.formattedSize}" : ""}',
                      style: const TextStyle(fontSize: 12, color: TVTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.chevron_right,
                color: _isFocused ? Colors.white : Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
