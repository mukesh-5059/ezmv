import 'dart:async';
import 'package:flutter/material.dart';

enum HudAction {
  play,
  pause,
  seekForward,
  seekBackward,
  subtitleChanged,
  info,
}

String formatSeekDelta(int totalSeconds) {
  final isPositive = totalSeconds >= 0;
  final absSec = totalSeconds.abs();
  final sign = isPositive ? '+' : '-';

  final hours = absSec ~/ 3600;
  final mins = (absSec % 3600) ~/ 60;
  final secs = absSec % 60;

  if (hours > 0) {
    return '$sign$hours:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  } else {
    return '$sign$mins:${secs.toString().padLeft(2, '0')}';
  }
}

class PlayerHud extends StatefulWidget {
  final PlayerHudController controller;

  const PlayerHud({
    super.key,
    required this.controller,
  });

  @override
  State<PlayerHud> createState() => _PlayerHudState();
}

class PlayerHudController extends ChangeNotifier {
  HudAction? currentAction;
  String? message;
  int seekDelta = 0;
  String? targetTimeStr;
  Timer? _dismissTimer;

  void triggerPlay() {
    currentAction = HudAction.play;
    message = null;
    _scheduleDismiss();
    notifyListeners();
  }

  void triggerPause() {
    currentAction = HudAction.pause;
    message = null;
    _scheduleDismiss();
    notifyListeners();
  }

  void triggerSeek({required int deltaSeconds, required String targetTime}) {
    seekDelta = deltaSeconds;
    currentAction = seekDelta >= 0 ? HudAction.seekForward : HudAction.seekBackward;
    targetTimeStr = targetTime;
    _scheduleDismiss(durationMs: 1200);
    notifyListeners();
  }

  void triggerSubtitle(String subtitleLabel) {
    currentAction = HudAction.subtitleChanged;
    message = subtitleLabel;
    _scheduleDismiss(durationMs: 1500);
    notifyListeners();
  }

  void triggerInfo(String infoText, {int durationMs = 1800}) {
    currentAction = HudAction.info;
    message = infoText;
    _scheduleDismiss(durationMs: durationMs);
    notifyListeners();
  }

  void _scheduleDismiss({int durationMs = 800}) {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(Duration(milliseconds: durationMs), () {
      currentAction = null;
      message = null;
      seekDelta = 0;
      targetTimeStr = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }
}

class _PlayerHudState extends State<PlayerHud> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.controller.currentAction;
    if (action == null) return const SizedBox.shrink();

    Widget content;
    switch (action) {
      case HudAction.play:
        content = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.play_arrow, color: Colors.white, size: 56),
        );
        break;
      case HudAction.pause:
        content = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.pause, color: Colors.white, size: 56),
        );
        break;
      case HudAction.seekForward:
      case HudAction.seekBackward:
        final isForward = widget.controller.seekDelta >= 0;
        content = Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isForward ? Icons.fast_forward : Icons.fast_rewind,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 12),
              Text(
                formatSeekDelta(widget.controller.seekDelta),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (widget.controller.targetTimeStr != null) ...[
                const SizedBox(width: 12),
                Text(
                  '(${widget.controller.targetTimeStr})',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ],
          ),
        );
        break;
      case HudAction.subtitleChanged:
        content = Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.subtitles, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              Text(
                widget.controller.message ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
        break;
      case HudAction.info:
        content = Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white30, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_circle_outline_rounded, color: Colors.white, size: 26),
              const SizedBox(width: 12),
              Text(
                widget.controller.message ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
        break;
    }

    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 150),
          child: content,
        ),
      ),
    );
  }
}
