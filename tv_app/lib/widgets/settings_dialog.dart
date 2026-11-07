import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import 'tv_shortcuts.dart';

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
    _ipController.text = ApiClient.instance.baseUrl;
    _textFieldFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _cancelFocusNode.requestFocus();
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
    var input = _ipController.text.trim();
    if (input.isNotEmpty) {
      if (!input.startsWith('http://') && !input.startsWith('https://')) {
        input = input.contains(':') && !input.contains('.') ? 'http://$input' : 'https://$input';
      }
      ApiClient.instance = ApiClient(baseUrl: input);
      await StorageService.instance.setApiBaseUrl(input);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Server endpoint saved: ${ApiClient.instance.baseUrl}'),
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
            'Specify the server IP and port where the EzMV backend is running.',
            style: TextStyle(color: TVTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            focusNode: _textFieldFocusNode,
            autofocus: true,
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'e.g. http://192.168.1.100:8787',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              if (mounted && _saveFocusNode.canRequestFocus) {
                _saveFocusNode.requestFocus();
              }
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
              if (TvShortcuts.isActivateKey(event.logicalKey)) {
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
                  backgroundColor: focused ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
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
              if (TvShortcuts.isActivateKey(event.logicalKey)) {
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
                  backgroundColor: focused ? Colors.white : TVTheme.primary,
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
