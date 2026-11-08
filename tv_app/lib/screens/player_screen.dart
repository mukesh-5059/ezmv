import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_core/shared_core.dart' hide SubtitleTrack;
import 'package:wakelock_plus/wakelock_plus.dart';
import '../theme.dart';
import '../widgets/player_hud.dart';
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

enum PlayerDrawerType {
  none,
  sources,
  audio,
  episodes,
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
  final List<SeasonSummary>? seasons;
  final String? overview;
  final String? releaseDate;
  final double? ratingScore;
  final int? voteCount;
  final List<String>? genres;
  final String? originalLanguage;

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
    this.seasons,
    this.overview,
    this.releaseDate,
    this.ratingScore,
    this.voteCount,
    this.genres,
    this.originalLanguage,
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
      seasons: (map['seasons'] as List?)?.map((s) => s is SeasonSummary ? s : SeasonSummary.fromJson(s as Map<String, dynamic>)).toList(),
      overview: map['overview'] as String?,
      releaseDate: map['releaseDate'] as String?,
      ratingScore: (map['ratingScore'] as num?)?.toDouble(),
      voteCount: (map['voteCount'] as num?)?.toInt(),
      genres: (map['genres'] as List?)?.map((g) => g.toString()).toList(),
      originalLanguage: map['originalLanguage'] as String?,
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
  final FocusNode _episodesButtonFocus = FocusNode();

  Timer? _progressSaveTimer;
  Timer? _osdHideTimer;
  Timer? _seekCommitTimer;
  Timer? _playbackWatchdogTimer;
  Duration? _pendingSeekPosition;
  int _accumulatedSeekDelta = 0;
  final List<StreamSubscription> _subscriptions = [];

  String? _errorMessage;
  bool _isExiting = false;
  bool _showOsd = false;
  bool _isPlaying = true;
  bool _isBuffering = false;

  // Drawer state
  PlayerDrawerType _activeDrawer = PlayerDrawerType.none;
  bool _wasPlayingBeforeDrawer = false;
  int? _currentSeason;
  int? _currentEpisode;
  List<SeasonSummary> _seasonsList = [];
  TvSeason? _currentDrawerSeason;
  bool _isLoadingDrawerSeason = false;
  bool _isLoadingDrawerEpisodeStreams = false;
  bool _isLoadingDrawerSources = false;
  StreamSubscription<StreamProgressEvent>? _drawerSseSubscription;
  String _drawerSseMessage = 'Connecting to scrapers...';
  final Map<String, ({StreamProgressStatus status, int count})> _drawerProviderStatuses = {};
  int _drawerTotalDiscovered = 0;
  final Set<String> _failedStreamUrls = {};
  bool _isSwitchingStream = false;

  // Subtitles & Audio
  List<SubtitleTrackInfo> _subtitles = [];
  SubtitleTrackInfo? _selectedSubtitle;
  bool _isLoadingSubtitles = false;
  double _subtitleFontSize = 42.0;
  bool _tamilAudioSelectedForCurrentMedia = false;
  DateTime? _lastBackPressTime;

  late String _currentStreamUrl;
  late String _currentQuality;
  late String _currentProvider;
  Map<String, String>? _currentHeaders;
  List<StreamSource> _availableStreams = [];

  Map<String, String> get _requestHeaders {
    return {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      if (_currentHeaders != null) ..._currentHeaders!,
    };
  }

  @override
  void initState() {
    super.initState();
    _currentStreamUrl = widget.streamUrl;
    _currentQuality = widget.quality;
    _currentProvider = widget.provider;
    _currentHeaders = widget.headers;
    _availableStreams = widget.availableStreams != null ? List<StreamSource>.from(widget.availableStreams!) : [];
    _currentSeason = widget.season ?? 1;
    _currentEpisode = widget.episode ?? 1;
    _seasonsList = widget.seasons ?? [];

    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Initialize media_kit Player with hardware decoding & buffering configuration
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
      ),
    );

    _configureHardwareAndBuffer();

    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        androidAttachSurfaceAfterVideoParameters: true,
      ),
    );

    StorageService.instance.getSubtitleFontSize().then((size) {
      if (mounted) setState(() => _subtitleFontSize = size);
    });

    _initPlayerListenersAndOpen();
    _probeUnprobedAvailableStreams();
  }

  void _configureHardwareAndBuffer() {
    try {
      final p = (_player.platform as dynamic);
      p?.setProperty('vd-lavc-threads', '4');

      // Network & Buffer Stability for Android TVs
      p?.setProperty('demuxer-readahead-secs', '30');
      p?.setProperty('network-timeout', '25');

      // Reconnect & HTTP resilience
      p?.setProperty(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=10',
      );
    } catch (_) {}
  }

  void _startPlaybackWatchdog() {
    _playbackWatchdogTimer?.cancel();
    _playbackWatchdogTimer = Timer(const Duration(seconds: 12), () {
      if (mounted && _player.state.position == Duration.zero && _player.state.buffer == Duration.zero) {
        _handlePlaybackFailure('Stream stalled: audio/video failed to decode within 12 seconds');
      }
    });
  }

  void _cancelPlaybackWatchdog() {
    _playbackWatchdogTimer?.cancel();
    _playbackWatchdogTimer = null;
  }

  Future<void> _initPlayerListenersAndOpen() async {
    // CRITICAL: Update ValueNotifier WITHOUT calling setState on PlayerScreen
    _subscriptions.add(
      _player.stream.position.listen((pos) {
        if (pos > Duration.zero) {
          _cancelPlaybackWatchdog();
          if (_isBuffering && !_player.state.buffering && mounted) {
            setState(() => _isBuffering = false);
          }
        }
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
          _handlePlaybackFailure(err);
        }
      }),
    );
    _subscriptions.add(
      _player.stream.tracks.listen((tracks) {
        _autoSelectTamilAudio(tracks.audio);
      }),
    );

    try {
      _startPlaybackWatchdog();
      _tamilAudioSelectedForCurrentMedia = false;
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
        await _handlePlaybackFailure(e.toString());
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
        tmdbId: widget.tmdbId,
        title: widget.movieTitle,
        posterPath: widget.posterPath,
        backdropPath: widget.backdropPath,
        mediaType: widget.mediaType,
        season: widget.season,
        episode: widget.episode,
        positionMs: posMs,
        durationMs: durMs,
        updatedAt: DateTime.now(),
        overview: widget.overview,
        releaseDate: widget.releaseDate,
        ratingScore: widget.ratingScore,
        voteCount: widget.voteCount,
        genres: widget.genres,
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

  void _autoSelectTamilAudio(List<AudioTrack> tracks) {
    if (_tamilAudioSelectedForCurrentMedia || tracks.isEmpty) return;
    for (final track in tracks) {
      final lang = track.language?.toLowerCase() ?? '';
      final title = track.title?.toLowerCase() ?? '';
      if (lang == 'ta' ||
          lang == 'tam' ||
          lang.contains('tamil') ||
          title.contains('tamil') ||
          title.contains('[tam]') ||
          title.contains('(tam)')) {
        if (_player.state.track.audio.id != track.id) {
          _player.setAudioTrack(track);
        }
        _tamilAudioSelectedForCurrentMedia = true;
        _hudController.triggerInfo('Audio: Tamil');
        break;
      }
    }
  }

  bool _handleBackAction() {
    final now = DateTime.now();
    if (_lastBackPressTime != null && now.difference(_lastBackPressTime!).inMilliseconds < 400) {
      return true;
    }
    _lastBackPressTime = now;

    if (_activeDrawer != PlayerDrawerType.none) {
      _closeDrawer();
      return true;
    } else if (_showOsd) {
      _hideOsdControls();
      return true;
    } else {
      _exitPlayer();
      return true;
    }
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
      _handleBackAction();
      return KeyEventResult.handled;
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

  Future<void> _handlePlaybackFailure(String err) async {
    if (!mounted || _isSwitchingStream) return;
    _cancelPlaybackWatchdog();
    _failedStreamUrls.add(_currentStreamUrl);

    // Auto-stream fallback: Find next stream that has not failed
    StreamSource? fallbackStream;
    for (final s in _availableStreams) {
      if (!_failedStreamUrls.contains(s.url) && s.url != _currentStreamUrl) {
        fallbackStream = s;
        break;
      }
    }

    if (fallbackStream != null) {
      _hudController.triggerInfo('Playback failed. Auto-switching to ${fallbackStream.provider} (${fallbackStream.quality})...');
      await _switchStream(fallbackStream, preservePosition: true);

      final runtimeMins = _player.state.duration > Duration.zero ? _player.state.duration.inMinutes : null;
      final unprobed = _availableStreams.where((s) => !_failedStreamUrls.contains(s.url) && s.url != fallbackStream!.url && s.headroomRatio == null).toList();
      if (unprobed.isNotEmpty) {
        StreamRanker.findNextFallback(unprobed, runtimeMinutes: runtimeMins).then((newFallback) {
          if (newFallback != null && mounted) {
            setState(() {
              final idx = _availableStreams.indexWhere((s) => s.url == newFallback.url);
              if (idx != -1) {
                _availableStreams[idx] = newFallback;
              } else {
                _availableStreams.add(newFallback);
              }
            });
          }
        });
      }
      _probeUnprobedAvailableStreams();
    } else {
      if (mounted) {
        setState(() {
          _errorMessage = 'Playback failed. No alternative streams available.';
        });
      }
    }
  }

  void _probeUnprobedAvailableStreams() {
    final unprobed = _availableStreams
        .where((s) => s.headroomRatio == null && !_failedStreamUrls.contains(s.url))
        .toList();
    if (unprobed.isEmpty) return;

    Future.microtask(() async {
      for (final stream in unprobed) {
        if (!mounted) break;
        if (_failedStreamUrls.contains(stream.url)) continue;

        final runtimeMins = _player.state.duration > Duration.zero ? _player.state.duration.inMinutes : null;
        final metrics = await StreamRanker.probeStream(
          stream,
          runtimeMinutes: runtimeMins,
          timeout: const Duration(milliseconds: 2500),
        );
        if (!mounted) break;

        final headroom = metrics?.headroomRatio ?? 0.0;
        setState(() {
          final updated = List<StreamSource>.from(_availableStreams);
          final idx = updated.indexWhere((s) => s.url == stream.url);
          if (idx != -1) {
            updated[idx] = stream.copyWith(headroomRatio: headroom);
            _availableStreams = updated;
          }
        });
      }
    });
  }

  Future<void> _switchStream(StreamSource stream, {bool preservePosition = true}) async {
    if (_isSwitchingStream) return;
    _isSwitchingStream = true;
    final pos = preservePosition ? _player.state.position : Duration.zero;
    _saveProgress();

    setState(() {
      _currentStreamUrl = stream.url;
      _currentQuality = stream.quality;
      _currentProvider = stream.provider;
      _currentHeaders = stream.headers;
      _errorMessage = null;
      _isBuffering = true;
      _tamilAudioSelectedForCurrentMedia = false;
    });

    try {
      _startPlaybackWatchdog();
      // Hardware Guardrail: Stop previous pipeline cleanly before opening new stream
      await _player.stop();
      await _player.open(
        Media(stream.url, httpHeaders: _requestHeaders),
      );

      if (pos > Duration.zero) {
        _player.stream.buffer.firstWhere((b) => b > Duration.zero).then((_) async {
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) {
            await _player.seek(pos);
            _hudController.triggerInfo('Resumed at ${_formatDuration(pos.inSeconds)}');
          }
        }).catchError((_) {});
      }
      _hudController.triggerInfo('Playing: ${stream.quality} (${stream.provider})');
    } catch (e) {
      await _handlePlaybackFailure(e.toString());
    } finally {
      _isSwitchingStream = false;
    }
  }

  // --- Right-Anchored TV Drawers (Sources, Audio, Episodes) ---

  void _openDrawer(PlayerDrawerType type) {
    _hideOsdControls();
    _wasPlayingBeforeDrawer = _isPlaying;
    if (_isPlaying) {
      _player.pause();
    }
    setState(() => _activeDrawer = type);

    if (type == PlayerDrawerType.episodes && _currentDrawerSeason == null) {
      _loadDrawerSeasonEpisodes(_currentSeason ?? 1);
    } else if (type == PlayerDrawerType.sources && _availableStreams.isEmpty) {
      _loadDrawerSources();
    }
  }

  void _closeDrawer() {
    _lastBackPressTime = DateTime.now();
    _drawerSseSubscription?.cancel();
    if (_activeDrawer != PlayerDrawerType.none) {
      setState(() => _activeDrawer = PlayerDrawerType.none);
      if (_wasPlayingBeforeDrawer) {
        _player.play();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mainFocusNode.requestFocus();
      });
    }
  }

  Future<void> _loadDrawerSources() async {
    if (widget.imdbId.isEmpty) return;
    _drawerSseSubscription?.cancel();
    setState(() {
      _isLoadingDrawerSources = true;
      _drawerProviderStatuses.clear();
      _drawerTotalDiscovered = 0;
      _drawerSseMessage = 'Connecting to scrapers...';
    });

    _drawerSseSubscription = ApiClient.instance.getStreamsProgressive(
      widget.mediaType,
      widget.imdbId,
      season: _currentSeason,
      episode: _currentEpisode,
      originalLanguage: widget.originalLanguage,
    ).listen(
      (event) {
        if (!mounted) return;
        if (event.isDone) {
          final resolvedStreams = event.streams ?? [];
          if (resolvedStreams.isNotEmpty) {
            setState(() {
              _drawerSseMessage = 'Ranking streams for optimal playback...';
            });
            StreamRanker.rankStreams(
              resolvedStreams,
              onProgress: (msg, probed, qual) {
                if (mounted) setState(() => _drawerSseMessage = msg);
              },
            ).then((ranked) {
              if (!mounted) return;
              setState(() {
                _availableStreams = [
                  ranked.topStream,
                  ...ranked.fallbackStreams,
                  ...ranked.unprobedStreams,
                ];
                _isLoadingDrawerSources = false;
              });
            }).catchError((_) {
              if (!mounted) return;
              setState(() {
                _availableStreams = resolvedStreams;
                _isLoadingDrawerSources = false;
              });
            });
          } else {
            setState(() {
              _availableStreams = [];
              _isLoadingDrawerSources = false;
            });
          }
          return;
        }

        if (event.status == StreamProgressStatus.error) {
          if (event.provider != 'all') {
            setState(() {
              _drawerProviderStatuses[event.provider] = (status: StreamProgressStatus.error, count: 0);
            });
          }
          return;
        }

        if (event.provider != 'all') {
          setState(() {
            _drawerProviderStatuses[event.provider] = (
              status: event.status,
              count: event.count ?? _drawerProviderStatuses[event.provider]?.count ?? 0,
            );
            if (event.status == StreamProgressStatus.searching) {
              _drawerSseMessage = 'Searching ${event.provider}...';
            } else if (event.status == StreamProgressStatus.resolved) {
              _drawerSseMessage = '${event.provider}: ${event.count ?? 0} found';
              _drawerTotalDiscovered = _drawerProviderStatuses.values.fold(0, (acc, p) => acc + p.count);
            }
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isLoadingDrawerSources = false);
      },
      onDone: () {
        if (mounted && _isLoadingDrawerSources && _availableStreams.isEmpty) {
          setState(() => _isLoadingDrawerSources = false);
        }
      },
    );
  }

  Future<void> _loadDrawerSeasonEpisodes([int? seasonNum]) async {
    final targetSeason = seasonNum ?? _currentSeason ?? 1;
    setState(() {
      _isLoadingDrawerSeason = true;
      _currentSeason = targetSeason;
    });
    try {
      int? tmdbId = widget.tmdbId;
      if ((tmdbId == null || tmdbId == 0) && widget.imdbId.isNotEmpty) {
        final details = await ApiClient.instance.getMovieDetails('tv', widget.imdbId);
        tmdbId = details.tmdbId;
        if (_seasonsList.isEmpty && details.seasons.isNotEmpty) {
          _seasonsList = details.seasons;
        }
      }
      if (tmdbId != null && tmdbId > 0) {
        final season = await ApiClient.instance.getTvSeason(tmdbId, targetSeason);
        if (mounted) {
          setState(() {
            _currentDrawerSeason = season;
            _isLoadingDrawerSeason = false;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingDrawerSeason = false);
  }

  Future<void> _selectEpisodeInDrawer(TvEpisode episode) async {
    if (_isLoadingDrawerEpisodeStreams) return;
    _drawerSseSubscription?.cancel();
    setState(() {
      _isLoadingDrawerEpisodeStreams = true;
      _drawerProviderStatuses.clear();
      _drawerTotalDiscovered = 0;
      _drawerSseMessage = 'Connecting to scrapers...';
    });

    final seasonNum = _currentDrawerSeason?.seasonNumber ?? _currentSeason ?? 1;
    _drawerSseSubscription = ApiClient.instance.getStreamsProgressive(
      'tv',
      widget.imdbId,
      season: seasonNum,
      episode: episode.episodeNumber,
      originalLanguage: widget.originalLanguage,
    ).listen(
      (event) async {
        if (!mounted) return;
        if (event.isDone) {
          final streams = event.streams ?? [];
          if (streams.isNotEmpty) {
            _currentSeason = seasonNum;
            _currentEpisode = episode.episodeNumber;
            _availableStreams = streams;
            _failedStreamUrls.clear();
            _closeDrawer();
            _hudController.triggerInfo('Playing S${seasonNum}E${episode.episodeNumber}: ${episode.name}');
            await _switchStream(streams.first, preservePosition: false);
            _probeUnprobedAvailableStreams();
          } else {
            _hudController.triggerInfo('No streams available for this episode');
          }
          setState(() => _isLoadingDrawerEpisodeStreams = false);
          return;
        }

        if (event.status == StreamProgressStatus.error) {
          if (event.provider != 'all') {
            setState(() {
              _drawerProviderStatuses[event.provider] = (status: StreamProgressStatus.error, count: 0);
            });
          }
          return;
        }

        if (event.provider != 'all') {
          setState(() {
            _drawerProviderStatuses[event.provider] = (
              status: event.status,
              count: event.count ?? _drawerProviderStatuses[event.provider]?.count ?? 0,
            );
            if (event.status == StreamProgressStatus.searching) {
              _drawerSseMessage = 'Searching ${event.provider}...';
            } else if (event.status == StreamProgressStatus.resolved) {
              _drawerSseMessage = '${event.provider}: ${event.count ?? 0} found';
              _drawerTotalDiscovered = _drawerProviderStatuses.values.fold(0, (acc, p) => acc + p.count);
            }
          });
        }
      },
      onError: (_) {
        if (!mounted) return;
        _hudController.triggerInfo('Failed to fetch episode streams');
        setState(() => _isLoadingDrawerEpisodeStreams = false);
      },
      onDone: () {
        if (mounted && _isLoadingDrawerEpisodeStreams) {
          setState(() => _isLoadingDrawerEpisodeStreams = false);
        }
      },
    );
  }

  String _formatAudioTrackLabel(AudioTrack track) {
    final langCode = track.language?.toLowerCase() ?? '';
    const languageMap = {
      'ta': 'Tamil',
      'tam': 'Tamil',
      'en': 'English',
      'eng': 'English',
      'hi': 'Hindi',
      'hin': 'Hindi',
      'te': 'Telugu',
      'tel': 'Telugu',
      'ml': 'Malayalam',
      'mal': 'Malayalam',
      'kn': 'Kannada',
      'kan': 'Kannada',
      'bn': 'Bengali',
      'ben': 'Bengali',
      'mr': 'Marathi',
      'mar': 'Marathi',
      'es': 'Spanish',
      'spa': 'Spanish',
      'fr': 'French',
      'fra': 'French',
      'de': 'German',
      'ger': 'German',
      'deu': 'German',
      'it': 'Italian',
      'ita': 'Italian',
      'ja': 'Japanese',
      'jpn': 'Japanese',
      'ko': 'Korean',
      'kor': 'Korean',
      'zh': 'Chinese',
      'zho': 'Chinese',
      'chi': 'Chinese',
      'ru': 'Russian',
      'rus': 'Russian',
      'pt': 'Portuguese',
      'por': 'Portuguese',
      'ar': 'Arabic',
      'ara': 'Arabic',
      'und': 'Undetermined',
    };
    final langName = languageMap[langCode] ?? (track.language?.isNotEmpty == true ? track.language!.toUpperCase() : null);
    final title = track.title;
    if (title != null && title.isNotEmpty) {
      if (langName != null && !title.toLowerCase().contains(langName.toLowerCase())) {
        return '$title ($langName)';
      }
      return title;
    }
    if (langName != null) return langName;
    return 'Track #${track.id}';
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
    _playbackWatchdogTimer?.cancel();

    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _drawerSseSubscription?.cancel();

    _saveProgress();

    // Critical Hardware Guardrail for Amlogic & TV Decoders:
    _player.stop();
    _player.dispose();

    _mainFocusNode.dispose();
    _playPauseButtonFocus.dispose();
    _subtitlesButtonFocus.dispose();
    _audioTrackButtonFocus.dispose();
    _sourceSwitcherButtonFocus.dispose();
    _episodesButtonFocus.dispose();
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
        _handleBackAction();
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
              if (_isBuffering && !_showOsd && _activeDrawer == PlayerDrawerType.none)
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

              // Right-Anchored Side Drawer (Sources, Audio, Episodes)
              _buildDrawerOverlay(),
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
                    _openDrawer(PlayerDrawerType.audio);
                  },
                ),
                const SizedBox(width: 24),
                _buildOsdIconButton(
                  focusNode: _sourceSwitcherButtonFocus,
                  icon: Icons.tune_rounded,
                  label: 'Sources',
                  prevFocus: _audioTrackButtonFocus,
                  nextFocus: widget.mediaType == 'tv' ? _episodesButtonFocus : null,
                  onPressed: () {
                    _resetOsdTimer();
                    _openDrawer(PlayerDrawerType.sources);
                  },
                ),
                if (widget.mediaType == 'tv') ...[
                  const SizedBox(width: 24),
                  _buildOsdIconButton(
                    focusNode: _episodesButtonFocus,
                    icon: Icons.video_library_rounded,
                    label: 'Episodes',
                    prevFocus: _sourceSwitcherButtonFocus,
                    onPressed: () {
                      _resetOsdTimer();
                      _openDrawer(PlayerDrawerType.episodes);
                    },
                  ),
                ],
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

  // --- Right-Anchored Side Drawer Overlay ---

  Widget _buildDrawerOverlay() {
    if (_activeDrawer == PlayerDrawerType.none) return const SizedBox.shrink();

    String title;
    Widget content;
    switch (_activeDrawer) {
      case PlayerDrawerType.sources:
        title = 'Sources';
        content = _buildSourcesDrawerContent();
        break;
      case PlayerDrawerType.audio:
        title = 'Audio Tracks';
        content = _buildAudioDrawerContent();
        break;
      case PlayerDrawerType.episodes:
        title = 'Episodes';
        content = _buildEpisodesDrawerContent();
        break;
      case PlayerDrawerType.none:
        title = '';
        content = const SizedBox.shrink();
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _closeDrawer,
            child: Container(color: Colors.black54),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: _activeDrawer == PlayerDrawerType.sources ? 460 : 420,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF16161E),
              border: Border(left: BorderSide(color: Colors.white12, width: 1)),
              boxShadow: [
                BoxShadow(color: Colors.black87, blurRadius: 24, spreadRadius: 4),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: _closeDrawer,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourcesDrawerContent() {
    if (_isLoadingDrawerSources || _availableStreams.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                _drawerSseMessage,
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
              if (_drawerProviderStatuses.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: _drawerProviderStatuses.entries.map((e) {
                    final isSearching = e.value.status == StreamProgressStatus.searching;
                    final isResolved = e.value.status == StreamProgressStatus.resolved;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isResolved && e.value.count > 0
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        isSearching ? '${e.key}...' : '${e.key} (${e.value.count})',
                        style: TextStyle(
                          fontSize: 11,
                          color: isResolved && e.value.count > 0 ? Colors.greenAccent : Colors.white70,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _availableStreams.length,
      itemBuilder: (ctx, idx) {
        final stream = _availableStreams[idx];
        final isSelected = stream.url == _currentStreamUrl;
        return _SourcesDrawerItem(
          stream: stream,
          isSelected: isSelected,
          autofocus: idx == 0,
          onTap: () {
            _closeDrawer();
            if (stream.url != _currentStreamUrl) {
              _switchStream(stream, preservePosition: true);
            }
          },
          onBack: _closeDrawer,
        );
      },
    );
  }

  Widget _buildAudioDrawerContent() {
    final tracks = _player.state.tracks.audio;
    final currentTrack = _player.state.track.audio;

    if (tracks.isEmpty) {
      return const Center(
        child: Text(
          'No alternative audio tracks available',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, idx) {
        final t = tracks[idx];
        final isSelected = currentTrack.id == t.id;
        final label = _formatAudioTrackLabel(t);
        return _DrawerTile(
          autofocus: isSelected || (idx == 0 && currentTrack.id.isEmpty),
          title: label,
          subtitle: t.channels != null ? '${t.channels} channels' : null,
          isSelected: isSelected,
          onTap: () async {
            await _player.setAudioTrack(t);
            _hudController.triggerInfo('Audio: $label');
            _closeDrawer();
          },
          onBack: _closeDrawer,
        );
      },
    );
  }

  Widget _buildEpisodesDrawerContent() {
    if (_isLoadingDrawerEpisodeStreams) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                _drawerSseMessage,
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
              if (_drawerProviderStatuses.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: _drawerProviderStatuses.entries.map((e) {
                    final isSearching = e.value.status == StreamProgressStatus.searching;
                    final isResolved = e.value.status == StreamProgressStatus.resolved;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isResolved && e.value.count > 0
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        isSearching ? '${e.key}...' : '${e.key} (${e.value.count})',
                        style: TextStyle(
                          fontSize: 11,
                          color: isResolved && e.value.count > 0 ? Colors.greenAccent : Colors.white70,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (_isLoadingDrawerSeason) {
      return const Center(
        child: CircularProgressIndicator(color: TVTheme.primary),
      );
    }

    final episodes = _currentDrawerSeason?.episodes ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_seasonsList.length > 1)
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: _seasonsList.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, idx) {
                final s = _seasonsList[idx];
                final isSelected = s.seasonNumber == (_currentDrawerSeason?.seasonNumber ?? _currentSeason);
                return _SeasonPill(
                  label: s.name.isNotEmpty ? s.name : 'Season ${s.seasonNumber}',
                  isSelected: isSelected,
                  onTap: () => _loadDrawerSeasonEpisodes(s.seasonNumber),
                  onBack: _closeDrawer,
                );
              },
            ),
          ),
        if (_seasonsList.length > 1)
          const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: episodes.isEmpty
              ? const Center(
                  child: Text('No episodes found', style: TextStyle(color: Colors.white70)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: episodes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) {
                    final ep = episodes[idx];
                    final isPlayingThis = ep.episodeNumber == _currentEpisode &&
                        (_currentDrawerSeason?.seasonNumber ?? _currentSeason) == _currentSeason;
                    final subtitleParts = <String>[];
                    if (ep.formattedRuntime.isNotEmpty) subtitleParts.add(ep.formattedRuntime);
                    if (ep.formattedAirDate.isNotEmpty) {
                      subtitleParts.add(ep.isUpcoming ? 'Airs ${ep.formattedAirDate}' : ep.formattedAirDate);
                    }
                    if (ep.isUpcoming) subtitleParts.add('Unreleased');
                    return _DrawerTile(
                      autofocus: isPlayingThis || (idx == 0 && _currentEpisode == null),
                      title: 'E${ep.episodeNumber}: ${ep.name}',
                      subtitle: subtitleParts.isNotEmpty ? subtitleParts.join(' • ') : null,
                      isSelected: isPlayingThis,
                      onTap: () => _selectEpisodeInDrawer(ep),
                      onBack: _closeDrawer,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SourcesDrawerItem extends StatefulWidget {
  final StreamSource stream;
  final bool isSelected;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback onBack;

  const _SourcesDrawerItem({
    required this.stream,
    required this.isSelected,
    required this.autofocus,
    required this.onTap,
    required this.onBack,
  });

  @override
  State<_SourcesDrawerItem> createState() => _SourcesDrawerItemState();
}

class _SourcesDrawerItemState extends State<_SourcesDrawerItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stream;
    final langs = s.languages.isNotEmpty ? s.languages.join(', ') : 'Default';

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.backspace ||
              event.logicalKey == LogicalKeyboardKey.goBack) {
            widget.onBack();
            return KeyEventResult.handled;
          }
        }
        return TvShortcuts.handleKeyEvent(event, onActivate: widget.onTap);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isFocused
                ? TVTheme.primary.withValues(alpha: 0.25)
                : widget.isSelected
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? Colors.white
                  : widget.isSelected
                      ? TVTheme.primary.withValues(alpha: 0.6)
                      : Colors.white12,
              width: _isFocused ? 2 : 1,
            ),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: TVTheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: TVTheme.primary, width: 1),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check, size: 12, color: TVTheme.primary),
                          SizedBox(width: 3),
                          Text(
                            'Active',
                            style: TextStyle(fontSize: 10, color: TVTheme.primary, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                s.filename ?? '${s.provider} Stream',
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

class _DrawerTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isSelected;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback onBack;

  const _DrawerTile({
    required this.title,
    this.subtitle,
    this.isSelected = false,
    this.autofocus = false,
    required this.onTap,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.backspace ||
              event.logicalKey == LogicalKeyboardKey.goBack) {
            onBack();
            return KeyEventResult.handled;
          }
        }
        return TvShortcuts.handleKeyEvent(event, onActivate: onTap);
      },
      child: Builder(
        builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: Duration.zero,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isFocused
                    ? Colors.white
                    : (isSelected ? TVTheme.primary.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isFocused
                      ? Colors.white
                      : (isSelected ? TVTheme.primary : Colors.transparent),
                  width: 1.5,
                ),
                boxShadow: isFocused ? TVTheme.focusShadows : [],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isFocused ? Colors.black : Colors.white,
                            fontWeight: isSelected || isFocused ? FontWeight.bold : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isFocused ? Colors.black54 : TVTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: isFocused ? Colors.black : TVTheme.primary,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SeasonPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onBack;

  const _SeasonPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.backspace ||
              event.logicalKey == LogicalKeyboardKey.goBack) {
            onBack();
            return KeyEventResult.handled;
          }
        }
        return TvShortcuts.handleKeyEvent(event, onActivate: onTap);
      },
      child: Builder(
        builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isFocused
                    ? Colors.white
                    : (isSelected ? TVTheme.primary : Colors.white12),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  color: isFocused ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
