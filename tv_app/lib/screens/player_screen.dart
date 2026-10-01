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
import '../widgets/resume_dialog.dart';
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

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    this.headers,
    required this.movieTitle,
    required this.tmdbId,
    this.provider = 'Direct',
    this.quality = 'HD',
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  final FocusNode _focusNode = FocusNode();
  final PlayerHudController _hudController = PlayerHudController();

  Timer? _progressSaveTimer;
  final List<StreamSubscription> _subscriptions = [];
  String? _errorMessage;
  bool _isShowingResumeDialog = false;

  List<SubtitleTrackInfo> _subtitles = [];
  SubtitleTrackInfo? _selectedSubtitle;
  bool _isLoadingSubtitles = false;

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

    _initPlayerAndMedia();
  }

  Future<void> _initPlayerAndMedia() async {
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (completed && mounted) {
          LocalStorage.clearProgress(widget.tmdbId);
          Navigator.of(context).pop();
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

    Duration? startPosition;
    final savedSeconds = await LocalStorage.getProgress(widget.tmdbId);
    if (savedSeconds > 10 && mounted) {
      setState(() => _isShowingResumeDialog = true);
      final resume = await ResumeDialog.show(
        context: context,
        savedSeconds: savedSeconds,
        formatDuration: formatDuration,
      );
      if (mounted) setState(() => _isShowingResumeDialog = false);
      if (resume == true) {
        startPosition = Duration(seconds: savedSeconds);
      } else {
        await LocalStorage.clearProgress(widget.tmdbId);
      }
    }


    try {
      await _player.open(
        Media(
          widget.streamUrl,
          httpHeaders: _requestHeaders,
        ),
      );

      if (startPosition != null) {
        _player.stream.buffer.firstWhere((b) => b > Duration.zero).then((_) async {
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) {
            await _player.seek(startPosition!);
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
      final subs = await ApiClient.getSubtitles(widget.tmdbId);
      if (mounted) {
        setState(() {
          _subtitles = subs;
          _isLoadingSubtitles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSubtitles = false);
      }
    }
  }

  Future<void> _selectSubtitle(SubtitleTrackInfo? subtitle) async {
    setState(() {
      _selectedSubtitle = subtitle;
    });

    if (subtitle != null) {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          subtitle.url,
          title: subtitle.language,
          language: subtitle.code,
        ),
      );
      _hudController.triggerSubtitle('Subtitles: ${subtitle.language}');
    } else {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      _hudController.triggerSubtitle('Subtitles: Off');
    }
  }

  void _showSubtitleDialog() async {
    final selected = await SubtitlePickerDialog.show(
      context: context,
      subtitles: _subtitles,
      selectedSubtitle: _selectedSubtitle,
      isLoading: _isLoadingSubtitles,
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_isShowingResumeDialog) {
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

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

    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
      final current = _player.state.position;
      final target = current - const Duration(seconds: 10);
      final finalTarget = target < Duration.zero ? Duration.zero : target;
      _player.seek(finalTarget);
      _hudController.triggerSeek(
        deltaSeconds: -10,
        targetTime: formatDuration(finalTarget.inSeconds),
      );
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
      final current = _player.state.position;
      final duration = _player.state.duration;
      final target = current + const Duration(seconds: 10);
      final finalTarget = target > duration ? duration : target;
      _player.seek(finalTarget);
      _hudController.triggerSeek(
        deltaSeconds: 10,
        targetTime: formatDuration(finalTarget.inSeconds),
      );
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.closedCaptionToggle ||
        key == LogicalKeyboardKey.keyC ||
        key == LogicalKeyboardKey.mediaAudioTrack) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      _showSubtitleDialog();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _exitPlayer();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _exitPlayer() {
    _saveProgress();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _saveProgress();
    _player.dispose();
    _focusNode.dispose();
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

  MaterialVideoControlsThemeData _buildThemeData() {
    final qualityBadge = widget.provider.isNotEmpty ? widget.provider : 'Direct';

    return MaterialVideoControlsThemeData(
      displaySeekBar: true,
      seekGesture: true,
      seekOnDoubleTap: true,
      seekOnDoubleTapBackwardDuration: const Duration(seconds: 10),
      seekOnDoubleTapForwardDuration: const Duration(seconds: 10),
      speedUpOnLongPress: true,
      seekBarPositionColor: TVTheme.accent,
      seekBarThumbColor: TVTheme.accent,
      topButtonBar: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _exitPlayer,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.movieTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: TVTheme.accent.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: TVTheme.accent, width: 1),
          ),
          child: Text(
            qualityBadge,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            _selectedSubtitle != null ? Icons.subtitles : Icons.subtitles_outlined,
            color: _selectedSubtitle != null ? TVTheme.accent : Colors.white,
          ),
          tooltip: 'Subtitles',
          onPressed: _showSubtitleDialog,
        ),
      ],
      bottomButtonBar: const [
        MaterialPositionIndicator(),
        Spacer(),
        MaterialFullscreenButton(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeData = _buildThemeData();

    return WillPopScope(
      onWillPop: () async {
        _exitPlayer();
        return false;
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
              MaterialVideoControlsTheme(
                normal: themeData,
                fullscreen: themeData,
                child: Video(
                  controller: _videoController,
                  controls: MaterialVideoControls,
                ),
              ),
              PlayerHud(controller: _hudController),
              if (_errorMessage != null)
                Container(
                  color: Colors.black.withOpacity(0.9),
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}
