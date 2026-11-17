import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';

class StreamSelector {
  static Future<StreamSource?> showModal({
    required BuildContext context,
    required String title,
    List<StreamSource> streams = const [],
    String? imdbId,
    String mediaType = 'movie',
    int? season,
    int? episode,
    List<String> genres = const [],
    String? originalLanguage,
    String? defaultLanguage,
    bool refresh = false,
    int? runtimeMinutes,
    bool autoPlay = false,
    ValueChanged<List<StreamSource>>? onStreamsLoaded,
    ValueChanged<String>? onError,
  }) {
    return showDialog<StreamSource>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return _StreamSelectorDialog(
          title: title,
          initialStreams: streams,
          imdbId: imdbId,
          mediaType: mediaType,
          season: season,
          episode: episode,
          genres: genres,
          originalLanguage: originalLanguage,
          defaultLanguage: defaultLanguage,
          refresh: refresh,
          runtimeMinutes: runtimeMinutes,
          autoPlay: autoPlay,
          onStreamsLoaded: onStreamsLoaded,
          onError: onError,
        );
      },
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
  final List<String> genres;
  final String? originalLanguage;
  final String? defaultLanguage;
  final bool refresh;
  final int? runtimeMinutes;
  final bool autoPlay;
  final ValueChanged<List<StreamSource>>? onStreamsLoaded;
  final ValueChanged<String>? onError;

  const _StreamSelectorDialog({
    required this.title,
    required this.initialStreams,
    this.imdbId,
    required this.mediaType,
    this.season,
    this.episode,
    this.genres = const [],
    this.originalLanguage,
    this.defaultLanguage,
    this.refresh = false,
    this.runtimeMinutes,
    this.autoPlay = false,
    this.onStreamsLoaded,
    this.onError,
  });

  @override
  State<_StreamSelectorDialog> createState() => _StreamSelectorDialogState();
}

class _StreamSelectorDialogState extends State<_StreamSelectorDialog> {
  bool _isLoading = true;
  bool _isBackendFallback = false;
  String? _backendFallbackReason;
  String _statusMessage = 'Connecting to scrapers...';
  int _stage = 0; // 0: Scraping, 1: Health Gate, 2: Speed Probing
  int _stage1Current = 0;
  int _stage1Total = 0;
  int _stage1Healthy = 0;
  int _stage2Current = 0;
  int _stage2Total = 0;
  int _stage2Qualified = 0;
  final Map<String, ({StreamProgressStatus status, int count})> _providerStatuses = {};
  final FocusNode _retryFocus = FocusNode();
  final FocusNode _cancelFocus = FocusNode();
  String? _fatalError;

  @override
  void initState() {
    super.initState();
    _startFetching();
  }

  void _startFetching({bool isRetry = false}) async {
    setState(() {
      _isLoading = true;
      _isBackendFallback = false;
      _backendFallbackReason = null;
      _fatalError = null;
      _stage = 0;
      _stage1Current = 0;
      _stage1Total = 0;
      _stage1Healthy = 0;
      _stage2Current = 0;
      _stage2Total = 0;
      _stage2Qualified = 0;
      _providerStatuses.clear();
      _statusMessage = 'Searching scrapers for ${widget.title}...';
    });

    final orchestrator = await SourceOrchestrator.createRemoteOrchestrator();
    final target = MediaScrapeTarget(
      imdbId: widget.imdbId ?? '',
      title: widget.title,
      mediaType: widget.mediaType,
      season: widget.season,
      episode: widget.episode,
      genres: widget.genres,
      originalLanguage: widget.originalLanguage,
      defaultLanguage: widget.defaultLanguage,
    );

    try {
      final allStreams = await orchestrator.scrapeWithBackendFallback(
        target: target,
        onProgress: (msg) {
          if (!mounted) return;
          setState(() => _statusMessage = msg);
        },
        onStageProgress: (event) {
          if (!mounted) return;
          setState(() {
            _stage = event.stage;
            if (event.stage == 1) {
              _stage1Current = event.current;
              _stage1Total = event.total;
              _stage1Healthy = event.healthy;
            } else if (event.stage == 2) {
              _stage2Current = event.current;
              _stage2Total = event.total;
              _stage2Qualified = event.qualified;
            }
          });
        },
        onProviderStatus: (provider, status, count) {
          if (!mounted) return;
          setState(() {
            _providerStatuses[provider] = (status: status, count: count);
          });
        },
        onBackendFallback: (reason) {
          if (!mounted) return;
          setState(() {
            _isBackendFallback = true;
            _backendFallbackReason = reason;
          });
        },
      );

      if (!mounted) return;

      if (allStreams.isEmpty) {
        widget.onStreamsLoaded?.call([]);
        setState(() {
          _isLoading = false;
          _fatalError = 'No playable streams found for this title.';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _retryFocus.requestFocus();
        });
        return;
      }

      widget.onStreamsLoaded?.call(allStreams);

      if (mounted) {
        if (widget.autoPlay) {
          Navigator.of(context).pop(allStreams.first);
        } else {
          Navigator.of(context).pop(null);
        }
      }
    } catch (err) {
      if (!mounted) return;
      final isOnline = await StreamRanker.checkInternetReachability();
      if (!mounted) return;
      final displayErr = !isOnline
          ? 'Network error: Check Wi-Fi or Ethernet connection.'
          : 'Scrapers temporarily unavailable ($err).';

      if (widget.autoPlay) {
        Navigator.of(context).pop(null);
        widget.onError?.call(displayErr);
        return;
      }

      setState(() {
        _isLoading = false;
        _fatalError = displayErr;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _retryFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _retryFocus.dispose();
    _cancelFocus.dispose();
    super.dispose();
  }

  Widget _buildStagePill({
    required String title,
    required String stats,
    required bool isActive,
    required bool isDone,
  }) {
    Color bg = Colors.white10;
    Color border = Colors.white12;
    Color textColor = TVTheme.textMuted;
    Color statsColor = TVTheme.textMuted;
    Widget icon = const SizedBox.shrink();

    if (isDone) {
      bg = Colors.white.withValues(alpha: 0.08);
      border = Colors.white24;
      textColor = Colors.white;
      statsColor = Colors.white70;
      icon = const Padding(
        padding: EdgeInsets.only(right: 6),
        child: Icon(Icons.check, size: 13, color: Colors.white),
      );
    } else if (isActive) {
      bg = TVTheme.primary.withValues(alpha: 0.18);
      border = TVTheme.primary;
      textColor = Colors.white;
      statsColor = TVTheme.accentGlow;
      icon = const Padding(
        padding: EdgeInsets.only(right: 6),
        child: SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 2, color: TVTheme.primary),
        ),
      );
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            icon,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isActive || isDone ? FontWeight.bold : FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  Text(
                    stats,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      color: statsColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalFound = _providerStatuses.values
        .where((s) => s.status == StreamProgressStatus.resolved)
        .fold<int>(0, (sum, item) => sum + item.count);

    double? progressValue;
    if (_stage == 1 && _stage1Total > 0) {
      progressValue = (_stage1Current / _stage1Total) * 0.5;
    } else if (_stage == 2 && _stage2Total > 0) {
      progressValue = 0.5 + (_stage2Current / _stage2Total) * 0.5;
    }

    final stage1Stats = _stage1Total > 0
        ? '$_stage1Current/$_stage1Total verified ($_stage1Healthy ok)'
        : (_stage == 0 ? 'Pending' : 'Starting...');

    final stage2Stats = _stage2Total > 0
        ? '$_stage2Current/$_stage2Total tested ($_stage2Qualified qual)'
        : (_stage < 2 ? 'Pending' : 'Testing...');

    return Dialog(
      backgroundColor: TVTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: TVTheme.borderRadiusMd),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.stream, color: TVTheme.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.autoPlay ? 'Finding Streams: ${widget.title}' : 'Scraping Sources: ${widget.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (totalFound > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: TVTheme.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: TVTheme.primary.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      '$totalFound found',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _buildStagePill(
                  title: '1. Health Gate',
                  stats: stage1Stats,
                  isActive: _stage == 1,
                  isDone: _stage > 1,
                ),
                const SizedBox(width: 8),
                _buildStagePill(
                  title: '2. Speed Probing',
                  stats: stage2Stats,
                  isActive: _stage == 2,
                  isDone: !_isLoading && _fatalError == null,
                ),
              ],
            ),
            if (_isBackendFallback) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: TVTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: TVTheme.primary.withValues(alpha: 0.6), width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_sync, size: 20, color: TVTheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'FALLING BACK TO BACKEND SERVER',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: TVTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _backendFallbackReason != null
                                ? '$_backendFallbackReason. Querying server-side scrapers...'
                                : 'No client streams found. Querying server-side scrapers...',
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_fatalError != null) ...[
              Text(
                _fatalError!,
                style: const TextStyle(fontSize: 13, color: Colors.redAccent),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    focusNode: _cancelFocus,
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    focusNode: _retryFocus,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TVTheme.primary,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => _startFetching(isRetry: true),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ] else ...[
              Text(
                _statusMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: TVTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: progressValue?.clamp(0.0, 1.0),
                color: TVTheme.primary,
                backgroundColor: Colors.white12,
              ),
              if (_providerStatuses.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _providerStatuses.entries.map((entry) {
                    final isResolved = entry.value.status == StreamProgressStatus.resolved;
                    final isSearching = entry.value.status == StreamProgressStatus.searching;
                    final count = entry.value.count;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isResolved
                            ? (count > 0 ? TVTheme.primary.withValues(alpha: 0.15) : Colors.white10)
                            : isSearching
                                ? Colors.white10
                                : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isResolved
                              ? (count > 0 ? TVTheme.primary.withValues(alpha: 0.5) : Colors.white24)
                              : isSearching
                                  ? Colors.white38
                                  : Colors.white12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSearching)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(strokeWidth: 2, color: TVTheme.primary),
                              ),
                            ),
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isResolved && count > 0
                                  ? TVTheme.primary
                                  : Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isResolved
                                  ? '$count'
                                  : isSearching
                                      ? '...'
                                      : '0',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isResolved && count > 0
                                    ? Colors.white
                                    : TVTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  focusNode: _cancelFocus,
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel', style: TextStyle(color: TVTheme.textMuted)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
