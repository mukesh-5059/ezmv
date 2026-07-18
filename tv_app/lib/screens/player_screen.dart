import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/local_storage.dart';

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final Map<String, String>? headers;
  final String movieTitle;
  final int tmdbId;

  const PlayerScreen({
    Key? key,
    required this.streamUrl,
    this.headers,
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
  
  // Virtual Cursor for Web Player controls & subtitles selection
  double _cursorX = 0.5;
  double _cursorY = 0.5;
  bool _showCursor = false;
  Timer? _cursorTimer;

  // Native Player (Isaimini)
  VideoPlayerController? _videoController;
  bool _isNativeLoading = true;
  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _progressSaveTimer;
  String? _errorMessage;
  String? _rawErrorMessage;
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

    final httpHeaders = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': 'https://${Uri.parse(widget.streamUrl).host}/',
      if (widget.headers != null) ...widget.headers!,
    };

    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(widget.streamUrl),
      formatHint: formatHint,
      httpHeaders: httpHeaders,
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
          _rawErrorMessage = e.toString();
          _errorMessage = _parsePlaybackError(e.toString());
        });
      });

    // Listen for progress change to update overlay UI and catch playback errors
    _videoController!.addListener(() {
      if (_videoController!.value.hasError) {
        final errorMsg = _videoController!.value.errorDescription ?? "Playback error";
        setState(() {
          _rawErrorMessage = errorMsg;
          _errorMessage = _parsePlaybackError(errorMsg);
        });
      }
      if (mounted) setState(() {});
    });
  }

  // Parse raw PlatformException error strings into user-friendly messages
  String _parsePlaybackError(String rawError) {
    final err = rawError.toLowerCase();
    
    if (err.contains('403') || err.contains('forbidden')) {
      return 'Access Forbidden (HTTP 403).\nThe server rejected the playback request, possibly due to expired hotlink tokens or incorrect referrer headers.';
    }
    if (err.contains('404') || err.contains('not found')) {
      return 'Stream Not Found (HTTP 404).\nThis video link is no longer available on the server. Try scraping again or selecting a different source.';
    }
    if (err.contains('410') || err.contains('gone')) {
      return 'Link Expired (HTTP 410).\nThe temporary streaming URL has expired. Please go back and reload the sources.';
    }
    if (err.contains('401') || err.contains('unauthorized')) {
      return 'Unauthorized Access (HTTP 401).\nYou do not have permission to view this video.';
    }
    if (err.contains('unknownhostexception') || err.contains('unable to resolve host') || err.contains('dns')) {
      return 'DNS Resolution Failed.\nThe player could not find the streaming server. Check your internet connection or DNS settings.';
    }
    if (err.contains('connection timed out') || err.contains('sockettimeout') || err.contains('timeout')) {
      return 'Connection Timeout.\nThe connection to the media server timed out. Please check your internet connection and try again.';
    }
    if (err.contains('ssl') || err.contains('certif') || err.contains('tls')) {
      return 'SSL/TLS Handshake Failed.\nCould not establish a secure connection to the media server.';
    }
    if (err.contains('decoder') || err.contains('codec') || err.contains('unsupported format') || err.contains('parserexception')) {
      return 'Video Decoding Failed.\nThe player could not decode this video stream format (unsupported video/audio codecs).';
    }
    if (err.contains('source error') || err.contains('exoplaybackexception')) {
      return 'Media Source Error.\nThe player failed to read the remote media stream. This usually happens when the link has expired or the server is overloaded.';
    }
    
    // Clean up generic Exoplayback exceptions for better readability
    if (rawError.contains('ExoPlaybackException:')) {
      final parts = rawError.split('ExoPlaybackException:');
      if (parts.length > 1) {
        return 'Playback Error: ${parts[1].trim()}';
      }
    }
    
    return rawError;
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
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_isDirectStream) {
        if (_videoController != null && _videoController!.value.isPlaying) {
          final currentSec = _videoController!.value.position.inSeconds;
          if (currentSec > 5) {
            LocalStorage.saveProgress(widget.tmdbId, currentSec);
          }
        }
      } else {
        try {
          final result = await _webViewController.runJavaScriptReturningResult(
            "var v = document.querySelector('video'); v ? v.currentTime : 0;"
          );
          final currentSec = double.tryParse(result.toString())?.toInt();
          if (currentSec != null && currentSec > 5) {
            LocalStorage.saveProgress(widget.tmdbId, currentSec);
          }
        } catch (_) {}
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
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url.toLowerCase();
            final host = Uri.parse(request.url).host.toLowerCase();
            
            // Allow original stream host and known mirror player/delivery domains
            final isTrustedHost = host.contains(Uri.parse(widget.streamUrl).host.toLowerCase()) ||
                                  host.contains('vidsrc') ||
                                  host.contains('cloudnestra') ||
                                  host.contains('cloudorchestranova') ||
                                  host.contains('vsembed') ||
                                  host.contains('putgate');
                                  
            if (request.isMainFrame && !isTrustedHost) {
              print("Adblock: Blocked main frame redirect to $url");
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
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
            // Wait slightly for video element and play button elements to load, then check progress
            Future.delayed(const Duration(milliseconds: 1500), () {
              _checkWebResumeProgress();
              // Try to autoplay bypassing policy blocks
              _webViewController.runJavaScript('''
                setInterval(function() {
                  var v = document.querySelector('video');
                  if (v && v.paused) {
                    v.play().catch(function(e) {
                      var playBtn = document.querySelector('.play-button') || 
                                    document.querySelector('.vjs-big-play-button') || 
                                    document.querySelector('[class*="play"]');
                      if (playBtn) playBtn.click();
                    });
                  }
                }, 1000);
              ''');
            });
          },
          onWebResourceError: (WebResourceError error) {
            print("WebView player error: ${error.description}");
          },
        ),
      )
      ..setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
      ..loadRequest(
        Uri.parse(widget.streamUrl),
        headers: widget.headers ?? {
          'Referer': 'https://${Uri.parse(widget.streamUrl).host}/',
        },
      );

    // Disable media playback user gesture requirement on Android
    final platform = _webViewController.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  Future<void> _checkWebResumeProgress() async {
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

      if (resume == true && mounted) {
        _webViewController.runJavaScript(
          "var v = document.querySelector('video'); if (v) v.currentTime = $savedSeconds;"
        );
      }
    }
    _startProgressSaving();
  }

  void _resetCursorTimer() {
    _cursorTimer?.cancel();
    _cursorTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _showCursor) {
        setState(() {
          _showCursor = false;
        });
      }
    });
  }

  void _triggerWebClick() {
    _webViewController.runJavaScript('''
      (function() {
        var x = window.innerWidth * $_cursorX;
        var y = window.innerHeight * $_cursorY;
        var el = document.elementFromPoint(x, y);
        if (el) {
          el.click();
          var ev1 = new MouseEvent('mousedown', {clientX: x, clientY: y, bubbles: true});
          var ev2 = new MouseEvent('mouseup', {clientX: x, clientY: y, bubbles: true});
          var ev3 = new MouseEvent('click', {clientX: x, clientY: y, bubbles: true});
          el.dispatchEvent(ev1);
          el.dispatchEvent(ev2);
          el.dispatchEvent(ev3);
        }
      })();
    ''');
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
    if (event is! RawKeyDownEvent) return KeyEventResult.ignored;

    _resetCursorTimer();

    // If cursor is showing, D-pad controls the cursor
    if (_showCursor) {
      const step = 0.035; // Cursor move step (fine speed)
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        setState(() {
          _cursorX = (_cursorX - step).clamp(0.01, 0.99);
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        setState(() {
          _cursorX = (_cursorX + step).clamp(0.01, 0.99);
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _cursorY = (_cursorY - step).clamp(0.01, 0.99);
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _cursorY = (_cursorY + step).clamp(0.01, 0.99);
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.select ||
                 event.logicalKey == LogicalKeyboardKey.enter) {
        // Trigger click at cursor position
        _triggerWebClick();
        return KeyEventResult.handled;
      }
    } else {
      // Normal remote mode
      if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        // Pressing Up/Down automatically activates virtual mouse mode!
        setState(() {
          _showCursor = true;
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        // Normal Left: seek back
        _webViewController.runJavaScript(
          "window.dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowLeft', keyCode: 37, bubbles: true}));"
        );
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        // Normal Right: seek forward
        _webViewController.runJavaScript(
          "window.dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowRight', keyCode: 39, bubbles: true}));"
        );
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.select ||
                 event.logicalKey == LogicalKeyboardKey.enter ||
                 event.logicalKey == LogicalKeyboardKey.space) {
        // Toggle play/pause directly on HTML5 video element if available
        _webViewController.runJavaScript(
          "var v = document.querySelector('video'); if (v) { if (v.paused) v.play(); else v.pause(); }"
        );
        // Also dispatch spacebar event to the window
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
    _cursorTimer?.cancel();

    // Allow screen to go to sleep/screensaver again
    WakelockPlus.disable();

    if (_isDirectStream) {
      if (_videoController != null) {
        final currentSec = _videoController!.value.position.inSeconds;
        final durationSec = _videoController!.value.duration.inSeconds;
        
        // Only save progress if they watched/seeked beyond the first 5 seconds (prevents hot restart overwriting)
        if (currentSec > 5) {
          // Clear watch progress if they finished 95% of the movie, else save current position
          if (durationSec > 0 && currentSec / durationSec > 0.95) {
            LocalStorage.clearProgress(widget.tmdbId);
          } else {
            LocalStorage.saveProgress(widget.tmdbId, currentSec);
          }
        }
        _videoController!.dispose();
      }
    } else {
      // WebView progress save on close (only if beyond 5 seconds)
      _webViewController.runJavaScriptReturningResult("var v = document.querySelector('video'); v ? v.currentTime : 0;")
          .then((result) {
            final currentSec = double.tryParse(result.toString())?.toInt();
            if (currentSec != null && currentSec > 5) {
              LocalStorage.saveProgress(widget.tmdbId, currentSec);
            }
          }).catchError((_) {});
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

  Widget _buildWebPlayer() {
    final size = MediaQuery.of(context).size;
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
          if (_showCursor)
            Positioned(
              left: _cursorX * size.width - 8,
              top: _cursorY * size.height - 8,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.85),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 4, spreadRadius: 1),
                  ],
                ),
              ),
            ),
          // System back remote key handles exit
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
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            if (_rawErrorMessage != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                  'Details: $_rawErrorMessage',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ),
            ],
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
