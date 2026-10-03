import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/subtitle.model.dart';
import '../theme.dart';

class SubtitlePickerResult {
  final bool isOff;
  final SubtitleTrackInfo? track;

  const SubtitlePickerResult._({this.isOff = false, this.track});

  factory SubtitlePickerResult.off() => const SubtitlePickerResult._(isOff: true);
  factory SubtitlePickerResult.selected(SubtitleTrackInfo track) => SubtitlePickerResult._(track: track);
}

class SubtitlePickerDialog extends StatefulWidget {
  final List<SubtitleTrackInfo> subtitles;
  final SubtitleTrackInfo? selectedSubtitle;
  final bool isLoading;
  final double initialFontSize;
  final double initialDelaySeconds;
  final ValueChanged<double>? onFontSizeChanged;
  final ValueChanged<double>? onDelayChanged;

  const SubtitlePickerDialog({
    super.key,
    required this.subtitles,
    this.selectedSubtitle,
    this.isLoading = false,
    this.initialFontSize = 44.0,
    this.initialDelaySeconds = 0.0,
    this.onFontSizeChanged,
    this.onDelayChanged,
  });

  static Future<SubtitlePickerResult?> show({
    required BuildContext context,
    required List<SubtitleTrackInfo> subtitles,
    SubtitleTrackInfo? selectedSubtitle,
    bool isLoading = false,
    double initialFontSize = 44.0,
    double initialDelaySeconds = 0.0,
    ValueChanged<double>? onFontSizeChanged,
    ValueChanged<double>? onDelayChanged,
  }) {
    return showGeneralDialog<SubtitlePickerResult?>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss Subtitles',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: SubtitlePickerDialog(
            subtitles: subtitles,
            selectedSubtitle: selectedSubtitle,
            isLoading: isLoading,
            initialFontSize: initialFontSize,
            initialDelaySeconds: initialDelaySeconds,
            onFontSizeChanged: onFontSizeChanged,
            onDelayChanged: onDelayChanged,
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

  @override
  State<SubtitlePickerDialog> createState() => _SubtitlePickerDialogState();
}

class _SubtitlePickerDialogState extends State<SubtitlePickerDialog> {
  late double _fontSize;
  late double _delay;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.initialFontSize;
    _delay = widget.initialDelaySeconds;
  }

  void _adjustFontSize(double delta) {
    final newSize = (_fontSize + delta).clamp(28.0, 68.0);
    setState(() => _fontSize = newSize);
    widget.onFontSizeChanged?.call(newSize);
  }

  void _adjustDelay(double delta) {
    final newDelay = double.parse((_delay + delta).toStringAsFixed(1));
    setState(() => _delay = newDelay);
    widget.onDelayChanged?.call(newDelay);
  }

  void _resetDelay() {
    setState(() => _delay = 0.0);
    widget.onDelayChanged?.call(0.0);
  }

  @override
  Widget build(BuildContext context) {
    final isOffSelected = widget.selectedSubtitle == null;
    final size = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          bottomLeft: Radius.circular(16),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: (size.width * 0.35).clamp(340.0, 440.0),
            height: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xE0181818),
              border: const Border(
                left: BorderSide(color: Colors.white12, width: 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        const Icon(Icons.subtitles_rounded, color: TVTheme.accent, size: 24),
                        const SizedBox(width: 12),
                        const Text(
                          'Subtitles',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (widget.isLoading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: TVTheme.accent, strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Subtitle Adjustments Card (Size & Sync)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Size Row
                          Row(
                            children: [
                              const Icon(Icons.format_size_rounded, color: Colors.white70, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Size',
                                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              const Spacer(),
                              _MiniStepperButton(
                                label: '−',
                                onPressed: () => _adjustFontSize(-4.0),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                                child: Text(
                                  '${_fontSize.toInt()}px',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              _MiniStepperButton(
                                label: '+',
                                onPressed: () => _adjustFontSize(4.0),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Sync Delay Row
                          Row(
                            children: [
                              const Icon(Icons.av_timer_rounded, color: Colors.white70, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Sync',
                                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              const Spacer(),
                              _MiniStepperButton(
                                label: '−0.5s',
                                onPressed: () => _adjustDelay(-0.5),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text(
                                  '${_delay > 0 ? '+' : ''}${_delay.toStringAsFixed(1)}s',
                                  style: TextStyle(
                                    color: _delay != 0.0 ? TVTheme.accent : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              _MiniStepperButton(
                                label: '+0.5s',
                                onPressed: () => _adjustDelay(0.5),
                              ),
                              if (_delay != 0.0) ...[
                                const SizedBox(width: 6),
                                _MiniStepperButton(
                                  label: '↺',
                                  onPressed: _resetDelay,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text(
                      'TRACKS',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Content
                    Expanded(
                      child: widget.isLoading && widget.subtitles.isEmpty
                          ? const Center(
                              child: Text(
                                'Searching subtitle tracks...',
                                style: TextStyle(color: Colors.white60, fontSize: 14),
                              ),
                            )
                          : widget.subtitles.isEmpty && !widget.isLoading
                              ? const Center(
                                  child: Text(
                                    'No subtitles found for this title.',
                                    style: TextStyle(color: Colors.white60, fontSize: 14),
                                  ),
                                )
                              : ListView(
                                  children: [
                                    _SubtitleOptionTile(
                                      label: 'Off (Disabled)',
                                      isSelected: isOffSelected,
                                      autofocus: isOffSelected,
                                      onSelected: () => Navigator.pop(context, SubtitlePickerResult.off()),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8.0),
                                      child: Divider(color: Colors.white10, height: 1),
                                    ),
                                    ...widget.subtitles.map((sub) {
                                      final isSelected = widget.selectedSubtitle?.url == sub.url;
                                      return _SubtitleOptionTile(
                                        label: sub.label,
                                        isSelected: isSelected,
                                        autofocus: isSelected,
                                        onSelected: () => Navigator.pop(context, SubtitlePickerResult.selected(sub)),
                                      );
                                    }),
                                  ],
                                ),
                    ),
                    const SizedBox(height: 12),
                    // Back / Close Prompt
                    const Center(
                      child: Text(
                        'Press Back to close',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniStepperButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _MiniStepperButton({
    required this.label,
    required this.onPressed,
  });

  @override
  State<_MiniStepperButton> createState() => _MiniStepperButtonState();
}

class _MiniStepperButtonState extends State<_MiniStepperButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: _isFocused ? TVTheme.accent : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.white24,
              width: 1.5,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: TVTheme.accent.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _isFocused ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _SubtitleOptionTile extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool autofocus;
  final VoidCallback onSelected;

  const _SubtitleOptionTile({
    required this.label,
    required this.isSelected,
    this.autofocus = false,
    required this.onSelected,
  });

  @override
  State<_SubtitleOptionTile> createState() => _SubtitleOptionTileState();
}

class _SubtitleOptionTileState extends State<_SubtitleOptionTile> {
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
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onSelected();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isFocused
                ? TVTheme.accent
                : widget.isSelected
                    ? Colors.white10
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.transparent,
              width: 2,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: TVTheme.accent.withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Icon(
                widget.isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: _isFocused
                    ? Colors.white
                    : widget.isSelected
                        ? TVTheme.accent
                        : Colors.white38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
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
