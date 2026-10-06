import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';

class StreamSelectorBottomSheet extends StatefulWidget {
  final Movie movie;
  final String? title;
  final String mediaType;
  final int? season;
  final int? episode;

  const StreamSelectorBottomSheet({
    super.key,
    required this.movie,
    this.title,
    this.mediaType = 'movie',
    this.season,
    this.episode,
  });

  static Future<Map<String, dynamic>?> show({
    required BuildContext context,
    required Movie movie,
    String? title,
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StreamSelectorBottomSheet(
        movie: movie,
        title: title,
        mediaType: mediaType,
        season: season,
        episode: episode,
      ),
    );
  }

  @override
  State<StreamSelectorBottomSheet> createState() => _StreamSelectorBottomSheetState();
}

class _StreamSelectorBottomSheetState extends State<StreamSelectorBottomSheet> {
  List<Map<String, dynamic>> _streams = [];
  bool _isLoading = true;
  String _statusMessage = 'Connecting to scrapers...';
  int _cacheExpiresIn = 0;
  Timer? _cacheTimer;

  @override
  void initState() {
    super.initState();
    _fetchStreams();
  }

  @override
  void dispose() {
    _cacheTimer?.cancel();
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
      mediaType: widget.mediaType,
      season: widget.season,
      episode: widget.episode,
      bypassCache: bypassCache,
      onProgress: (status) {
        if (mounted) {
          setState(() {
            _statusMessage = status;
          });
        }
      },
    );

    if (mounted) {
      final List<Map<String, dynamic>> list = [];
      if (response['streams'] is List) {
        for (final item in response['streams']) {
          if (item is Map) {
            list.add(item.cast<String, dynamic>());
          }
        }
      }

      final ttl = response['cache_expires_in'] as int? ?? 0;

      setState(() {
        _streams = list;
        _isLoading = false;
        _cacheExpiresIn = ttl;
        if (list.isEmpty) {
          _statusMessage = 'No streams found from scrapers.';
        }
      });

      if (_cacheExpiresIn > 0) {
        _startCacheTimer();
      }
    }
  }

  void _startCacheTimer() {
    _cacheTimer?.cancel();
    _cacheTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cacheExpiresIn > 0) {
        setState(() => _cacheExpiresIn--);
      } else {
        timer.cancel();
      }
    });
  }

  String _formatTtl(int seconds) {
    if (seconds <= 0) return 'Expired';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Color _getQualityColor(String quality) {
    final q = quality.toUpperCase();
    if (q.contains('4K') || q.contains('UHD') || q.contains('2160')) return Colors.amber;
    if (q.contains('1080')) return MobileTheme.accent;
    if (q.contains('720')) return Colors.blueAccent;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle = widget.title ?? widget.movie.title;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: MobileTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Stream Source',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: MobileTheme.textPrimary,
                        ),
                      ),
                      Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: MobileTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isLoading) ...[
                  if (_cacheExpiresIn > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Cache: ${_formatTtl(_cacheExpiresIn)}',
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Force Rescrape',
                    icon: const Icon(Icons.refresh_rounded, color: MobileTheme.accent, size: 22),
                    onPressed: () => _fetchStreams(bypassCache: true),
                  ),
                ],
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 20),
          // Content
          Flexible(
            child: _isLoading
                ? _buildLoadingState()
                : (_streams.isEmpty ? _buildEmptyState() : _buildStreamsList()),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3, color: MobileTheme.accent),
          ),
          const SizedBox(height: 20),
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_outlined, color: Colors.white30, size: 48),
          const SizedBox(height: 12),
          const Text(
            'No stream links available',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Scrapers could not find direct playable links. Try rescraping or check back later.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: MobileTheme.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Rescrape Sources'),
            onPressed: () => _fetchStreams(bypassCache: true),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamsList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      shrinkWrap: true,
      physics: const BouncingScrollPhysics(),
      itemCount: _streams.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final stream = _streams[index];
        final quality = stream['quality']?.toString() ?? 'Auto';
        final provider = stream['provider']?.toString() ?? 'Direct Stream';
        final latency = stream['latency_ms'] as num?;
        final qColor = _getQualityColor(quality);

        return Material(
          color: MobileTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.pop(context, stream),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: qColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: qColor.withValues(alpha: 0.4), width: 1),
                    ),
                    child: Text(
                      quality.toUpperCase(),
                      style: TextStyle(
                        color: qColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (latency != null)
                          Text(
                            '${latency.toInt()}ms response',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.play_circle_filled_rounded, color: MobileTheme.accent, size: 28),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
