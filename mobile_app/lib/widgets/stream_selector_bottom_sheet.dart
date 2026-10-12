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
      useSafeArea: true,
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
  List<StreamSource> _streamSources = [];
  bool _isLoading = true;
  String _statusMessage = 'Connecting to scrapers...';
  int _cacheExpiresIn = 0;
  Timer? _cacheTimer;
  String? _selectedQuality;
  String? _selectedLanguage;

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
      _selectedQuality = null;
      _selectedLanguage = null;
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
      final List<StreamSource> list = [];
      if (response['streams'] is List) {
        for (final item in response['streams']) {
          if (item is Map) {
            list.add(StreamSource.fromJson(item.cast<String, dynamic>()));
          }
        }
      }

      list.sort((a, b) {
        final p = a.priority.compareTo(b.priority);
        if (p != 0) return p;
        final bBitrate = b.bitrateKbps ?? 0;
        final aBitrate = a.bitrateKbps ?? 0;
        if (bBitrate != aBitrate) return bBitrate.compareTo(aBitrate);
        return (b.sizeMb ?? 0).compareTo(a.sizeMb ?? 0);
      });

      final ttl = response['cache_expires_in'] as int? ?? 0;

      setState(() {
        _streamSources = list;
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
      setState(() {
        if (_cacheExpiresIn > 0) {
          _cacheExpiresIn--;
        }
        for (int i = 0; i < _streamSources.length; i++) {
          if (_streamSources[i].remainingTtl > 0) {
            _streamSources[i] = _streamSources[i].copyWith(
              remainingTtl: _streamSources[i].remainingTtl - 1,
            );
          }
        }
      });
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
    if (q.contains('1080') || q.contains('FHD')) return const Color(0xFF00E676);
    if (q.contains('720') || q.contains('HD')) return Colors.lightBlueAccent;
    if (q.contains('480') || q.contains('SD')) return Colors.white60;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle = widget.title ?? widget.movie.title;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
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
                : (_streamSources.isEmpty ? _buildEmptyState() : _buildStreamsList()),
          ),
        ],
      ),
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

  Widget _buildFilterChips() {
    final qualities = _streamSources.map((s) => s.quality).toSet().toList();
    final languages = _streamSources.expand((s) => s.languages).toSet().toList();

    if (qualities.length <= 1 && languages.length <= 1) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 32,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildChoiceChip(
            label: 'All (${_streamSources.length})',
            isSelected: _selectedQuality == null && _selectedLanguage == null,
            onTap: () {
              setState(() {
                _selectedQuality = null;
                _selectedLanguage = null;
              });
            },
          ),
          if (qualities.length > 1) ...[
            const SizedBox(width: 6),
            ...qualities.map((q) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildChoiceChip(
                    label: q,
                    isSelected: _selectedQuality == q,
                    onTap: () {
                      setState(() {
                        _selectedQuality = _selectedQuality == q ? null : q;
                      });
                    },
                  ),
                )),
          ],
          if (languages.length > 1) ...[
            const SizedBox(width: 4),
            ...languages.map((lang) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildChoiceChip(
                    label: lang,
                    icon: Icons.audiotrack_rounded,
                    isSelected: _selectedLanguage == lang,
                    onTap: () {
                      setState(() {
                        _selectedLanguage = _selectedLanguage == lang ? null : lang;
                      });
                    },
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildChoiceChip({
    required String label,
    IconData? icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? MobileTheme.accent : MobileTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? MobileTheme.accent : Colors.white12,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: isSelected ? Colors.white : Colors.white70),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : MobileTheme.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaPill({
    required IconData icon,
    required String label,
    Color color = Colors.white70,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamCard(StreamSource stream) {
    final qColor = _getQualityColor(stream.quality);
    final isExpired = stream.isExpired;

    return Material(
      color: MobileTheme.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(context, stream.toJson()),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isExpired
                  ? Colors.redAccent.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: qColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: qColor.withValues(alpha: 0.4), width: 1),
                    ),
                    child: Text(
                      stream.quality.toUpperCase(),
                      style: TextStyle(
                        color: qColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (stream.displaySize.isNotEmpty) ...[
                    _buildMetaPill(
                      icon: Icons.folder_zip_outlined,
                      label: stream.displaySize,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (stream.bitrateStr != null && stream.bitrateStr!.isNotEmpty) ...[
                    _buildMetaPill(
                      icon: Icons.speed_rounded,
                      label: stream.bitrateStr!,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (stream.remainingTtl > 0) ...[
                    _buildMetaPill(
                      icon: Icons.schedule_rounded,
                      label: stream.formattedRemainingTtl,
                      color: stream.remainingTtl < 300 ? Colors.orangeAccent : Colors.white60,
                    ),
                  ] else if (isExpired) ...[
                    _buildMetaPill(
                      icon: Icons.warning_amber_rounded,
                      label: 'Expired',
                      color: Colors.redAccent,
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    isExpired ? Icons.refresh_rounded : Icons.play_circle_filled_rounded,
                    color: isExpired ? Colors.redAccent : MobileTheme.accent,
                    size: 28,
                  ),
                ],
              ),
              if (stream.languages.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.audiotrack_rounded,
                      size: 13,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: stream.languages.map((lang) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              lang,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.dns_outlined,
                    size: 13,
                    color: MobileTheme.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      stream.sourceHierarchy,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MobileTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (stream.priority <= 10)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'P${stream.priority}',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              if (stream.filename != null && stream.filename!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  stream.filename!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MobileTheme.textMuted,
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreamsList() {
    final displayedStreams = _streamSources.where((s) {
      if (_selectedQuality != null && s.quality != _selectedQuality) {
        return false;
      }
      if (_selectedLanguage != null && !s.languages.contains(_selectedLanguage)) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilterChips(),
        if (displayedStreams.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const Text(
                  'No streams match the selected filter',
                  style: TextStyle(color: MobileTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedQuality = null;
                      _selectedLanguage = null;
                    });
                  },
                  child: const Text('Reset Filters'),
                ),
              ],
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: displayedStreams.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _buildStreamCard(displayedStreams[index]);
              },
            ),
          ),
      ],
    );
  }
}
