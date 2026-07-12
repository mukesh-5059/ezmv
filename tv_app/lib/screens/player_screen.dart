import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/local_storage.dart';

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String movieTitle;
  final int tmdbId;

  const PlayerScreen({
    Key? key,
    required this.streamUrl,
    required this.movieTitle,
    required this.tmdbId,
  }) : super(key: key);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // Web Player (Fallback)
  late final WebViewController _webViewController;
  bool _isWebLoading = true;

  // Native Player (Isaimini)
  VideoPlayerController? _videoController;
  bool _isNativeLoading = true;
  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _progressSaveTimer;
  String? _errorMessage;
  bool _isShowingResumeDialog = false;

  // Check if link is a direct streamable file
  bool get _isDirectStream {
    final uri = Uri.parse(widget.streamUrl);
    final path = uri.path.toLowerCase();
    final host = uri.host.toLowerCase();
    return host.contains('uptomkv') || 
           host.contains('fastbytes') || 
           path.endsWith('.mp4') || 
           path.endsWith('.m3u8') || 
           uri.queryParameters.containsKey('stream');
  }

  @override
  void initState() {
    super.initState();
    
    // Keep screen awake during video playback
    WakelockPlus.enable();

    // Lock screen to fullscreen landscape
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    if (_isDirectStream) {
      _initNativePlayer();
    } else {
      _initWebPlayer();
    }
  }

  // Initialize Native player
  void _initNativePlayer() {
    VideoFormat? formatHint;
    final lowercaseUrl = widget.streamUrl.toLowerCase();
    if (lowercaseUrl.contains('.m3u8') || lowercaseUrl.contains('m3u8')) {
      formatHint = VideoFormat.hls;
    } else if (lowercaseUrl.contains('.mp4')) {
      formatHint = VideoFormat.other;
    }

    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(widget.streamUrl),
      formatHint: formatHint,
      httpHeaders: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://${Uri.parse(widget.streamUrl).host}/',
      },
    )
      ..initialize().then((_) {
        setState(() {
          _isNativeLoading = false;
        });
        _checkResumeProgress();
        _resetHideTimer();
      }).catchError((e) {
        print("Native player initialization failed: $e");
        setState(() {
          _isNativeLoading = false;
          _errorMessage = e.toString();
        });
      });

    // Listen for progress change to update overlay UI and catch playback errors
    _videoController!.addListener(() {
      if (_videoController!.value.hasError) {
        setState(() {
          _errorMessage = _videoController!.value.errorDescription ?? "Playback error";
        });
      }
      if (mounted) setState(() {});
    });
  }

  // Check and prompt for watch progress
  Future<void> _checkResumeProgress() async {
    final savedSeconds = await LocalStorage.getProgress(widget.tmdbId);
    if (savedSeconds > 10 && mounted) {
      setState(() {
        _isShowingResumeDialog = true;
      });
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
              Focus(
                onKey: (node, event) {
                  if (event is RawKeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.select ||
                        event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                        event.logicalKey == LogicalKeyboardKey.space) {
                      Navigator.pop(context, false);
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: focused ? Colors.white24 : Colors.transparent,
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Start Over', style: TextStyle(color: Colors.red)),
                    );
                  },
                ),
              ),
              Focus(
                autofocus: true,
                onKey: (node, event) {
                  if (event is RawKeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.select ||
                        event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                        event.logicalKey == LogicalKeyboardKey.space) {
                      Navigator.pop(context, true);
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: focused ? Colors.white : Colors.red,
                        foregroundColor: focused ? Colors.black : Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Resume'),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );

      setState(() {
        _isShowingResumeDialog = false;
      });

      if (resume == true && _videoController != null) {
        await _videoController!.seekTo(Duration(seconds: savedSeconds));
      }
    }

    if (_videoController != null) {
      _videoController!.play();
      _startProgressSaving();
    }
  }

  // Periodically save progress to LocalStorage
  void _startProgressSaving() {
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_videoController != null && _videoController!.value.isPlaying) {
        final currentSec = _videoController!.value.position.inSeconds;
        LocalStorage.saveProgress(widget.tmdbId, currentSec);
      }
    });
  }

  // Initialize WebView player
  void _initWebPlayer() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress > 80) {
              setState(() => _isWebLoading = false);
            }
          },
          onPageStarted: (String url) {
            setState(() => _isWebLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isWebLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            print("WebView player error: ${error.description}");
          },
        ),
      )
      ..setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
      ..loadRequest(
        Uri.parse(widget.streamUrl),
        headers: {
          'Referer': 'https://${Uri.parse(widget.streamUrl).host}/',
        },
      );
  }

  // Overlay management
  void _resetHideTimer() {
    _hideTimer?.cancel();
    setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _seekRelative(int seconds) {
    if (_videoController == null) return;
    _resetHideTimer();
    final newPosition = _videoController!.value.position + Duration(seconds: seconds);
    final duration = _videoController!.value.duration;
    if (newPosition < Duration.zero) {
      _videoController!.seekTo(Duration.zero);
    } else if (newPosition > duration) {
      _videoController!.seekTo(duration);
    } else {
      _videoController!.seekTo(newPosition);
    }
  }

  void _togglePlay() {
    if (_videoController == null) return;
    _resetHideTimer();
    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
    });
  }

  // Key Event Handling (TV Remote control logic)
  KeyEventResult _handleKeyEvent(RawKeyEvent event) {
    _resetHideTimer();
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _seekRelative(-10);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _seekRelative(10);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.select ||
                 event.logicalKey == LogicalKeyboardKey.enter ||
                 event.logicalKey == LogicalKeyboardKey.space) {
        _togglePlay();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // Web Remote event mapping: Forward keys directly into browser context
  KeyEventResult _handleWebKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _webViewController.runJavaScript(
          "window.dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowLeft', keyCode: 37, bubbles: true}));"
        );
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _webViewController.runJavaScript(
          "window.dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowRight', keyCode: 39, bubbles: true}));"
        );
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.select ||
                 event.logicalKey == LogicalKeyboardKey.enter ||
                 event.logicalKey == LogicalKeyboardKey.space) {
        _webViewController.runJavaScript(
          "window.dispatchEvent(new KeyboardEvent('keydown', {key: ' ', keyCode: 32, bubbles: true}));"
        );
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  String formatDuration(int totalSeconds) {
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    _hideTimer?.cancel();

    // Allow screen to go to sleep/screensaver again
    WakelockPlus.disable();

    if (_videoController != null) {
      final currentSec = _videoController!.value.position.inSeconds;
      final durationSec = _videoController!.value.duration.inSeconds;
      
      // Clear watch progress if they finished 95% of the movie, else save current position
      if (durationSec > 0 && currentSec / durationSec > 0.95) {
        LocalStorage.clearProgress(widget.tmdbId);
      } else {
        LocalStorage.saveProgress(widget.tmdbId, currentSec);
      }
      _videoController!.dispose();
    }

    // Restore standard UI options & unlock orientation on exit
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildErrorWidget(),
      );
    }

    if (_isDirectStream) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildNativePlayer(),
      );
    } else {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildWebPlayer(),
      );
    }
  }

  // Native player UI Layout
  Widget _buildNativePlayer() {
    if (_isNativeLoading || _videoController == null || !_videoController!.value.isInitialized) {
      return _buildLoadingWidget();
    }

    final duration = _videoController!.value.duration;
    final position = _videoController!.value.position;

    return Focus(
      autofocus: !_isShowingResumeDialog,
      canRequestFocus: !_isShowingResumeDialog,
      onKey: (node, event) {
        if (_isShowingResumeDialog) return KeyEventResult.ignored;
        return _handleKeyEvent(event);
      },
      child: GestureDetector(
        onTap: _resetHideTimer,
        child: Stack(
          children: [
            // Video renderer
            Center(
              child: AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
            ),

            // Buffering Overlay
            if (_videoController!.value.isBuffering)
              Positioned.fill(
                child: Container(
                  color: Colors.black45,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.red, strokeWidth: 3),
                        SizedBox(height: 12),
                        Text(
                          'Buffering...',
                          style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Controls Overlay
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Container(
                  color: Colors.black.withOpacity(0.6),
                  child: Stack(
                    children: [
                      // Header panel
                      Positioned(
                        top: 24,
                        left: 24,
                        right: 24,
                        child: Row(
                          children: [
                            Focus(
                              onKey: (node, event) {
                                if (event is RawKeyDownEvent) {
                                  if (event.logicalKey == LogicalKeyboardKey.select ||
                                      event.logicalKey == LogicalKeyboardKey.enter ||
                                      event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                      event.logicalKey == LogicalKeyboardKey.space) {
                                    Navigator.pop(context);
                                    return KeyEventResult.handled;
                                  }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Builder(
                                builder: (context) {
                                  final focused = Focus.of(context).hasFocus;
                                  return IconButton(
                                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                                    style: IconButton.styleFrom(
                                      backgroundColor: focused ? Colors.red : Colors.black45,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              widget.movieTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Center Play/Pause indicator
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: Icon(
                            _videoController!.value.isPlaying ? Icons.play_arrow : Icons.pause,
                            color: Colors.white,
                            size: 56,
                          ),
                        ),
                      ),

                      // Bottom Progress timeline
                      Positioned(
                        bottom: 24,
                        left: 24,
                        right: 24,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            VideoProgressIndicator(
                              _videoController!,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Colors.red,
                                bufferedColor: Colors.white24,
                                backgroundColor: Colors.white12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  formatDuration(position.inSeconds),
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                                Text(
                                  formatDuration(duration.inSeconds),
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // WebView fallback UI Layout
  Widget _buildWebPlayer() {
    return Focus(
      autofocus: true,
      onKey: (node, event) => _handleWebKeyEvent(event),
      child: Stack(
        children: [
          Positioned.fill(
            child: WebViewWidget(controller: _webViewController),
          ),
          if (_isWebLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.red),
                ),
              ),
            ),
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: Focus(
                onKey: (node, event) {
                  if (event is RawKeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.select ||
                        event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                        event.logicalKey == LogicalKeyboardKey.space) {
                      Navigator.pop(context);
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                      style: IconButton.styleFrom(
                        backgroundColor: focused ? Colors.red : Colors.black54,
                        side: BorderSide(
                          color: focused ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Playback Error',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'An unknown error occurred.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 32),
            Focus(
              autofocus: true,
              onKey: (node, event) {
                if (event is RawKeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                      event.logicalKey == LogicalKeyboardKey.space) {
                    Navigator.pop(context);
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: focused ? Colors.white : Colors.red,
                      foregroundColor: focused ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Go Back'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.red, strokeWidth: 4),
          const SizedBox(height: 24),
          Text(
            widget.movieTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connecting to server & loading stream...',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
