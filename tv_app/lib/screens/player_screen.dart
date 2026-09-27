import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/local_storage.dart';
import '../theme.dart';

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

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    this.headers,
    required this.movieTitle,
    required this.tmdbId,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  final FocusNode _focusNode = FocusNode();

  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _progressSaveTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = true;
  String? _errorMessage;
  bool _isShowingResumeDialog = false;

  final List<StreamSubscription> _subscriptions = [];

  Map<String, String> get _requestHeaders => {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://cdn.uptomkv.ch/',
    ...?widget.headers,
  };

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _initPlayer();
  }

  Future<void> _initPlayer() async {
    _player = Player();
    _videoController = VideoController(_player);

    _subscriptions.add(
      _player.stream.position.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
    );
    _subscriptions.add(
      _player.stream.duration.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
    );
    _subscriptions.add(
      _player.stream.buffer.listen((b) {
        if (mounted) setState(() => _buffer = b);
      }),
    );
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() => _isPlaying = playing);
          if (playing) _startHideTimer();
        }
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
          Navigator.of(context).pop();
        }
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((err) {
        if (mounted) {
          setState(() {
            _errorMessage = err.isNotEmpty ? err : 'Playback error encountered';
            _isBuffering = false;
          });
        }
      }),
    );

    Duration? startPosition;
    final savedSeconds = await LocalStorage.getProgress(widget.tmdbId);
    if (savedSeconds > 10 && mounted) {
      setState(() => _isShowingResumeDialog = true);
      final resume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('Resume Playback?', style: TextStyle(color: Colors.white)),
            content: Text(
              'Would you like to resume watching from ${formatDuration(savedSeconds)}?',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              _FocusableDialogButton(
                label: 'Start Over',
                color: Colors.redAccent,
                onPressed: () => Navigator.pop(context, false),
              ),
              const SizedBox(width: 8),
              _FocusableDialogButton(
                label: 'Resume',
                color: TVTheme.accent,
                autofocus: true,
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          );
        },
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
          start: startPosition,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isBuffering = false;
        });
      }
    }

    _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });

    _startHideTimer();
  }

  void _saveProgress() {
    if (_duration.inSeconds > 30) {
      if (_position.inSeconds >= (_duration.inSeconds * 0.95)) {
        LocalStorage.clearProgress(widget.tmdbId);
      } else if (_position.inSeconds > 5) {
        LocalStorage.saveProgress(widget.tmdbId, _position.inSeconds);
      }
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying && !_isShowingResumeDialog) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showOverlayControls() {
    setState(() => _showControls = true);
    _startHideTimer();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _isShowingResumeDialog) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (!_showControls) {
        _showOverlayControls();
      } else {
        _player.playOrPause();
        _startHideTimer();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
      _showOverlayControls();
      final target = _position - const Duration(seconds: 10);
      _player.seek(target < Duration.zero ? Duration.zero : target);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
      _showOverlayControls();
      final target = _position + const Duration(seconds: 10);
      _player.seek(target > _duration ? _duration : target);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      _showOverlayControls();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (_showControls) {
        setState(() => _showControls = false);
      } else {
        _exitPlayer();
      }
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
    _hideTimer?.cancel();
    _progressSaveTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _saveProgress();
    _player.dispose();
    _focusNode.dispose();
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
      canPop: !_showControls,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _saveProgress();
        } else if (_showControls) {
          setState(() => _showControls = false);
        }
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Video(
                controller: _videoController,
                controls: NoVideoControls,
              ),
              if (_isBuffering && _errorMessage == null)
                const Center(
                  child: CircularProgressIndicator(
                    color: TVTheme.accent,
                    strokeWidth: 3,
                  ),
                ),
              if (_errorMessage != null)
                _buildErrorOverlay(),
              if (_showControls && _errorMessage == null)
                _buildControlsOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: TVTheme.accent, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Playback Error',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Failed to play stream',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FocusableDialogButton(
                  label: 'Retry',
                  color: TVTheme.accent,
                  autofocus: true,
                  onPressed: () {
                    setState(() {
                      _errorMessage = null;
                      _isBuffering = true;
                    });
                    _player.open(Media(widget.streamUrl, httpHeaders: _requestHeaders));
                  },
                ),
                const SizedBox(width: 16),
                _FocusableDialogButton(
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

  Widget _buildControlsOverlay() {
    final double progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final double buffer = _duration.inMilliseconds > 0
        ? (_buffer.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black87,
            Colors.transparent,
            Colors.transparent,
            Colors.black87,
          ],
          stops: [0.0, 0.25, 0.75, 1.0],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _exitPlayer,
                ),
                const SizedBox(width: 12),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: TVTheme.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: TVTheme.accent),
                  ),
                  child: const Text(
                    'Direct HD',
                    style: TextStyle(
                      color: TVTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: IconButton(
              iconSize: 64,
              icon: Icon(
                _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              onPressed: () {
                _player.playOrPause();
                _startHideTimer();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 4,
                          width: width,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Container(
                          height: 4,
                          width: width * buffer,
                          decoration: BoxDecoration(
                            color: Colors.white38,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Container(
                          height: 4,
                          width: width * progress,
                          decoration: BoxDecoration(
                            color: TVTheme.accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatDuration(_position.inSeconds),
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const Text(
                      '◄◄ 10s   [OK: Play/Pause]   10s ►►',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    Text(
                      formatDuration(_duration.inSeconds),
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusableDialogButton extends StatefulWidget {
  final String label;
  final Color color;
  final bool autofocus;
  final VoidCallback onPressed;

  const _FocusableDialogButton({
    required this.label,
    required this.color,
    this.autofocus = false,
    required this.onPressed,
  });

  @override
  State<_FocusableDialogButton> createState() => _FocusableDialogButtonState();
}

class _FocusableDialogButtonState extends State<_FocusableDialogButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: _isFocused ? widget.color : Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.transparent,
              width: 2,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    )
                  ]
                : [],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _isFocused ? Colors.white : Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
