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
    return showDialog<SubtitleTrackInfo?>(
      context: context,
      builder: (context) => SubtitlePickerDialog(
        subtitles: subtitles,
        selectedSubtitle: selectedSubtitle,
        isLoading: isLoading,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOffSelected = selectedSubtitle == null;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Row(
        children: [
          const Icon(Icons.subtitles, color: Colors.white, size: 24),
          const SizedBox(width: 10),
          const Text('Subtitles', style: TextStyle(color: Colors.white)),
          if (isLoading) ...[
            const Spacer(),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(color: TVTheme.accent, strokeWidth: 2),
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: 380,
        child: isLoading && subtitles.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(
                  child: Text('Loading subtitles...', style: TextStyle(color: Colors.white70)),
                ),
              )
            : subtitles.isEmpty && !isLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: Text('No subtitles available for this title.', style: TextStyle(color: Colors.white70)),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Option: Off
                        _SubtitleOptionTile(
                          label: 'Off',
                          isSelected: isOffSelected,
                          autofocus: isOffSelected,
                          onSelected: () => Navigator.pop(context, null),
                        ),
                        const Divider(color: Colors.white12),
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, selectedSubtitle),
          child: const Text('Close', style: TextStyle(color: Colors.white70)),
        ),
      ],
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
        child: Container(
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
          ),
          child: Row(
            children: [
              Icon(
                widget.isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
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
