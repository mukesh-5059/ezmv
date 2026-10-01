import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api_client.dart';
import '../theme.dart';

class SettingsDialog extends StatefulWidget {
  final VoidCallback onSaved;

  const SettingsDialog({
    super.key,
    required this.onSaved,
  });

  static Future<void> show({
    required BuildContext context,
    required VoidCallback onSaved,
  }) {
    return showDialog(
      context: context,
      builder: (context) => SettingsDialog(onSaved: onSaved),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final TextEditingController _ipController = TextEditingController();
  final FocusNode _saveFocusNode = FocusNode();
  final FocusNode _cancelFocusNode = FocusNode();
  late final FocusNode _textFieldFocusNode;

  @override
  void initState() {
    super.initState();
    _ipController.text = ApiClient.displayBaseUrl;
    _textFieldFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _saveFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _textFieldFocusNode.dispose();
    _saveFocusNode.dispose();
    _cancelFocusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final input = _ipController.text.trim();
    if (input.isNotEmpty) {
      await ApiClient.setBaseUrl(input);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Server endpoint saved: ${ApiClient.baseUrl}'),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 2),
          ),
        );
        widget.onSaved();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: TVTheme.surface,
      title: const Text('Backend API Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Specify the server IP and port where the FastAPI python server is running.',
            style: TextStyle(color: TVTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            focusNode: _textFieldFocusNode,
            autofocus: true,
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'Server IP / Port / URL',
              hintText: 'e.g., 192.168.29.50:8080',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (val) {
              Future.delayed(const Duration(milliseconds: 150), () {
                if (_saveFocusNode.canRequestFocus) {
                  _saveFocusNode.requestFocus();
                }
              });
            },
          ),
        ],
      ),
      actions: [
        Focus(
          focusNode: _cancelFocusNode,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                _textFieldFocusNode.requestFocus();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _saveFocusNode.requestFocus();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
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
              return TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: focused ? Colors.white.withOpacity(0.15) : Colors.transparent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              );
            },
          ),
        ),
        Focus(
          focusNode: _saveFocusNode,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                _textFieldFocusNode.requestFocus();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _cancelFocusNode.requestFocus();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space) {
                _save();
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
                  backgroundColor: focused ? Colors.white : TVTheme.accent,
                  foregroundColor: focused ? Colors.black : Colors.white,
                ),
                onPressed: _save,
                child: const Text('Save Settings'),
              );
            },
          ),
        ),
      ],
    );
  }
}
