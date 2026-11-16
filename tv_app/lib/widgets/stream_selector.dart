import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      barrierColor: Colors.black.withValues(alpha: 0.7),
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
                  if (widget.stream.isFailed && widget.stream.failureReason != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.redAccent, width: 1),
                      ),
                      child: Text(
                        widget.stream.failureReason!,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
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
    this.initialStreams = const [],
    this.imdbId,
    this.mediaType = 'movie',
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
  late List<StreamSource> _streams;
  int _selectedTab = 0;
  late bool _isLoading;
  String _statusMessage = 'Connecting to scrapers...';
  StreamSubscription<StreamProgressEvent>? _sseSubscription;
  final Map<String, ({StreamProgressStatus status, int count})> _providerStatuses = {};
  final FocusNode _firstItemFocus = FocusNode();
  final FocusNode _streamsTabFocus = FocusNode();
  final FocusNode _failedTabFocus = FocusNode();
  final FocusNode _retryFocus = FocusNode();
  final FocusNode _cancelFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _streams = List.of(widget.initialStreams);
    _isLoading = _streams.isEmpty && widget.imdbId != null && widget.imdbId!.isNotEmpty;
    if (_isLoading) _startFetching();
  }

  void _startFetching({bool isRetry = false}) async {
    _sseSubscription?.cancel();
    setState(() {
      _isLoading = true;
      _providerStatuses.clear();
      _statusMessage = 'Searching Batch 1 scrapers for ${widget.title}...';
    });

    final orchestrator = SourceOrchestrator();
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
          if (mounted) setState(() => _statusMessage = msg);
        },
        onProviderStatus: (provider, status, count) {
          if (!mounted) return;
          setState(() {
            _providerStatuses[provider] = (status: status, count: count);
          });
        },
      );
      if (!mounted) return;

      if (allStreams.isEmpty) {
        _streams = [];
        _isLoading = false;
        widget.onStreamsLoaded?.call([]);
        setState(() {
          _statusMessage = 'No streams found for this title.';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _retryFocus.requestFocus();
        });
        return;
      }

      _streams = allStreams;
      _isLoading = false;
      widget.onStreamsLoaded?.call(allStreams);

      if (widget.autoPlay && mounted) {
        Navigator.of(context).pop(allStreams.first);
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
    } catch (err) {
      if (!mounted) return;
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
    }
  }

  @override
  void dispose() {
    _sseSubscription?.cancel();
    _firstItemFocus.dispose();
    _streamsTabFocus.dispose();
    _failedTabFocus.dispose();
    _retryFocus.dispose();
    _cancelFocus.dispose();
    super.dispose();
  }

  Widget _buildTab({
    FocusNode? focusNode,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    bool isError = false,
    VoidCallback? onDown,
    VoidCallback? onLeft,
    VoidCallback? onRight,
  }) {
    return _SelectorTabButton(
      focusNode: focusNode,
      label: label,
      isSelected: isSelected,
      onTap: onTap,
      isError: isError,
      onDown: onDown,
      onLeft: onLeft,
      onRight: onRight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeStreams = _streams.where((s) => !s.isFailed).toList()
      ..sort(StreamRanker.compareBySpeed);
    final failedStreams = _streams.where((s) => s.isFailed).toList();
    final displayedStreams = _selectedTab == 0 ? activeStreams : failedStreams;

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
              Row(
                children: [
                  _buildTab(
                    focusNode: _streamsTabFocus,
                    label: 'Streams (${activeStreams.length})',
                    isSelected: _selectedTab == 0,
                    onTap: () => setState(() => _selectedTab = 0),
                    onRight: () => _failedTabFocus.requestFocus(),
                    onDown: () => _firstItemFocus.requestFocus(),
                  ),
                  const SizedBox(width: 8),
                  _buildTab(
                    focusNode: _failedTabFocus,
                    label: 'Failed (${failedStreams.length})',
                    isSelected: _selectedTab == 1,
                    isError: true,
                    onTap: () => setState(() => _selectedTab = 1),
                    onLeft: () => _streamsTabFocus.requestFocus(),
                    onDown: () => _firstItemFocus.requestFocus(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: displayedStreams.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedTab == 0 ? 'No playable streams found.' : 'No failed streams.',
                              style: const TextStyle(color: TVTheme.textMuted, fontSize: 14),
                            ),
                            const SizedBox(height: 12),
                            if (widget.imdbId != null && widget.imdbId!.isNotEmpty && _selectedTab == 0)
                              ElevatedButton.icon(
                                focusNode: _retryFocus,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: TVTheme.primary,
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: () => _startFetching(isRetry: true),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: displayedStreams.length,
                        itemBuilder: (ctx, idx) {
                          final s = displayedStreams[idx];
                          return _DialogStreamRow(
                            stream: s,
                            autofocus: idx == 0,
                            focusNode: idx == 0 ? _firstItemFocus : null,
                            onUp: idx == 0 ? () => (_selectedTab == 0 ? _streamsTabFocus : _failedTabFocus).requestFocus() : null,
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

class _SelectorTabButton extends StatefulWidget {
  final FocusNode? focusNode;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isError;
  final VoidCallback? onDown;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _SelectorTabButton({
    this.focusNode,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isError = false,
    this.onDown,
    this.onLeft,
    this.onRight,
  });

  @override
  State<_SelectorTabButton> createState() => _SelectorTabButtonState();
}

class _SelectorTabButtonState extends State<_SelectorTabButton> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected;
    final isHighlighted = _isFocused || _isHovered;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (TvShortcuts.isActivateKey(event.logicalKey)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: active
                  ? (widget.isError ? Colors.red.withValues(alpha: 0.25) : TVTheme.primary.withValues(alpha: 0.25))
                  : isHighlighted
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isHighlighted
                    ? Colors.white
                    : active
                        ? (widget.isError ? Colors.redAccent : TVTheme.primary)
                        : Colors.transparent,
                width: isHighlighted ? 2.0 : 1.5,
              ),
              boxShadow: isHighlighted ? TVTheme.focusShadows : [],
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active || isHighlighted ? FontWeight.bold : FontWeight.w500,
                color: isHighlighted
                    ? Colors.white
                    : active
                        ? (widget.isError ? Colors.redAccent : TVTheme.primary)
                        : Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogStreamRow extends StatefulWidget {
  final StreamSource stream;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onUp;
  final VoidCallback onSelect;

  const _DialogStreamRow({
    required this.stream,
    required this.autofocus,
    this.focusNode,
    this.onUp,
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
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (TvShortcuts.isActivateKey(event.logicalKey)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
          if (widget.onUp != null && event.logicalKey == LogicalKeyboardKey.arrowUp) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
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
                  color: s.isFailed ? Colors.redAccent : TVTheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  s.quality,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: s.isFailed ? Colors.white : Colors.black,
                  ),
                ),
              ),
              if (s.isFailed && s.failureReason != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.redAccent, width: 1),
                  ),
                  child: Text(
                    s.failureReason!,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ],
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
