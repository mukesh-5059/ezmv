import 'package:flutter/material.dart';
import '../theme.dart';

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
      backgroundColor: MobileTheme.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.history_rounded, color: MobileTheme.accent),
          SizedBox(width: 10),
          Text('Resume Playback', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Text(
        'You were watching at ${formatDuration(savedSeconds)}. Would you like to resume from where you left off?',
        style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Start Over', style: TextStyle(color: Colors.white60)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: MobileTheme.accent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Resume', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
