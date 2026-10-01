import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/subtitle.model.dart';
import '../theme.dart';

class SubtitlePickerDialog extends StatelessWidget {
  final List<SubtitleTrackInfo> subtitles;
  final SubtitleTrackInfo? selectedSubtitle;
  final bool isLoading;

  const SubtitlePickerDialog({
    super.key,
    required this.subtitles,
    this.selectedSubtitle,
    this.isLoading = false,
  });

  static Future<SubtitleTrackInfo?> show({
    required BuildContext context,
    required List<SubtitleTrackInfo> subtitles,
    SubtitleTrackInfo? selectedSubtitle,
    bool isLoading = false,
  }) {
    return showGeneralDialog<SubtitleTrackInfo?>(
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
  Widget build(BuildContext context) {
    final isOffSelected = selectedSubtitle == null;
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
            width: (size.width * 0.35).clamp(320.0, 420.0),
            height: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xE0181818),
              border: const Border(
                left: BorderSide(color: Colors.white12, width: 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
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
                        if (isLoading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: TVTheme.accent, strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 12),
                    // Content
                    Expanded(
                      child: isLoading && subtitles.isEmpty
                          ? const Center(
                              child: Text(
                                'Searching subtitle tracks...',
                                style: TextStyle(color: Colors.white60, fontSize: 14),
                              ),
                            )
                          : subtitles.isEmpty && !isLoading
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
                                      onSelected: () => Navigator.pop(context, null),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8.0),
                                      child: Divider(color: Colors.white10, height: 1),
                                    ),
                                    ...subtitles.map((sub) {
                                      final isSelected = selectedSubtitle?.url == sub.url;
                                      return _SubtitleOptionTile(
                                        label: sub.label,
                                        isSelected: isSelected,
                                        autofocus: isSelected,
                                        onSelected: () => Navigator.pop(context, sub),
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
