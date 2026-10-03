import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

class SearchDialog extends StatefulWidget {
  final ValueChanged<String> onSearch;
  final void Function(String label, {int? year, int? genreId}) onDiscover;

  const SearchDialog({
    super.key,
    required this.onSearch,
    required this.onDiscover,
  });

  static Future<void> show({
    required BuildContext context,
    required ValueChanged<String> onSearch,
    required void Function(String label, {int? year, int? genreId}) onDiscover,
  }) {
    return showDialog(
      context: context,
      builder: (context) => SearchDialog(
        onSearch: onSearch,
        onDiscover: onDiscover,
      ),
    );
  }

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchButtonFocusNode = FocusNode();
  final FocusNode _cancelButtonFocusNode = FocusNode();
  late final FocusNode _textFieldFocusNode;

  @override
  void initState() {
    super.initState();
    _textFieldFocusNode = FocusNode(
      onKey: (node, event) {
        if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _searchButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _textFieldFocusNode.dispose();
    _searchButtonFocusNode.dispose();
    _cancelButtonFocusNode.dispose();
    super.dispose();
  }

  Widget _buildSearchTag(
    String label,
    VoidCallback onTap, {
    bool isLeftMost = false,
    FocusNode? leftFocusNode,
  }) {
    return Focus(
      onKey: (node, event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft && isLeftMost && leftFocusNode != null) {
            leftFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return ActionChip(
            label: Text(
              label,
              style: TextStyle(
                color: focused ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            backgroundColor: focused ? Colors.white : TVTheme.surface,
            side: BorderSide(color: focused ? Colors.white : Colors.white24, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onPressed: onTap,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: TVTheme.surface,
      title: const Text('Search Movies'),
      content: SizedBox(
        width: 750,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Type Movie Title',
                    style: TextStyle(color: TVTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    focusNode: _textFieldFocusNode,
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Enter title...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (val) {
                      Future.delayed(const Duration(milliseconds: 150), () {
                        if (mounted && _searchButtonFocusNode.canRequestFocus) {
                          _searchButtonFocusNode.requestFocus();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Focus(
                          focusNode: _cancelButtonFocusNode,
                          onKey: (node, event) {
                            if (event is RawKeyDownEvent) {
                              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                _textFieldFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                _searchButtonFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey == LogicalKeyboardKey.select ||
                                  event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey == LogicalKeyboardKey.numpadEnter ||
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
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Focus(
                          focusNode: _searchButtonFocusNode,
                          onKey: (node, event) {
                            if (event is RawKeyDownEvent) {
                              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                _textFieldFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                _cancelButtonFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey == LogicalKeyboardKey.select ||
                                  event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                  event.logicalKey == LogicalKeyboardKey.space) {
                                Navigator.pop(context);
                                widget.onSearch(_searchController.text);
                                return KeyEventResult.handled;
                              }
                            }
                            return KeyEventResult.ignored;
                          },
                          child: Builder(
                            builder: (context) {
                              final focused = Focus.of(context).hasFocus;
                              return ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  widget.onSearch(_searchController.text);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: focused ? Colors.white : TVTheme.accent,
                                  foregroundColor: focused ? Colors.black : Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text('Search'),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0),
              child: SizedBox(
                height: 280,
                child: VerticalDivider(color: Colors.grey, width: 1, thickness: 1),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 280,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quick Search Genres',
                        style: TextStyle(color: TVTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildSearchTag('Action', () {
                            Navigator.pop(context);
                            widget.onDiscover('Action', genreId: 28);
                          }, isLeftMost: true, leftFocusNode: _searchButtonFocusNode),
                          _buildSearchTag('Comedy', () {
                            Navigator.pop(context);
                            widget.onDiscover('Comedy', genreId: 35);
                          }),
                          _buildSearchTag('Thriller', () {
                            Navigator.pop(context);
                            widget.onDiscover('Thriller', genreId: 53);
                          }),
                          _buildSearchTag('Horror', () {
                            Navigator.pop(context);
                            widget.onDiscover('Horror', genreId: 27);
                          }),
                          _buildSearchTag('Sci-Fi', () {
                            Navigator.pop(context);
                            widget.onDiscover('Sci-Fi', genreId: 878);
                          }, isLeftMost: true, leftFocusNode: _searchButtonFocusNode),
                          _buildSearchTag('Romance', () {
                            Navigator.pop(context);
                            widget.onDiscover('Romance', genreId: 10749);
                          }),
                          _buildSearchTag('Animation', () {
                            Navigator.pop(context);
                            widget.onDiscover('Animation', genreId: 16);
                          }),
                          _buildSearchTag('Drama', () {
                            Navigator.pop(context);
                            widget.onDiscover('Drama', genreId: 18);
                          }, isLeftMost: true, leftFocusNode: _searchButtonFocusNode),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Quick Search Years',
                        style: TextStyle(color: TVTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildSearchTag('2026', () {
                            Navigator.pop(context);
                            widget.onDiscover('2026', year: 2026);
                          }, isLeftMost: true, leftFocusNode: _searchButtonFocusNode),
                          _buildSearchTag('2025', () {
                            Navigator.pop(context);
                            widget.onDiscover('2025', year: 2025);
                          }),
                          _buildSearchTag('2024', () {
                            Navigator.pop(context);
                            widget.onDiscover('2024', year: 2024);
                          }),
                          _buildSearchTag('2023', () {
                            Navigator.pop(context);
                            widget.onDiscover('2023', year: 2023);
                          }),
                          _buildSearchTag('2022', () {
                            Navigator.pop(context);
                            widget.onDiscover('2022', year: 2022);
                          }),
                          _buildSearchTag('2021', () {
                            Navigator.pop(context);
                            widget.onDiscover('2021', year: 2021);
                          }, isLeftMost: true, leftFocusNode: _searchButtonFocusNode),
                          _buildSearchTag('2020', () {
                            Navigator.pop(context);
                            widget.onDiscover('2020', year: 2020);
                          }),
                          _buildSearchTag('2019', () {
                            Navigator.pop(context);
                            widget.onDiscover('2019', year: 2019);
                          }),
                          _buildSearchTag('2018', () {
                            Navigator.pop(context);
                            widget.onDiscover('2018', year: 2018);
                          }),
                          _buildSearchTag('2015', () {
                            Navigator.pop(context);
                            widget.onDiscover('2015', year: 2015);
                          }),
                          _buildSearchTag('2010', () {
                            Navigator.pop(context);
                            widget.onDiscover('2010', year: 2010);
                          }, isLeftMost: true, leftFocusNode: _searchButtonFocusNode),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
