import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import 'tv_shortcuts.dart';

Future<T?> showSidePanelDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required String barrierLabel,
  double width = 420.0,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, anim1, anim2) {
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: (MediaQuery.of(ctx).size.width * 0.35).clamp(340.0, width),
          height: double.infinity,
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xF707080B),
                  border: Border(
                    left: BorderSide(color: Color(0x33FFFFFF), width: 1.5),
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black87, blurRadius: 24, spreadRadius: 4),
                  ],
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                    child: builder(ctx),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim1, anim2, child) {
      final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      );
    },
  );
}

class AudioPickerDialog extends StatelessWidget {
  final List<AudioTrack> tracks;
  final AudioTrack selectedTrack;

  const AudioPickerDialog({
    super.key,
    required this.tracks,
    required this.selectedTrack,
  });

  static Future<AudioTrack?> show({
    required BuildContext context,
    required List<AudioTrack> tracks,
    required AudioTrack selectedTrack,
  }) {
    return showSidePanelDialog<AudioTrack>(
      context: context,
      barrierLabel: 'Dismiss Audio',
      builder: (ctx) => AudioPickerDialog(
        tracks: tracks,
        selectedTrack: selectedTrack,
      ),
    );
  }

  static String formatAudioTrackLabel(AudioTrack t) {
    final lang = t.language ?? '';
    final title = t.title ?? '';
    final id = t.id;
    if (title.isNotEmpty && lang.isNotEmpty) return '$title ($lang)';
    if (title.isNotEmpty) return title;
    if (lang.isNotEmpty) return lang.toUpperCase();
    return 'Track #$id';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.audiotrack_rounded, color: TVTheme.primary, size: 24),
            const SizedBox(width: 12),
            const Text(
              'Audio Tracks',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Colors.white12),
        const SizedBox(height: 12),
        Expanded(
          child: tracks.isEmpty
              ? const Center(
                  child: Text(
                    'No alternative audio tracks available',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                )
              : ListView.separated(
                  itemCount: tracks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) {
                    final t = tracks[idx];
                    final isSelected = selectedTrack.id == t.id;
                    return _DialogTile(
                      label: formatAudioTrackLabel(t),
                      isSelected: isSelected,
                      autofocus: isSelected || (idx == 0 && (selectedTrack.id == 'no' || selectedTrack.id == 'auto')),
                      isFirst: idx == 0,
                      isLast: idx == tracks.length - 1,
                      onSelected: () => Navigator.of(context).pop(t),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class SourcesPickerDialog extends StatefulWidget {
  final List<StreamSource> streams;
  final String currentStreamUrl;
  final String mediaType;
  final String imdbId;
  final String? title;
  final int? season;
  final int? episode;
  final int? year;
  final List<String>? genres;
  final String? originalLanguage;
  final String? defaultLanguage;
  final ValueChanged<List<StreamSource>>? onStreamsDiscovered;

  const SourcesPickerDialog({
    super.key,
    required this.streams,
    required this.currentStreamUrl,
    required this.mediaType,
    required this.imdbId,
    this.title,
    this.season,
    this.episode,
    this.year,
    this.genres,
    this.originalLanguage,
    this.defaultLanguage,
    this.onStreamsDiscovered,
  });

  static Future<StreamSource?> show({
    required BuildContext context,
    required List<StreamSource> streams,
    required String currentStreamUrl,
    required String mediaType,
    required String imdbId,
    String? title,
    int? season,
    int? episode,
    int? year,
    List<String>? genres,
    String? originalLanguage,
    String? defaultLanguage,
    ValueChanged<List<StreamSource>>? onStreamsDiscovered,
  }) {
    return showSidePanelDialog<StreamSource>(
      context: context,
      barrierLabel: 'Dismiss Sources',
      width: 460,
      builder: (ctx) => SourcesPickerDialog(
        streams: streams,
        currentStreamUrl: currentStreamUrl,
        mediaType: mediaType,
        imdbId: imdbId,
        title: title,
        season: season,
        episode: episode,
        year: year,
        genres: genres,
        originalLanguage: originalLanguage,
        defaultLanguage: defaultLanguage,
        onStreamsDiscovered: onStreamsDiscovered,
      ),
    );
  }

  @override
  State<SourcesPickerDialog> createState() => _SourcesPickerDialogState();
}

class _SourcesPickerDialogState extends State<SourcesPickerDialog> {
  late List<StreamSource> _availableStreams;
  bool _isLoading = false;
  bool _isScrapingMore = false;
  int _currentBatch = 1;
  int _totalBatches = 1;
  String _sseMessage = 'Connecting to scrapers...';
  late final SourceOrchestrator _orchestrator;
  late final MediaScrapeTarget _target;

  @override
  void initState() {
    super.initState();
    _availableStreams = List.of(widget.streams);
    _target = MediaScrapeTarget(
      imdbId: widget.imdbId,
      title: widget.title ?? widget.imdbId,
      mediaType: widget.mediaType,
      season: widget.season,
      episode: widget.episode,
      year: widget.year,
      genres: widget.genres ?? const [],
      originalLanguage: widget.originalLanguage,
      defaultLanguage: widget.defaultLanguage,
    );
    _orchestrator = SourceOrchestrator();
    final plans = _orchestrator.planBatches(_target);
    _totalBatches = plans.isEmpty ? 1 : plans.length;

    if (_availableStreams.isEmpty && widget.imdbId.isNotEmpty) {
      _loadSources();
    }
  }

  void _loadSources() async {
    setState(() {
      _isLoading = true;
      _currentBatch = 1;
      _sseMessage = 'Searching Batch 1 sources...';
    });

    try {
      final streams = await _orchestrator.scrapeWithBackendFallback(
        target: _target,
        onProgress: (msg) {
          if (mounted) setState(() => _sseMessage = msg);
        },
      );
      if (!mounted) return;
      setState(() {
        _availableStreams = streams;
        _isLoading = false;
      });
      widget.onStreamsDiscovered?.call(streams);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _scrapeNextBatch() async {
    if (_isScrapingMore || _currentBatch >= _totalBatches) return;
    final nextBatch = _currentBatch + 1;
    setState(() {
      _isScrapingMore = true;
      _sseMessage = 'Scraping Batch $nextBatch...';
    });

    try {
      final result = await _orchestrator.scrapeBatch(
        target: _target,
        batchNumber: nextBatch,
        onProgress: (msg) {
          if (mounted) setState(() => _sseMessage = msg);
        },
      );
      if (!mounted) return;

      final existingUrls = _availableStreams.map((s) => s.url).toSet();
      final newStreams = result.streams.where((s) => !existingUrls.contains(s.url)).toList();
      final combined = [..._availableStreams, ...newStreams];

      setState(() {
        _availableStreams = combined;
        _currentBatch = nextBatch;
        _isScrapingMore = false;
      });
      widget.onStreamsDiscovered?.call(combined);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isScrapingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.tune_rounded, color: TVTheme.primary, size: 24),
            const SizedBox(width: 12),
            const Text(
              'Sources',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (_isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: TVTheme.primary, strokeWidth: 2),
              ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Colors.white12),
        const SizedBox(height: 12),
        Expanded(
          child: _isLoading && _availableStreams.isEmpty
              ? Focus(
                  autofocus: true,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(color: TVTheme.primary, strokeWidth: 3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _sseMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: const LinearProgressIndicator(
                              minHeight: 3,
                              color: TVTheme.primary,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : _availableStreams.isEmpty
                  ? const Center(
                      child: Text(
                        'No streams found',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _availableStreams.length + ((_currentBatch < _totalBatches || _isScrapingMore) ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, idx) {
                        if (idx == _availableStreams.length) {
                          return _ScrapeMoreTile(
                            currentBatch: _currentBatch,
                            totalBatches: _totalBatches,
                            isLoading: _isScrapingMore,
                            onScrapeMore: _scrapeNextBatch,
                            isLast: true,
                          );
                        }
                        final s = _availableStreams[idx];
                        final isSelected = s.url == widget.currentStreamUrl;
                        final hasScrapeMore = (_currentBatch < _totalBatches || _isScrapingMore);
                        return _SourceItemTile(
                          stream: s,
                          isSelected: isSelected,
                          autofocus: isSelected || (idx == 0 && widget.currentStreamUrl.isEmpty),
                          isFirst: idx == 0,
                          isLast: !hasScrapeMore && idx == _availableStreams.length - 1,
                          onSelected: () => Navigator.of(context).pop(s),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _SourceItemTile extends StatefulWidget {
  final StreamSource stream;
  final bool isSelected;
  final bool autofocus;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onSelected;

  const _SourceItemTile({
    required this.stream,
    required this.isSelected,
    required this.autofocus,
    this.isFirst = false,
    this.isLast = false,
    required this.onSelected,
  });

  @override
  State<_SourceItemTile> createState() => _SourceItemTileState();
}

class _SourceItemTileState extends State<_SourceItemTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stream;
    final langs = s.languages.isNotEmpty ? s.languages.join(', ') : 'Default';

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _isFocused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (TvShortcuts.isActivateKey(event.logicalKey)) {
            widget.onSelected();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            return KeyEventResult.handled;
          }
          if (widget.isFirst && event.logicalKey == LogicalKeyboardKey.arrowUp) {
            return KeyEventResult.handled;
          }
          if (widget.isLast && event.logicalKey == LogicalKeyboardKey.arrowDown) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isFocused
                ? TVTheme.primary.withValues(alpha: 0.25)
                : widget.isSelected
                    ? TVTheme.surfaceElevated
                    : TVTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? Colors.white
                  : widget.isSelected
                      ? TVTheme.primary.withValues(alpha: 0.7)
                      : Colors.transparent,
              width: 2,
            ),
            boxShadow: _isFocused ? TVTheme.focusShadows : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: TVTheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      s.quality.isNotEmpty ? s.quality : 'HD',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  if (s.headroomRatio != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                        '${s.headroomRatio!.toStringAsFixed(1)}x Headroom',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          color: s.headroomRatio! >= 1.4
                              ? Colors.greenAccent
                              : s.headroomRatio! >= 1.0
                                  ? Colors.amberAccent
                                  : Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (widget.isSelected)
                    const Icon(Icons.check_circle_rounded, color: TVTheme.primary, size: 18),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                s.filename?.isNotEmpty == true ? s.filename! : '${s.provider} Stream',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${s.provider.toUpperCase()}  •  Audio: $langs${s.formattedSize != null ? "  •  ${s.formattedSize}" : ""}',
                style: const TextStyle(fontSize: 11, color: TVTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrapeMoreTile extends StatefulWidget {
  final int currentBatch;
  final int totalBatches;
  final bool isLoading;
  final VoidCallback onScrapeMore;
  final bool isLast;

  const _ScrapeMoreTile({
    required this.currentBatch,
    required this.totalBatches,
    required this.isLoading,
    required this.onScrapeMore,
    this.isLast = false,
  });

  @override
  State<_ScrapeMoreTile> createState() => _ScrapeMoreTileState();
}

class _ScrapeMoreTileState extends State<_ScrapeMoreTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        setState(() => _isFocused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (TvShortcuts.isActivateKey(event.logicalKey)) {
            if (!widget.isLoading) widget.onScrapeMore();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            return KeyEventResult.handled;
          }
          if (widget.isLast && event.logicalKey == LogicalKeyboardKey.arrowDown) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.isLoading ? null : widget.onScrapeMore,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _isFocused
                ? TVTheme.primary.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? TVTheme.primary : Colors.white12,
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isLoading) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: TVTheme.primary,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Scraping next batch...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else ...[
                const Icon(Icons.add_circle_outline_rounded,
                    color: TVTheme.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Scrape More (Batch ${widget.currentBatch + 1} of ${widget.totalBatches})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EpisodesPickerDialog extends StatefulWidget {
  final String imdbId;
  final int? tmdbId;
  final String? originalLanguage;
  final int currentSeason;
  final int? currentEpisode;
  final List<SeasonSummary> seasonsList;
  final TvSeason? initialSeason;
  final Future<TvSeason?> Function(int seasonNum)? onSeasonChanged;

  const EpisodesPickerDialog({
    super.key,
    required this.imdbId,
    this.tmdbId,
    this.originalLanguage,
    required this.currentSeason,
    this.currentEpisode,
    required this.seasonsList,
    this.initialSeason,
    this.onSeasonChanged,
  });

  static Future<TvEpisode?> show({
    required BuildContext context,
    required String imdbId,
    int? tmdbId,
    String? originalLanguage,
    required int currentSeason,
    int? currentEpisode,
    required List<SeasonSummary> seasonsList,
    TvSeason? initialSeason,
    Future<TvSeason?> Function(int seasonNum)? onSeasonChanged,
  }) {
    return showSidePanelDialog<TvEpisode>(
      context: context,
      barrierLabel: 'Dismiss Episodes',
      width: 440,
      builder: (ctx) => EpisodesPickerDialog(
        imdbId: imdbId,
        tmdbId: tmdbId,
        originalLanguage: originalLanguage,
        currentSeason: currentSeason,
        currentEpisode: currentEpisode,
        seasonsList: seasonsList,
        initialSeason: initialSeason,
        onSeasonChanged: onSeasonChanged,
      ),
    );
  }

  @override
  State<EpisodesPickerDialog> createState() => _EpisodesPickerDialogState();
}

class _EpisodesPickerDialogState extends State<EpisodesPickerDialog> {
  late int _selectedSeason;
  TvSeason? _currentSeasonData;
  bool _isLoadingSeason = false;

  final FocusNode _firstEpisodeFocusNode = FocusNode();
  final FocusNode _activeSeasonPillFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.currentSeason;
    _currentSeasonData = widget.initialSeason;
    if (_currentSeasonData == null) {
      _loadSeason(_selectedSeason);
    }
  }

  @override
  void dispose() {
    _firstEpisodeFocusNode.dispose();
    _activeSeasonPillFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSeason(int seasonNum) async {
    setState(() {
      _isLoadingSeason = true;
      _selectedSeason = seasonNum;
    });

    if (widget.onSeasonChanged != null) {
      final season = await widget.onSeasonChanged!(seasonNum);
      if (mounted) {
        setState(() {
          _currentSeasonData = season;
          _isLoadingSeason = false;
        });
      }
      return;
    }

    try {
      int? tmdbId = widget.tmdbId;
      if ((tmdbId == null || tmdbId == 0) && widget.imdbId.isNotEmpty) {
        final details = await ApiClient.instance.getMovieDetails('tv', widget.imdbId);
        tmdbId = details.tmdbId;
      }
      if (tmdbId != null && tmdbId > 0) {
        final season = await ApiClient.instance.getTvSeason(tmdbId, seasonNum);
        if (mounted) {
          setState(() {
            _currentSeasonData = season;
            _isLoadingSeason = false;
          });
        }
        return;
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoadingSeason = false);
  }

  @override
  Widget build(BuildContext context) {
    final episodes = _currentSeasonData?.episodes ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.video_library_rounded, color: TVTheme.primary, size: 24),
            const SizedBox(width: 12),
            const Text(
              'Episodes',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (_isLoadingSeason)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: TVTheme.primary, strokeWidth: 2),
              ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (widget.seasonsList.length > 1) ...[
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.seasonsList.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, idx) {
                final s = widget.seasonsList[idx];
                final isSelected = s.seasonNumber == _selectedSeason;
                return _SeasonPill(
                  focusNode: isSelected ? _activeSeasonPillFocusNode : null,
                  label: s.name.isNotEmpty ? s.name : 'Season ${s.seasonNumber}',
                  isSelected: isSelected,
                  isFirst: idx == 0,
                  isLast: idx == widget.seasonsList.length - 1,
                  onSelected: () {
                    if (s.seasonNumber != _selectedSeason) {
                      _loadSeason(s.seasonNumber);
                    }
                  },
                  onDown: () => _firstEpisodeFocusNode.requestFocus(),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        const Divider(height: 1, color: Colors.white12),
        const SizedBox(height: 12),
        Expanded(
          child: _isLoadingSeason
              ? const Center(
                  child: CircularProgressIndicator(color: TVTheme.primary, strokeWidth: 3),
                )
              : episodes.isEmpty
                  ? const Center(
                      child: Text('No episodes found', style: TextStyle(color: Colors.white70)),
                    )
                  : ListView.separated(
                      itemCount: episodes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, idx) {
                        final ep = episodes[idx];
                        final isPlayingThis = ep.episodeNumber == widget.currentEpisode &&
                            _selectedSeason == widget.currentSeason;
                        final subtitleParts = <String>[];
                        if (ep.formattedRuntime.isNotEmpty) subtitleParts.add(ep.formattedRuntime);
                        if (ep.formattedAirDate.isNotEmpty) {
                          subtitleParts.add(ep.isUpcoming ? 'Airs ${ep.formattedAirDate}' : ep.formattedAirDate);
                        }
                        if (ep.isUpcoming) subtitleParts.add('Unreleased');

                        return _DialogTile(
                          focusNode: idx == 0 ? _firstEpisodeFocusNode : null,
                          autofocus: isPlayingThis || (idx == 0 && widget.currentEpisode == null),
                          label: 'E${ep.episodeNumber}: ${ep.name}',
                          subtitle: subtitleParts.isNotEmpty ? subtitleParts.join(' • ') : null,
                          isSelected: isPlayingThis,
                          isFirst: idx == 0,
                          isLast: idx == episodes.length - 1,
                          onUp: idx == 0 && widget.seasonsList.length > 1
                              ? () => _activeSeasonPillFocusNode.requestFocus()
                              : null,
                          onSelected: () => Navigator.of(context).pop(ep),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _SeasonPill extends StatefulWidget {
  final FocusNode? focusNode;
  final String label;
  final bool isSelected;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onSelected;
  final VoidCallback onDown;

  const _SeasonPill({
    this.focusNode,
    required this.label,
    required this.isSelected,
    this.isFirst = false,
    this.isLast = false,
    required this.onSelected,
    required this.onDown,
  });

  @override
  State<_SeasonPill> createState() => _SeasonPillState();
}

class _SeasonPillState extends State<_SeasonPill> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _isFocused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (TvShortcuts.isActivateKey(event.logicalKey)) {
            widget.onSelected();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            widget.onDown();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            return KeyEventResult.handled;
          }
          if (widget.isFirst && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            return KeyEventResult.handled;
          }
          if (widget.isLast && event.logicalKey == LogicalKeyboardKey.arrowRight) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _isFocused
                ? TVTheme.primary
                : widget.isSelected
                    ? TVTheme.primary.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isFocused
                  ? Colors.white
                  : widget.isSelected
                      ? TVTheme.primary
                      : Colors.white24,
              width: 1.5,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _isFocused
                  ? Colors.black
                  : widget.isSelected
                      ? TVTheme.primary
                      : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogTile extends StatefulWidget {
  final FocusNode? focusNode;
  final String label;
  final String? subtitle;
  final bool isSelected;
  final bool autofocus;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onUp;
  final VoidCallback onSelected;

  const _DialogTile({
    this.focusNode,
    required this.label,
    this.subtitle,
    this.isSelected = false,
    this.autofocus = false,
    this.isFirst = false,
    this.isLast = false,
    this.onUp,
    required this.onSelected,
  });

  @override
  State<_DialogTile> createState() => _DialogTileState();
}

class _DialogTileState extends State<_DialogTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (TvShortcuts.isActivateKey(event.logicalKey)) {
            widget.onSelected();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            return KeyEventResult.handled;
          }
          if (widget.isFirst && event.logicalKey == LogicalKeyboardKey.arrowUp) {
            if (widget.onUp != null) {
              widget.onUp!();
            }
            return KeyEventResult.handled;
          }
          if (widget.isLast && event.logicalKey == LogicalKeyboardKey.arrowDown) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isFocused
                ? TVTheme.primary.withValues(alpha: 0.25)
                : widget.isSelected
                    ? TVTheme.surfaceElevated
                    : TVTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? Colors.white
                  : widget.isSelected
                      ? TVTheme.primary.withValues(alpha: 0.7)
                      : Colors.transparent,
              width: 2,
            ),
            boxShadow: _isFocused ? TVTheme.focusShadows : [],
          ),
          child: Row(
            children: [
              Icon(
                widget.isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: _isFocused
                    ? Colors.white
                    : widget.isSelected
                        ? TVTheme.primary
                        : Colors.white38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TVTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
