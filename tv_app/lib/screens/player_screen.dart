import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/api_client.dart';
import '../core/local_storage.dart';
import '../models/subtitle.model.dart';
import '../theme.dart';
import '../widgets/focusable_button.dart';
import '../widgets/player_hud.dart';
import '../widgets/subtitle_picker_dialog.dart';

String formatDuration(int totalSeconds) {
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
  final int tmdbId;
  final String provider;
  final String quality;
  final int initialPositionSeconds;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    this.headers,
    required this.movieTitle,
    required this.tmdbId,
    this.provider = 'Direct',
    this.quality = 'HD',
    this.initialPositionSeconds = 0,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  final FocusNode _focusNode = FocusNode();
  final PlayerHudController _hudController = PlayerHudController();

  final FocusNode _backButtonFocus = FocusNode();
  final FocusNode _subtitleButtonFocus = FocusNode();
  final FocusNode _rewindButtonFocus = FocusNode();
  final FocusNode _playPauseButtonFocus = FocusNode();
  final FocusNode _forwardButtonFocus = FocusNode();
  final FocusNode _seekBarFocus = FocusNode();

  Timer? _progressSaveTimer;
  Timer? _osdHideTimer;
  final List<StreamSubscription> _subscriptions = [];
  String? _errorMessage;
  bool _isExiting = false;
  bool _showOsd = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _isPlaying = true;
  bool _isBuffering = false;

  List<SubtitleTrackInfo> _subtitles = [];
  SubtitleTrackInfo? _selectedSubtitle;
  bool _isLoadingSubtitles = false;
  double _subtitleFontSize = 44.0;
  double _subtitleDelaySeconds = 0.0;

  Map<String, String> get _requestHeaders {
    if (widget.headers != null) {
      return {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        ...widget.headers!,
      };
    }
    return {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
  }

  @override
  void initState() {
    super.initState();

    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    LocalStorage.getSubtitleFontSize().then((size) {
      if (mounted) setState(() => _subtitleFontSize = size);
    });

    _initPlayerAndMedia();
  }

  Future<void> _initPlayerAndMedia() async {
    _subscriptions.add(
      _player.stream.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
      }),
    );
    _subscriptions.add(
      _player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      }),
    );
    _subscriptions.add(
      _player.stream.buffer.listen((buf) {
        if (mounted) setState(() => _buffer = buf);
      }),
    );
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      }),
    );
    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _isBuffering = buffering);
      }),
    );
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (completed && mounted) {
          LocalStorage.clearProgress(widget.tmdbId);
          _exitPlayer();
        }
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((err) {
        if (mounted) {
          setState(() {
            _errorMessage = err.isNotEmpty ? err : 'Playback error encountered';
          });
        }
      }),
    );

    try {
      await _player.open(
        Media(
          widget.streamUrl,
          httpHeaders: _requestHeaders,
        ),
      );

      if (widget.initialPositionSeconds > 0) {
        final startPosition = Duration(seconds: widget.initialPositionSeconds);
        _player.stream.buffer.firstWhere((b) => b > Duration.zero).then((_) async {
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) {
            await _player.seek(startPosition);
            _hudController.triggerInfo(
              'Resumed from ${formatDuration(widget.initialPositionSeconds)}',
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }

    _loadSubtitlesAsync();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _loadSubtitlesAsync() async {
    if (!mounted) return;
    setState(() => _isLoadingSubtitles = true);
    try {
      final tracks = await ApiClient.getSubtitles(widget.tmdbId);
      if (mounted) {
        setState(() {
          _subtitles = tracks;
          _isLoadingSubtitles = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingSubtitles = false);
    }
  }

  Future<void> _selectSubtitle(SubtitleTrackInfo? track) async {
    setState(() => _selectedSubtitle = track);
    if (track != null) {
      try {
        final uri = Uri.parse(track.url);
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(
            uri.toString(),
            title: track.label,
            language: track.language,
          ),
        );
        _hudController.triggerSubtitle('Subtitles: ${track.label}');
      } catch (e) {
        _hudController.triggerSubtitle('Failed to load subtitle');
      }
    } else {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      _hudController.triggerSubtitle('Subtitles: Off');
    }
  }

  void _updateSubtitleFontSize(double newSize) {
    setState(() => _subtitleFontSize = newSize);
    LocalStorage.saveSubtitleFontSize(newSize);
  }

  void _updateSubtitleDelay(double newDelay) {
    setState(() => _subtitleDelaySeconds = newDelay);
    try {
      (_player.platform as dynamic)?.setProperty('sub-delay', newDelay.toStringAsFixed(3));
      final sign = newDelay > 0 ? '+' : '';
      _hudController.triggerInfo('Subtitle Sync: $sign${newDelay.toStringAsFixed(1)}s');
    } catch (_) {}
  }

  void _showSubtitleDialog() async {
    _hideOsdControls();
    final selected = await SubtitlePickerDialog.show(
      context: context,
      subtitles: _subtitles,
      selectedSubtitle: _selectedSubtitle,
      isLoading: _isLoadingSubtitles,
      initialFontSize: _subtitleFontSize,
      initialDelaySeconds: _subtitleDelaySeconds,
      onFontSizeChanged: _updateSubtitleFontSize,
      onDelayChanged: _updateSubtitleDelay,
    );
    if (mounted && selected != _selectedSubtitle) {
      await _selectSubtitle(selected);
    }
  }

  void _saveProgress() {
    final pos = _player.state.position;
    final dur = _player.state.duration;
    if (dur.inSeconds > 30) {
      if (pos.inSeconds >= (dur.inSeconds * 0.95)) {
        LocalStorage.clearProgress(widget.tmdbId);
      } else if (pos.inSeconds > 5) {
        LocalStorage.saveProgress(widget.tmdbId, pos.inSeconds);
      }
    }
  }

  void _showOsdControls([FocusNode? targetFocus]) {
    setState(() => _showOsd = true);
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
    _focusNode.requestFocus();
  }

  void _resetOsdTimer() {
    _osdHideTimer?.cancel();
    _osdHideTimer = Timer(const Duration(milliseconds: 4500), () {
      if (mounted && _showOsd) {
        _hideOsdControls();
      }
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (_showOsd) {
        _hideOsdControls();
        return KeyEventResult.handled;
      } else {
        _exitPlayer();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      _player.playOrPause();
      if (_player.state.playing) {
        _hudController.triggerPause();
      } else {
        _hudController.triggerPlay();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      if (!_showOsd) {
        _showOsdControls(_playPauseButtonFocus);
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
      if (!_showOsd) {
        _seekDelta(-10);
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
      if (!_showOsd) {
        _seekDelta(10);
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.closedCaptionToggle ||
        key == LogicalKeyboardKey.keyC ||
        key == LogicalKeyboardKey.mediaAudioTrack) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      _showSubtitleDialog();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _seekDelta(int seconds) {
    final current = _player.state.position;
    final duration = _player.state.duration;
    final target = current + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && target > duration ? duration : target);
    _player.seek(clamped);
    _hudController.triggerSeek(
      deltaSeconds: seconds,
      targetTime: formatDuration(clamped.inSeconds),
    );
  }

  void _exitPlayer() {
    if (_isExiting) return;
    _isExiting = true;
    _saveProgress();
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _osdHideTimer?.cancel();
    _progressSaveTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _saveProgress();
    _player.dispose();
    _focusNode.dispose();
    _backButtonFocus.dispose();
    _subtitleButtonFocus.dispose();
    _rewindButtonFocus.dispose();
    _playPauseButtonFocus.dispose();
    _forwardButtonFocus.dispose();
    _seekBarFocus.dispose();
    _hudController.dispose();
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
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video Layer
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
                    backgroundColor: const Color(0xB3000000),
                  ),
                  padding: const EdgeInsets.fromLTRB(32.0, 0.0, 32.0, 36.0),
                ),
              ),

              // Quick HUD Toast Layer
              PlayerHud(controller: _hudController),

              // Buffering indicator
              if (_isBuffering)
                const Center(
                  child: CircularProgressIndicator(color: TVTheme.accent, strokeWidth: 3),
                ),

              // 10-Foot TV OSD Overlay Layer
              if (_showOsd) _buildTvOsdOverlay(),

              // Playback Error Overlay
              if (_errorMessage != null) _buildErrorOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTvOsdOverlay() {
    final posSeconds = _position.inSeconds;
    final durSeconds = _duration.inSeconds;
    final progressRatio = durSeconds > 0 ? (posSeconds / durSeconds).clamp(0.0, 1.0) : 0.0;
    final bufferRatio = durSeconds > 0 ? (_buffer.inSeconds / durSeconds).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: _resetOsdTimer,
      behavior: HitTestBehavior.translucent,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xCC000000),
              Color(0x33000000),
              Color(0xEE000000),
            ],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
        child: Column(
          children: [
            // Top Bar
            Row(
              children: [
                _buildOsdIconButton(
                  focusNode: _backButtonFocus,
                  icon: Icons.arrow_back_rounded,
                  label: 'Back',
                  onTap: _exitPlayer,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.movieTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: TVTheme.accent.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: TVTheme.accent, width: 1),
                            ),
                            child: Text(
                              '${widget.provider} • ${widget.quality}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          if (_selectedSubtitle != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'CC: ${_selectedSubtitle!.label}',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                _buildOsdIconButton(
                  focusNode: _subtitleButtonFocus,
                  icon: _selectedSubtitle != null ? Icons.subtitles_rounded : Icons.subtitles_outlined,
                  label: 'Subtitles',
                  highlight: _selectedSubtitle != null,
                  onTap: _showSubtitleDialog,
                ),
              ],
            ),

            const Spacer(),

            // Center Quick Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildOsdIconButton(
                  focusNode: _rewindButtonFocus,
                  icon: Icons.replay_10_rounded,
                  label: '-10s',
                  size: 48,
                  iconSize: 28,
                  onTap: () {
                    _resetOsdTimer();
                    _seekDelta(-10);
                  },
                ),
                const SizedBox(width: 24),
                _buildOsdIconButton(
                  focusNode: _playPauseButtonFocus,
                  icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  label: _isPlaying ? 'Pause' : 'Play',
                  size: 64,
                  iconSize: 40,
                  isPrimary: true,
                  onTap: () {
                    _resetOsdTimer();
                    _player.playOrPause();
                  },
                ),
                const SizedBox(width: 24),
                _buildOsdIconButton(
                  focusNode: _forwardButtonFocus,
                  icon: Icons.forward_10_rounded,
                  label: '+10s',
                  size: 48,
                  iconSize: 28,
                  onTap: () {
                    _resetOsdTimer();
                    _seekDelta(10);
                  },
                ),
              ],
            ),

            const Spacer(),

            // Bottom Progress & Seek Bar
            Focus(
              focusNode: _seekBarFocus,
              onKeyEvent: (node, event) {
                _resetOsdTimer();
                if (event is KeyDownEvent || event is KeyRepeatEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    _seekDelta(-10);
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    _seekDelta(10);
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space) {
                    _player.playOrPause();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: focused ? Colors.white12 : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: focused ? TVTheme.accent : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Time Display
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatDuration(posSeconds),
                              style: TextStyle(
                                color: focused ? Colors.white : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              formatDuration(durSeconds),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Track
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Stack(
                            children: [
                              Container(
                                height: 6,
                                color: Colors.white24,
                              ),
                              FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: bufferRatio,
                                child: Container(
                                  height: 6,
                                  color: Colors.white38,
                                ),
                              ),
                              FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: progressRatio,
                                child: Container(
                                  height: 6,
                                  color: TVTheme.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOsdIconButton({
    required FocusNode focusNode,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    double size = 44,
    double iconSize = 22,
    bool isPrimary = false,
    bool highlight = false,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        _resetOsdTimer();
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedScale(
              scale: focused ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 140),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPrimary
                      ? (focused ? Colors.white : TVTheme.accent)
                      : (focused ? Colors.white24 : (highlight ? TVTheme.accent.withOpacity(0.3) : Colors.white10)),
                  border: Border.all(
                    color: focused ? Colors.white : (highlight ? TVTheme.accent : Colors.white12),
                    width: focused ? 2.0 : 1.0,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: (isPrimary ? TVTheme.accent : Colors.white).withOpacity(0.5),
                            blurRadius: 16,
                            spreadRadius: 2,
                          )
                        ]
                      : [],
                ),
                child: Icon(
                  icon,
                  size: iconSize,
                  color: isPrimary
                      ? (focused ? Colors.black : Colors.white)
                      : (focused ? Colors.white : (highlight ? TVTheme.accent : Colors.white70)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.92),
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Playback Error',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FocusableButton(
                  label: 'Retry',
                  color: TVTheme.accent,
                  autofocus: true,
                  onPressed: () {
                    setState(() => _errorMessage = null);
                    _player.open(Media(widget.streamUrl, httpHeaders: _requestHeaders));
                  },
                ),
                const SizedBox(width: 16),
                FocusableButton(
                  label: 'Exit',
                  color: Colors.white24,
                  onPressed: _exitPlayer,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
