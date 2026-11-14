import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import 'tv_shortcuts.dart';

class SearchInputDialog extends StatefulWidget {
  final String initialQuery;
  final ValueChanged<String> onSearch;

  const SearchInputDialog({
    super.key,
    this.initialQuery = '',
    required this.onSearch,
  });

  static Future<String?> show({
    required BuildContext context,
    String initialQuery = '',
    required ValueChanged<String> onSearch,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => SearchInputDialog(
        initialQuery: initialQuery,
        onSearch: onSearch,
      ),
    );
  }

  @override
  State<SearchInputDialog> createState() => _SearchInputDialogState();
}

class _SearchInputDialogState extends State<SearchInputDialog> {
  late final TextEditingController _controller;
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _cancelFocusNode = FocusNode();
  late final FocusNode _textFieldFocusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _textFieldFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _searchFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _textFieldFocusNode.dispose();
    _searchFocusNode.dispose();
    _cancelFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final query = _controller.text.trim();
    Navigator.pop(context, query);
    widget.onSearch(query);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: TVTheme.surface,
      title: const Text('Search Titles & People'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter title, actor name, or keywords to search the catalog.',
            style: TextStyle(color: TVTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            focusNode: _textFieldFocusNode,
            autofocus: true,
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Search Query',
              hintText: 'e.g. Inception, Marvel, Rajinikanth...',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
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
                _searchFocusNode.requestFocus();
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
          focusNode: _searchFocusNode,
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
                _submit();
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
                onPressed: _submit,
                child: const Text('Search'),
              );
            },
          ),
        ),
      ],
    );
  }
}
