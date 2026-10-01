import 'package:flutter/material.dart';
import '../theme.dart';
import 'focusable_button.dart';

class ResumeDialog extends StatelessWidget {
  final int savedSeconds;
  final String Function(int seconds) formatDuration;

  const ResumeDialog({
    super.key,
    required this.savedSeconds,
    required this.formatDuration,
  });

  static Future<bool?> show({
    required BuildContext context,
    required int savedSeconds,
    required String Function(int seconds) formatDuration,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ResumeDialog(
        savedSeconds: savedSeconds,
        formatDuration: formatDuration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Resume Playback?', style: TextStyle(color: Colors.white)),
      content: Text(
        'Would you like to resume watching from ${formatDuration(savedSeconds)}?',
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        FocusableButton(
          label: 'Start Over',
          color: Colors.redAccent.withOpacity(0.3),
          focusedBorderColor: Colors.redAccent,
          onPressed: () => Navigator.pop(context, false),
        ),
        const SizedBox(width: 8),
        FocusableButton(
          label: 'Resume',
          color: TVTheme.accent,
          autofocus: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}
