import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_core/shared_core.dart' hide SubtitleTrack;
import 'package:wakelock_plus/wakelock_plus.dart';
import '../theme.dart';
import '../widgets/player_hud.dart';
import '../widgets/stream_selector.dart';
import '../widgets/subtitle_picker_dialog.dart';
import '../widgets/tv_shortcuts.dart';

String _formatDuration(int totalSeconds) {
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

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final Map<String, String>? headers;
  final String movieTitle;
  final String imdbId;
  final int? tmdbId;
  final String mediaType;
  final int? season;
  final int? episode;
  final String provider;
  final String quality;
  final int initialPositionSeconds;
  final String? posterPath;
  final String? backdropPath;
  final List<StreamSource>? availableStreams;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    this.headers,
    required this.movieTitle,
    required this.imdbId,
    this.tmdbId,
    this.mediaType = 'movie',
    this.season,
    this.episode,
    this.provider = 'Direct',
    this.quality = 'HD',
    this.initialPositionSeconds = 0,
    this.posterPath,
    this.backdropPath,
    this.availableStreams,
  });

  factory PlayerScreen.fromMap(Map<String, dynamic> map) {
    return PlayerScreen(
      streamUrl: map['streamUrl'] as String? ?? '',
      headers: (map['headers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())),
      movieTitle: map['movieTitle'] as String? ?? '',
      imdbId: map['imdbId'] as String? ?? '',
      tmdbId: (map['tmdbId'] as num?)?.toInt(),
      mediaType: map['mediaType'] as String? ?? 'movie',
      season: (map['season'] as num?)?.toInt(),
      episode: (map['episode'] as num?)?.toInt(),
      provider: map['provider'] as String? ?? 'Direct',
      quality: map['quality'] as String? ?? 'HD',
      initialPositionSeconds: (map['initialPositionSeconds'] as num?)?.toInt() ?? 0,
      posterPath: map['posterPath'] as String?,
      backdropPath: map['backdropPath'] as String?,
      availableStreams: (map['availableStreams'] as List?)?.cast<StreamSource>(),
    );
  }

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;

  final FocusNode _mainFocusNode = FocusNode();
  final PlayerHudController _hudController = PlayerHudController();

  // Position notifiers to prevent setState churn on PlayerScreen
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _bufferNotifier = ValueNotifier(Duration.zero);

  // OSD Focus Nodes
  final FocusNode _playPauseButtonFocus = FocusNode();
  final FocusNode _subtitlesButtonFocus = FocusNode();
  final FocusNode _audioTrackButtonFocus = FocusNode();
  final FocusNode _sourceSwitcherButtonFocus = FocusNode();

  Timer? _progressSaveTimer;
  Timer? _osdHideTimer;
  Timer? _seekCommitTimer;
  Duration? _pendingSeekPosition;
  int _accumulatedSeekDelta = 0;
  final List<StreamSubscription> _subscriptions = [];

  String? _errorMessage;
  bool _isExiting = false;
  bool _showOsd = false;
  bool _isPlaying = true;
  bool _isBuffering = false;

  // Subtitles & Audio
  List<SubtitleTrackInfo> _subtitles = [];
  SubtitleTrackInfo? _selectedSubtitle;
  bool _isLoadingSubtitles = false;
  double _subtitleFontSize = 42.0;

  late String _currentStreamUrl;
  late String _currentQuality;
  late String _currentProvider;
  List<StreamSource> _availableStreams = [];

  Map<String, String> get _requestHeaders {
    return {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Range': 'bytes=0-',
      if (widget.headers != null) ...widget.headers!,
    };
  }

  @override
  void initState() {
    super.initState();
    _currentStreamUrl = widget.streamUrl;
    _currentQuality = widget.quality;
    _currentProvider = widget.provider;
    _availableStreams = widget.availableStreams ?? [];

    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Initialize media_kit Player with hardware decoding & buffering configuration
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 48 * 1024 * 1024,
      ),
    );

    _configureHardwareAndBuffer();

    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    StorageService.instance.getSubtitleFontSize().then((size) {
      if (mounted) setState(() => _subtitleFontSize = size);
    });

    _initPlayerListenersAndOpen();
  }

  void _configureHardwareAndBuffer() {
    try {
      final p = (_player.platform as dynamic);
      // Hardware decoding: Never fallback to CPU software decoding for 1080p
      p?.setProperty('hwdec', 'mediacodec-copy');
      p?.setProperty('vd-lavc-threads', '4');
      p?.setProperty('framedrop', 'vo');

      // Network & Buffer Stability for 1.5GB RAM Android TVs
      p?.setProperty('cache', 'yes');
      p?.setProperty('cache-secs', '30');
      p?.setProperty('demuxer-readahead-secs', '25');
      p?.setProperty('demuxer-max-bytes', '48MiB');
      p?.setProperty('demuxer-max-back-bytes', '24MiB');
      p?.setProperty('video-sync', 'audio');

      // Reconnect & HTTP resilience
      p?.setProperty('demuxer-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_on_http_error=4xx,5xx,reconnect_delay_max=10');
      p?.setProperty('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=10');
      p?.setProperty('network-timeout', '30');
    } catch (_) {}
  }

  Future<void> _initPlayerListenersAndOpen() async {
    // CRITICAL: Update ValueNotifier WITHOUT calling setState on PlayerScreen
    _subscriptions.add(
      _player.stream.position.listen((pos) {
        if (_showOsd) {
          _positionNotifier.value = pos;
        }
      }),
    );
    _subscriptions.add(
      _player.stream.duration.listen((dur) {
        _durationNotifier.value = dur;
      }),
    );
    _subscriptions.add(
      _player.stream.buffer.listen((buf) {
        if (_showOsd) {
          _bufferNotifier.value = buf;
        }
      }),
    );
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (mounted && _isPlaying != playing) {
          setState(() => _isPlaying = playing);
        }
      }),
    );
    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        if (mounted && _isBuffering != buffering) {
          setState(() => _isBuffering = buffering);
        }
      }),
    );
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (completed && mounted) {
          _saveProgress();
          _exitPlayer();
        }
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((err) {
        if (mounted && err.isNotEmpty) {
          _hudController.triggerInfo('Playback warning: $err');
        }
      }),
    );

    try {
      await _player.open(
        Media(
          _currentStreamUrl,
          httpHeaders: _requestHeaders,
        ),
      );

      if (widget.initialPositionSeconds > 0) {
        final startPos = Duration(seconds: widget.initialPositionSeconds);
        _player.stream.buffer.firstWhere((b) => b > Duration.zero).then((_) async {
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) {
            await _player.seek(startPos);
            _hudController.triggerInfo(
              'Resumed from ${_formatDuration(widget.initialPositionSeconds)}',
            );
          }
        }).catchError((_) {});
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    }

    _loadSubtitlesAsync();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mainFocusNode.requestFocus();
    });
  }

  Future<void> _loadSubtitlesAsync() async {
    if (widget.imdbId.isEmpty) return;
    setState(() => _isLoadingSubtitles = true);
    try {
      final tracks = await ApiClient.instance.getSubtitles(
        widget.mediaType,
        widget.imdbId,
        season: widget.season,
        episode: widget.episode,
      );
      if (!mounted) return;
      setState(() {
        _subtitles = tracks;
        _isLoadingSubtitles = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingSubtitles = false);
    }
  }

  void _saveProgress() {
    final posMs = _player.state.position.inMilliseconds;
    final durMs = _player.state.duration.inMilliseconds;

    if (durMs > 30000 && widget.imdbId.isNotEmpty) {
      final entry = ContinueWatchingEntry(
        imdbId: widget.imdbId,
        title: widget.movieTitle,
        posterPath: widget.posterPath,
        backdropPath: widget.backdropPath,
        mediaType: widget.mediaType,
        season: widget.season,
        episode: widget.episode,
        positionMs: posMs,
        durationMs: durMs,
        updatedAt: DateTime.now(),
      );
      StorageService.instance.saveContinueWatching(entry);
    }
  }

  // --- TV OSD HUD Control ---

  void _showOsdControls([FocusNode? targetFocus]) {
    setState(() => _showOsd = true);
    _positionNotifier.value = _player.state.position;
    _durationNotifier.value = _player.state.duration;
    _bufferNotifier.value = _player.state.buffer;
    _resetOsdTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        (targetFocus ?? _playPauseButtonFocus).requestFocus();
      }
    });
  }

  void _hideOsdControls() {
    _osdHideTimer?.cancel();
    setState(() => _showOsd = false);
    _mainFocusNode.requestFocus();
  }

  void _resetOsdTimer() {
    _osdHideTimer?.cancel();
    // Auto-hide after 4 seconds of inactivity
    _osdHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showOsd) {
        _hideOsdControls();
      }
    });
  }

  // --- Remote D-Pad Navigation & Shortcuts ---

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // Back key
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.backspace) {
      if (_showOsd) {
        _hideOsdControls();
        return KeyEventResult.handled;
      } else {
        _exitPlayer();
        return KeyEventResult.handled;
      }
    }

    // Play / Pause toggle on D-pad Center
    if (TvShortcuts.isActivateKey(key) || key == LogicalKeyboardKey.mediaPlayPause) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      final wasPlaying = _isPlaying;
      _player.playOrPause();
      if (wasPlaying) {
        _hudController.triggerPause();
      } else {
        _hudController.triggerPlay();
      }
      return KeyEventResult.handled;
    }

    // D-Pad Up / Down toggles OSD
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      if (!_showOsd) {
        _showOsdControls(_playPauseButtonFocus);
        return KeyEventResult.handled;
      }
    }

    // D-Pad Left / Right seeks -10s / +10s
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
      if (!_showOsd) {
        _seekDelta(-1);
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
      if (!_showOsd) {
        _seekDelta(1);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _seekDelta(int direction) {
    const step = 10;
    _accumulatedSeekDelta += (step * direction);

    final current = _pendingSeekPosition ?? _player.state.position;
    final duration = _player.state.duration;
    final target = current + Duration(seconds: step * direction);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && target > duration ? duration : target);

    _pendingSeekPosition = clamped;
    _hudController.triggerSeek(
      deltaSeconds: _accumulatedSeekDelta,
      targetTime: _formatDuration(clamped.inSeconds),
    );

    _seekCommitTimer?.cancel();
    _seekCommitTimer = Timer(const Duration(milliseconds: 250), () {
      if (_pendingSeekPosition != null) {
        _player.seek(_pendingSeekPosition!);
        _pendingSeekPosition = null;
        _accumulatedSeekDelta = 0;
      }
    });
  }

  // --- In-Player Dialogs ---

  void _showSubtitleDialog() async {
    _hideOsdControls();
    final result = await SubtitlePickerDialog.show(
      context: context,
      subtitles: _subtitles,
      selectedSubtitle: _selectedSubtitle,
      isLoading: _isLoadingSubtitles,
      initialFontSize: _subtitleFontSize,
      onFontSizeChanged: (newSize) {
        setState(() => _subtitleFontSize = newSize);
        StorageService.instance.setSubtitleFontSize(newSize);
      },
    );

    if (result != null && mounted) {
      if (result.isOff) {
        _selectedSubtitle = null;
        await _player.setSubtitleTrack(SubtitleTrack.no());
        _hudController.triggerSubtitle('Subtitles: Off');
      } else if (result.track != null) {
        _selectedSubtitle = result.track;
        try {
          await _player.setSubtitleTrack(
            SubtitleTrack.uri(
              result.track!.url,
              title: result.track!.label,
              language: result.track!.language,
            ),
          );
          _hudController.triggerSubtitle('Subtitles: ${result.track!.label}');
        } catch (_) {
          _hudController.triggerSubtitle('Failed to load subtitle');
        }
      }
    }
  }

  void _showAudioTrackDialog() async {
    _hideOsdControls();
    final tracks = _player.state.tracks.audio;
    if (tracks.isEmpty) {
      _hudController.triggerInfo('No alternative audio tracks');
      return;
    }

    final selected = await showDialog<AudioTrack>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TVTheme.surface,
        title: const Text('Select Audio Track', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: tracks.length,
            itemBuilder: (c, idx) {
              final t = tracks[idx];
              final label = (t.title?.isNotEmpty == true)
                  ? t.title!
                  : (t.language?.isNotEmpty == true ? t.language! : 'Track #${t.id}');
              return ListTile(
                autofocus: idx == 0,
                title: Text(label, style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(ctx).pop(t),
              );
            },
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      await _player.setAudioTrack(selected);
      _hudController.triggerInfo('Audio: ${selected.title ?? selected.language ?? selected.id}');
    }
  }

  void _showSourceSwitcherDialog() async {
    _hideOsdControls();
    List<StreamSource> sources = _availableStreams;
    if (sources.isEmpty && widget.imdbId.isNotEmpty) {
      try {
        sources = await ApiClient.instance.getStreams(
          widget.mediaType,
          widget.imdbId,
          season: widget.season,
          episode: widget.episode,
        );
        _availableStreams = sources;
      } catch (_) {}
    }

    if (!mounted) return;
    final selectedStream = await StreamSelector.showModal(
      context: context,
      streams: sources,
      title: widget.movieTitle,
    );

    if (selectedStream != null && mounted && selectedStream.url != _currentStreamUrl) {
      _saveProgress();
      _hudController.triggerInfo('Switching to ${selectedStream.quality} (${selectedStream.provider})...');
      setState(() {
        _currentStreamUrl = selectedStream.url;
        _currentQuality = selectedStream.quality;
        _currentProvider = selectedStream.provider;
      });

      // Hardware Guardrail: Stop old pipeline before opening new stream
      await _player.stop();
      await _player.open(
        Media(selectedStream.url, httpHeaders: _requestHeaders),
      );
    }
  }

  // --- Hardware Guardrail: Single-pipeline decoder cleanup ---

  void _exitPlayer() {
    if (_isExiting) return;
    _isExiting = true;
    _saveProgress();
    // Immediately stop hardware decoder pipeline
    _player.stop();
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _osdHideTimer?.cancel();
    _progressSaveTimer?.cancel();
    _seekCommitTimer?.cancel();

    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    _saveProgress();

    // Critical Hardware Guardrail for Amlogic & TV Decoders:
    _player.stop();
    _player.dispose();

    _mainFocusNode.dispose();
    _playPauseButtonFocus.dispose();
    _subtitlesButtonFocus.dispose();
    _audioTrackButtonFocus.dispose();
    _sourceSwitcherButtonFocus.dispose();
    _hudController.dispose();

    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _bufferNotifier.dispose();

    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_showOsd) {
          _hideOsdControls();
        } else {
          _exitPlayer();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _mainFocusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Hardware-accelerated Video Surface
              Video(
                controller: _videoController,
                controls: NoVideoControls,
                subtitleViewConfiguration: SubtitleViewConfiguration(
                  style: TextStyle(
                    height: 1.35,
                    fontSize: _subtitleFontSize,
                    letterSpacing: 0.2,
                    wordSpacing: 0.5,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: const [
                      Shadow(offset: Offset(-1.5, -1.5), color: Colors.black),
                      Shadow(offset: Offset(1.5, -1.5), color: Colors.black),
                      Shadow(offset: Offset(1.5, 1.5), color: Colors.black),
                      Shadow(offset: Offset(-1.5, 1.5), color: Colors.black),
                    ],
                  ),
                ),
              ),

              // Buffering indicator
              if (_isBuffering && !_showOsd)
                const Center(
                  child: CircularProgressIndicator(color: TVTheme.primary, strokeWidth: 3),
                ),

              // Error display
              if (_errorMessage != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: TVTheme.primary),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),

              // Quick TV OSD Action HUD
              PlayerHud(controller: _hudController),

              // Interactive TV OSD Layer
              if (_showOsd) _buildOsdOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOsdOverlay() {
    return GestureDetector(
      onTap: _resetOsdTimer,
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        padding: const EdgeInsets.symmetric(
          horizontal: TVTheme.overscanMargin,
          vertical: 32,
        ),
        child: Column(
          children: [
            // Top Title Bar
            Row(
              children: [
                IconButton(
                  focusNode: FocusNode(canRequestFocus: false),
                  onPressed: _exitPlayer,
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.movieTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_currentProvider • $_currentQuality${widget.season != null ? " • S${widget.season}E${widget.episode}" : ""}',
                        style: const TextStyle(fontSize: 13, color: TVTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),

            // Center Seek / Position Bar (Uses ValueListenableBuilder - Zero Parent Rebuilds)
            ValueListenableBuilder<Duration>(
              valueListenable: _positionNotifier,
              builder: (ctx, pos, _) {
                final dur = _durationNotifier.value;
                final posSeconds = pos.inSeconds;
                final durSeconds = dur.inSeconds;
                final progress = durSeconds > 0 ? (posSeconds / durSeconds).clamp(0.0, 1.0) : 0.0;

                return Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        activeTrackColor: TVTheme.primary,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: progress,
                        onChanged: (val) {
                          _resetOsdTimer();
                          final newSec = (val * durSeconds).toInt();
                          _player.seek(Duration(seconds: newSec));
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(posSeconds),
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          Text(
                            _formatDuration(durSeconds),
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // Bottom TV Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildOsdIconButton(
                  focusNode: _playPauseButtonFocus,
                  icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  label: _isPlaying ? 'Pause' : 'Play',
                  nextFocus: _subtitlesButtonFocus,
                  onPressed: () {
                    _resetOsdTimer();
                    _player.playOrPause();
                  },
                ),
                const SizedBox(width: 24),
                _buildOsdIconButton(
                  focusNode: _subtitlesButtonFocus,
                  icon: Icons.subtitles_rounded,
                  label: 'Subtitles',
                  prevFocus: _playPauseButtonFocus,
                  nextFocus: _audioTrackButtonFocus,
                  onPressed: () {
                    _resetOsdTimer();
                    _showSubtitleDialog();
                  },
                ),
                const SizedBox(width: 24),
                _buildOsdIconButton(
                  focusNode: _audioTrackButtonFocus,
                  icon: Icons.audiotrack_rounded,
                  label: 'Audio',
                  prevFocus: _subtitlesButtonFocus,
                  nextFocus: _sourceSwitcherButtonFocus,
                  onPressed: () {
                    _resetOsdTimer();
                    _showAudioTrackDialog();
                  },
                ),
                const SizedBox(width: 24),
                _buildOsdIconButton(
                  focusNode: _sourceSwitcherButtonFocus,
                  icon: Icons.tune_rounded,
                  label: 'Sources',
                  prevFocus: _audioTrackButtonFocus,
                  onPressed: () {
                    _resetOsdTimer();
                    _showSourceSwitcherDialog();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildOsdIconButton({
    required FocusNode focusNode,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    FocusNode? nextFocus,
    FocusNode? prevFocus,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight && nextFocus != null) {
            _resetOsdTimer();
            nextFocus.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft && prevFocus != null) {
            _resetOsdTimer();
            prevFocus.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown || event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _resetOsdTimer();
            return KeyEventResult.handled;
          }
        }
        return TvShortcuts.handleKeyEvent(event, onActivate: onPressed);
      },
      child: Builder(
        builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: isFocused ? Colors.white : Colors.white12,
                borderRadius: BorderRadius.circular(8),
                boxShadow: isFocused ? TVTheme.focusShadows : [],
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isFocused ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: isFocused ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
