import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import 'tv_focus_button.dart';
import 'tv_shortcuts.dart';

class TvKeyboardDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final String hintText;
  final String acceptLabel;
  final bool isUrl;

  const TvKeyboardDialog({
    super.key,
    required this.title,
    this.initialValue = '',
    this.hintText = '',
    this.acceptLabel = 'Accept',
    this.isUrl = false,
  });

  static Future<String?> show({
    required BuildContext context,
    required String title,
    String initialValue = '',
    String hintText = '',
    String acceptLabel = 'Accept',
    bool isUrl = false,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => TvKeyboardDialog(
        title: title,
        initialValue: initialValue,
        hintText: hintText,
        acceptLabel: acceptLabel,
        isUrl: isUrl,
      ),
    );
  }

  @override
  State<TvKeyboardDialog> createState() => _TvKeyboardDialogState();
}

class _TvKeyboardDialogState extends State<TvKeyboardDialog> {
  late String _text;

  final List<String> _urlPresets = const [
    'https://',
    'http://',
    '.com',
    ':8000',
  ];

  final List<List<String>> _baseRows = const [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '/', ':', '.'],
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M', '_', '@'],
  ];

  late final List<FocusNode> _presetNodes = List.generate(
    _urlPresets.length,
    (_) => FocusNode(),
  );

  late final List<List<FocusNode>> _baseNodes = [
    List.generate(14, (_) => FocusNode()),
    List.generate(10, (_) => FocusNode()),
    List.generate(9, (_) => FocusNode()),
    List.generate(9, (_) => FocusNode()),
  ];

  late final List<FocusNode> _controlNodes = List.generate(3, (_) => FocusNode());

  final FocusNode _cancelFocus = FocusNode();
  final FocusNode _acceptFocus = FocusNode();

  late final FocusScopeNode _keyboardScopeNode = FocusScopeNode(
    debugLabel: 'KeyboardScope',
  )..directionalTraversalEdgeBehavior = TraversalEdgeBehavior.stop;

  @override
  void initState() {
    super.initState();
    _text = widget.initialValue;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.isUrl) {
        _presetNodes[0].requestFocus();
      } else {
        _baseNodes[0][0].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final node in _presetNodes) {
      node.dispose();
    }
    for (final row in _baseNodes) {
      for (final node in row) {
        node.dispose();
      }
    }
    for (final node in _controlNodes) {
      node.dispose();
    }
    _cancelFocus.dispose();
    _acceptFocus.dispose();
    _keyboardScopeNode.dispose();
    super.dispose();
  }

  void _append(String char) {
    setState(() => _text += char);
  }

  void _backspace() {
    if (_text.isNotEmpty) setState(() => _text = _text.substring(0, _text.length - 1));
  }

  void _clear() {
    setState(() => _text = '');
  }

  void _submit() {
    Navigator.of(context).pop(_text.trim());
  }

  void _cancel() {
    Navigator.of(context).pop(null);
  }

  KeyEventResult _handlePresetKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    if (event is KeyDownEvent && TvShortcuts.isActivateKey(event.logicalKey)) {
      _append(_urlPresets[index]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) _presetNodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (index < _urlPresets.length - 1) _presetNodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      const targetColumns = [1, 5, 8, 12];
      _baseNodes[0][targetColumns[index]].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleBaseKeyEvent(int r, int c, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    if (event is KeyDownEvent && TvShortcuts.isActivateKey(event.logicalKey)) {
      _append(_baseRows[r][c].toLowerCase());
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (c > 0) _baseNodes[r][c - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (c < _baseRows[r].length - 1) _baseNodes[r][c + 1].requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (r == 0) {
        if (widget.isUrl) {
          final pIdx = (c * 4 / 14).floor().clamp(0, 3);
          _presetNodes[pIdx].requestFocus();
        }
        return KeyEventResult.handled;
      } else if (r == 1) {
        final targetCol = (c * 14 / 10).round().clamp(0, 13);
        _baseNodes[0][targetCol].requestFocus();
        return KeyEventResult.handled;
      } else if (r == 2) {
        final targetCol = (c * 10 / 9).round().clamp(0, 9);
        _baseNodes[1][targetCol].requestFocus();
        return KeyEventResult.handled;
      } else if (r == 3) {
        _baseNodes[2][c].requestFocus();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (r == 0) {
        final targetCol = (c * 10 / 14).round().clamp(0, 9);
        _baseNodes[1][targetCol].requestFocus();
        return KeyEventResult.handled;
      } else if (r == 1) {
        final targetCol = (c * 9 / 10).round().clamp(0, 8);
        _baseNodes[2][targetCol].requestFocus();
        return KeyEventResult.handled;
      } else if (r == 2) {
        _baseNodes[3][c].requestFocus();
        return KeyEventResult.handled;
      } else if (r == 3) {
        if (c <= 4) {
          _controlNodes[0].requestFocus();
        } else if (c <= 6) {
          _controlNodes[1].requestFocus();
        } else {
          _controlNodes[2].requestFocus();
        }
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleControlKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    if (event is KeyDownEvent && TvShortcuts.isActivateKey(event.logicalKey)) {
      if (index == 0) _append(' ');
      if (index == 1) _backspace();
      if (index == 2) _clear();
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent && index == 1 && TvShortcuts.isActivateKey(event.logicalKey)) {
      _backspace();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) _controlNodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (index < 2) _controlNodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index == 0) _baseNodes[3][2].requestFocus();
      if (index == 1) _baseNodes[3][6].requestFocus();
      if (index == 2) _baseNodes[3][8].requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index == 0) {
        _cancelFocus.requestFocus();
      } else {
        _acceptFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleGlobalKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _cancel();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }

    final char = event.character;
    if (char != null &&
        char.isNotEmpty &&
        char.codeUnitAt(0) >= 32 &&
        !TvShortcuts.isActivateKey(event.logicalKey)) {
      _append(char);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _buildKeyButton({
    required String label,
    required VoidCallback onTap,
    required FocusNode focusNode,
    double flex = 1,
    IconData? icon,
    Color? activeColor,
    double height = 32,
    double fontSize = 13,
    KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent,
  }) {
    return Expanded(
      flex: (flex * 10).toInt(),
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Focus(
          focusNode: focusNode,
          onKeyEvent: (node, event) {
            if (onKeyEvent != null) {
              final res = onKeyEvent(node, event);
              if (res != KeyEventResult.ignored) return res;
            }
            if (event is KeyDownEvent && TvShortcuts.isActivateKey(event.logicalKey)) {
              onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return GestureDetector(
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: height,
                  decoration: BoxDecoration(
                    color: focused
                        ? (activeColor ?? Colors.white)
                        : TVTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: focused ? Colors.white : Colors.white10,
                      width: focused ? 2 : 1,
                    ),
                    boxShadow: focused ? TVTheme.focusShadows : null,
                  ),
                  child: Center(
                    child: icon != null
                        ? Icon(
                            icon,
                            size: 15,
                            color: focused ? Colors.black : Colors.white,
                          )
                        : Text(
                            label,
                            style: TextStyle(
                              color: focused ? Colors.black : Colors.white,
                              fontSize: label.length > 4 ? 11 : fontSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: FocusScope(
        node: _keyboardScopeNode,
        child: Focus(
          onKeyEvent: _handleGlobalKeyEvent,
          child: Dialog(
            backgroundColor: TVTheme.surface,
            insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TVTheme.radiusMd),
              side: const BorderSide(color: Colors.white12, width: 1.5),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (widget.hintText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.hintText,
                          style: const TextStyle(fontSize: 11, color: TVTheme.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _text.isEmpty ? (widget.hintText.isNotEmpty ? widget.hintText : 'Type here...') : _text,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontFamily: 'monospace',
                                  color: _text.isEmpty ? TVTheme.textMuted : Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_text.isNotEmpty)
                              GestureDetector(
                                onTap: _clear,
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Icon(Icons.cancel, color: TVTheme.textSecondary, size: 18),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (widget.isUrl) ...[
                        Row(
                          children: [
                            for (int i = 0; i < _urlPresets.length; i++)
                              _buildKeyButton(
                                label: _urlPresets[i],
                                flex: 1.2,
                                height: 26,
                                fontSize: 11,
                                focusNode: _presetNodes[i],
                                onTap: () => _append(_urlPresets[i]),
                                onKeyEvent: (node, event) => _handlePresetKeyEvent(i, event),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                      ],
                      for (int r = 0; r < _baseRows.length; r++)
                        Row(
                          children: [
                            for (int c = 0; c < _baseRows[r].length; c++)
                              _buildKeyButton(
                                label: _baseRows[r][c],
                                focusNode: _baseNodes[r][c],
                                onTap: () => _append(_baseRows[r][c].toLowerCase()),
                                onKeyEvent: (node, event) => _handleBaseKeyEvent(r, c, event),
                              ),
                          ],
                        ),
                      Row(
                        children: [
                          _buildKeyButton(
                            label: 'Space',
                            icon: Icons.space_bar,
                            flex: 3.5,
                            focusNode: _controlNodes[0],
                            onTap: () => _append(' '),
                            onKeyEvent: (node, event) => _handleControlKeyEvent(0, event),
                          ),
                          _buildKeyButton(
                            label: 'Backspace',
                            icon: Icons.backspace_outlined,
                            flex: 2.0,
                            focusNode: _controlNodes[1],
                            onTap: _backspace,
                            onKeyEvent: (node, event) => _handleControlKeyEvent(1, event),
                          ),
                          _buildKeyButton(
                            label: 'Clear',
                            icon: Icons.delete_sweep_outlined,
                            flex: 1.5,
                            focusNode: _controlNodes[2],
                            onTap: _clear,
                            onKeyEvent: (node, event) => _handleControlKeyEvent(2, event),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TvFocusButton(
                            label: 'Cancel',
                            icon: Icons.close,
                            isPrimary: false,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            fontSize: 13,
                            focusNode: _cancelFocus,
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                  _acceptFocus.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                  _controlNodes[0].requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                                    event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            onPressed: _cancel,
                          ),
                          const SizedBox(width: 12),
                          TvFocusButton(
                            label: widget.acceptLabel,
                            icon: Icons.check,
                            isPrimary: true,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            fontSize: 13,
                            focusNode: _acceptFocus,
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                  _cancelFocus.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                  _controlNodes[1].requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                                    event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
