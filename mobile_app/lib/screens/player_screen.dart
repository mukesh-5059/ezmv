import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_core/shared_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../theme.dart';
import '../widgets/resume_dialog.dart';
import '../widgets/subtitle_side_panel.dart';
import '../widgets/subtitle_settings_side_panel.dart';

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final Map<String, String>? headers;
  final String movieTitle;
  final int tmdbId;
  final String mediaType;
  final int? season;
  final int? episode;
  final String provider;
  final String quality;
  final int initialPositionSeconds;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    this.headers,
    required this.movieTitle,
    required this.tmdbId,
    this.mediaType = 'movie',
    this.season,
    this.episode,
    this.provider = 'Direct',
    this.quality = '',
    this.initialPositionSeconds = 0,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;

  Timer? _progressSaveTimer;
  final List<StreamSubscription> _subscriptions = [];
  String? _errorMessage;

  List<SubtitleTrackInfo> _subtitles = [];
  SubtitleTrackInfo? _selectedSubtitle;
  bool _isLoadingSubtitles = false;
  double _subtitleFontSize = 24.0;
  double _subtitleDelaySeconds = 0.0;
  bool _isSpeedingUp = false;
  final BoxFit _fitMode = BoxFit.contain;
  final double _playbackRate = 1.0;

  Map<String, String> get _requestHeaders {
    return {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      if (widget.headers != null) ...widget.headers!,
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

    _initPlayer();
  }

  Future<void> _initPlayer() async {
    _subscriptions.add(_player.stream.error.listen((error) {
      if (mounted && error.isNotEmpty) {
        setState(() => _errorMessage = error);
      }
    }));

    _subscriptions.add(_player.stream.tracks.listen((tracks) {
      final embedded = tracks.subtitle
          .where((t) => t.id != 'no' && t.id != 'auto')
          .map((t) => SubtitleTrackInfo(
                id: t.id,
                language: t.language ?? 'Unknown',
                code: t.language ?? 'und',
                url: '',
                format: 'embedded',
                release: t.title,
              ))
          .toList();

      if (mounted) {
        setState(() {
          final externalTracks = _subtitles.where((s) => s.isExternal).toList();
          _subtitles = [...embedded, ...externalTracks];
        });
      }
    }));

    try {
      await _player.open(
        Media(widget.streamUrl, httpHeaders: _requestHeaders),
        play: true,
      );

      // Check if we should resume
      if (widget.initialPositionSeconds > 15) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final resume = await ResumeDialog.show(
            context: context,
            savedSeconds: widget.initialPositionSeconds,
            formatDuration: _formatDuration,
          );
          if (resume == true) {
            await _player.seek(Duration(seconds: widget.initialPositionSeconds));
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    }

    _loadInitialSubtitleSettings();
    _loadSubtitlesAsync();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
  }

  Future<void> _loadInitialSubtitleSettings() async {
    final savedFontSize = await LocalStorage.getSubtitleFontSize();
    final savedDelay = await LocalStorage.getSubtitleDelay(
      widget.tmdbId,
      mediaType: widget.mediaType,
      season: widget.season,
      episode: widget.episode,
    );
    if (mounted) {
      setState(() {
        _subtitleFontSize = savedFontSize > 0 ? (savedFontSize * 0.6).clamp(16.0, 36.0) : 24.0;
        _subtitleDelaySeconds = savedDelay;
      });
      if (savedDelay != 0.0) {
        try {
          (_player.platform as dynamic)?.setProperty('sub-delay', savedDelay.toStringAsFixed(3));
        } catch (_) {}
      }
    }
  }

  Future<void> _loadSubtitlesAsync() async {
    if (!mounted) return;
    setState(() => _isLoadingSubtitles = true);
    try {
      final tracks = await ApiClient.getSubtitles(
        widget.tmdbId,
        mediaType: widget.mediaType,
        season: widget.season,
        episode: widget.episode,
      );
      if (!mounted) return;

      final savedChoice = await LocalStorage.getSubtitleChoice(
        widget.tmdbId,
        mediaType: widget.mediaType,
        season: widget.season,
        episode: widget.episode,
      );

      SubtitleTrackInfo? trackToSelect;
      if (savedChoice == 'none') {
        trackToSelect = null;
      } else if (savedChoice != null && savedChoice.isNotEmpty) {
        final match = tracks.where((t) => t.url == savedChoice || t.name == savedChoice).toList();
        if (match.isNotEmpty) {
          trackToSelect = match.first;
        } else {
          final eng = tracks.where((t) => t.isEnglish).toList();
          trackToSelect = eng.isNotEmpty ? eng.first : (tracks.isNotEmpty ? tracks.first : null);
        }
      } else {
        // Auto select English if available
        final eng = tracks.where((t) => t.isEnglish).toList();
        if (eng.isNotEmpty) {
          trackToSelect = eng.first;
        }
      }

      setState(() {
        final embedded = _subtitles.where((s) => !s.isExternal).toList();
        _subtitles = [...embedded, ...tracks];
        _isLoadingSubtitles = false;
      });

      if (trackToSelect != null) {
        _applySubtitleTrack(trackToSelect);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingSubtitles = false);
    }
  }

  Future<void> _applySubtitleTrack(SubtitleTrackInfo track) async {
    setState(() => _selectedSubtitle = track);
    await LocalStorage.setSubtitleChoice(
      widget.tmdbId,
      track.url.isNotEmpty ? track.url : track.name,
      mediaType: widget.mediaType,
      season: widget.season,
      episode: widget.episode,
    );

    if (track.isExternal && track.url.isNotEmpty) {
      await _player.setSubtitleTrack(SubtitleTrack.uri(track.url, title: track.name, language: track.language));
    } else if (track.id != null) {
      await _player.setSubtitleTrack(SubtitleTrack(track.id!, track.name, track.language));
    }
  }

  Future<void> _disableSubtitles() async {
    setState(() => _selectedSubtitle = null);
    await LocalStorage.setSubtitleChoice(
      widget.tmdbId,
      'none',
      mediaType: widget.mediaType,
      season: widget.season,
      episode: widget.episode,
    );
    await _player.setSubtitleTrack(SubtitleTrack.no());
  }

  void _saveProgress() {
    final pos = _player.state.position;
    final dur = _player.state.duration;
    if (dur.inSeconds > 30) {
      // Check & auto-mark watched (remaining <= 300s or progress >= 92%)
      LocalStorage.checkAndAutoMarkWatched(
        widget.tmdbId,
        pos.inSeconds,
        dur.inSeconds,
        mediaType: widget.mediaType,
        season: widget.season,
        episode: widget.episode,
      );

      // Clear timestamp only at the very end (remaining <= 30s or progress >= 98%)
      final remaining = dur.inSeconds - pos.inSeconds;
      final progressRatio = pos.inSeconds / dur.inSeconds;
      if (remaining <= 30 || progressRatio >= 0.98) {
        LocalStorage.clearProgress(
          widget.tmdbId,
          mediaType: widget.mediaType,
          season: widget.season,
          episode: widget.episode,
        );
      } else {
        LocalStorage.saveProgress(
          widget.tmdbId,
          pos.inSeconds,
          totalDurationSeconds: dur.inSeconds,
          mediaType: widget.mediaType,
          season: widget.season,
          episode: widget.episode,
        );
      }
    }
  }

  String _formatDuration(int totalSecs) {
    final hours = totalSecs ~/ 3600;
    final minutes = (totalSecs % 3600) ~/ 60;
    final seconds = totalSecs % 60;
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  Future<void> _openSubtitleSidePanel() async {
    final result = await SubtitleSidePanel.show(
      context: context,
      subtitles: _subtitles,
      selectedSubtitle: _selectedSubtitle,
      isLoading: _isLoadingSubtitles,
    );

    if (result != null) {
      if (result.isOff) {
        _disableSubtitles();
      } else if (result.track != null) {
        _applySubtitleTrack(result.track!);
      }
    }
  }

  Future<void> _openSubtitleSettingsSidePanel() async {
    await SubtitleSettingsSidePanel.show(
      context: context,
      initialFontSize: _subtitleFontSize,
      initialDelaySeconds: _subtitleDelaySeconds,
      onFontSizeChanged: (size) async {
        setState(() => _subtitleFontSize = size);
        await LocalStorage.setSubtitleFontSize(size);
        try {
          (_player.platform as dynamic)?.setProperty('sub-font-size', size.toStringAsFixed(0));
        } catch (_) {}
      },
      onDelayChanged: (delay) async {
        setState(() => _subtitleDelaySeconds = delay);
        await LocalStorage.setSubtitleDelay(
          widget.tmdbId,
          delay,
          mediaType: widget.mediaType,
          season: widget.season,
          episode: widget.episode,
        );
        try {
          (_player.platform as dynamic)?.setProperty('sub-delay', delay.toStringAsFixed(3));
        } catch (_) {}
      },
    );
  }

  @override
  void dispose() {
    _saveProgress();
    _progressSaveTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _player.dispose();

    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MaterialVideoControlsTheme(
        normal: MaterialVideoControlsThemeData(
          volumeGesture: true,
          brightnessGesture: true,
          seekGesture: true,
          seekOnDoubleTap: true,
          topButtonBar: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.movieTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (widget.quality.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: MobileTheme.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: MobileTheme.accent, width: 0.8),
                ),
                child: Text(
                  widget.quality,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            IconButton(
              icon: Icon(
                _selectedSubtitle != null ? Icons.subtitles_rounded : Icons.subtitles_outlined,
                color: _selectedSubtitle != null ? MobileTheme.accent : Colors.white,
              ),
              tooltip: 'Subtitles',
              onPressed: _openSubtitleSidePanel,
            ),
            IconButton(
              icon: const Icon(Icons.tune_rounded, color: Colors.white),
              tooltip: 'Subtitle Settings',
              onPressed: _openSubtitleSettingsSidePanel,
            ),
          ],
        ),
        fullscreen: const MaterialVideoControlsThemeData(
          volumeGesture: true,
          brightnessGesture: true,
          seekGesture: true,
          seekOnDoubleTap: true,
        ),
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (_) {
                if (_player.state.playing) {
                  _player.setRate(2.0);
                  setState(() => _isSpeedingUp = true);
                }
              },
              onLongPressEnd: (_) {
                if (_isSpeedingUp) {
                  _player.setRate(_playbackRate);
                  setState(() => _isSpeedingUp = false);
                }
              },
              onLongPressCancel: () {
                if (_isSpeedingUp) {
                  _player.setRate(_playbackRate);
                  setState(() => _isSpeedingUp = false);
                }
              },
              child: Video(
                controller: _videoController,
                controls: MaterialVideoControls,
                fit: _fitMode,
              ),
            ),
            if (_isSpeedingUp)
              Positioned(
                top: 54,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fast_forward_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text(
                          '2X Speed',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_errorMessage != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MobileTheme.accent),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: MobileTheme.accent, size: 40),
                      const SizedBox(height: 12),
                      const Text(
                        'Playback Error',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(backgroundColor: MobileTheme.accent),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
