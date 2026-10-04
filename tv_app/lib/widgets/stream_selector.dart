import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

class StreamSelector extends StatelessWidget {
  final List<Map<String, dynamic>> streams;
  final bool isLoading;
  final String statusMessage;
  final int cacheExpiresIn;
  final VoidCallback onRetry;
  final VoidCallback onForceRescrape;
  final void Function(Map<String, dynamic> stream) onStreamSelected;
  final FocusNode firstStreamFocusNode;
  final FocusNode retryFocusNode;
  final VoidCallback? onSectionFocused;

  const StreamSelector({
    super.key,
    required this.streams,
    required this.isLoading,
    required this.statusMessage,
    required this.cacheExpiresIn,
    required this.onRetry,
    required this.onForceRescrape,
    required this.onStreamSelected,
    required this.firstStreamFocusNode,
    required this.retryFocusNode,
    this.onSectionFocused,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Available Streams',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (!isLoading)
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                          event.logicalKey == LogicalKeyboardKey.space)) {
                    onForceRescrape();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return InkWell(
                      onTap: onForceRescrape,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: focused ? TVTheme.accent : Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: focused ? Colors.white : Colors.white24,
                            width: 1.5,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh, size: 16, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'Rescrape All',
                              style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: TVTheme.accent, strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    statusMessage,
                    style: const TextStyle(color: TVTheme.textSecondary, fontSize: 14),
                  ),
                ),
              ],
            ),
          )
        else if (streams.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No streams found or failed to connect. Verify your backend server is online.',
                style: TextStyle(color: TVTheme.accent, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Focus(
                focusNode: retryFocusNode,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                          event.logicalKey == LogicalKeyboardKey.space)) {
                    onRetry();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: focused ? Colors.white : TVTheme.surface,
                        foregroundColor: focused ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry Fetching'),
                    );
                  },
                ),
              ),
            ],
          )
        else
          SizedBox(
            height: 54,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: streams.length,
              itemBuilder: (context, index) {
                final stream = streams[index];
                return _StreamItemButton(
                  key: ValueKey(stream['url'] ?? index),
                  stream: stream,
                  focusNode: index == 0 ? firstStreamFocusNode : null,
                  onSelect: () => onStreamSelected(stream),
                  onFocused: onSectionFocused,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _StreamItemButton extends StatefulWidget {
  final Map<String, dynamic> stream;
  final FocusNode? focusNode;
  final VoidCallback onSelect;
  final VoidCallback? onFocused;

  const _StreamItemButton({
    super.key,
    required this.stream,
    this.focusNode,
    required this.onSelect,
    this.onFocused,
  });

  @override
  State<_StreamItemButton> createState() => _StreamItemButtonState();
}

class _StreamItemButtonState extends State<_StreamItemButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final stream = widget.stream;
    final String provider = stream['provider']?.toString() ?? 'Direct';
    final String quality = stream['quality']?.toString() ?? 'HD';

    final num? expiresAt = (stream['expires_at'] as num?);
    final num totalTtl = (stream['ttl'] as num?) ?? 86400;
    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    double fillProgress = 0.0;
    bool isExpired = false;

    if (expiresAt != null && totalTtl > 0) {
      final remaining = expiresAt - nowSec;
      if (remaining <= 0) {
        isExpired = true;
        fillProgress = 1.0;
      } else {
        fillProgress = (1.0 - (remaining / totalTtl)).clamp(0.0, 1.0);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(right: 14.0),
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) {
          setState(() => _isFocused = focused);
          if (focused) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
            );
            widget.onFocused?.call();
          }
        },
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: () {
            widget.onSelect();
          },
          child: AnimatedScale(
            scale: _isFocused ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: Container(
              width: 170,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: _isFocused
                    ? [
                        BoxShadow(
                          color: (isExpired ? Colors.redAccent : TVTheme.accent).withOpacity(0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        )
                      ]
                    : [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    // Base background
                    Positioned.fill(
                      child: Container(
                        color: _isFocused ? const Color(0xFF2A2A2A) : TVTheme.surface,
                      ),
                    ),
                    // TTL Fill Bar (filling slowly from left to right)
                    if (fillProgress > 0)
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: fillProgress,
                          child: Container(
                            color: isExpired
                                ? Colors.red.withOpacity(0.35)
                                : TVTheme.accent.withOpacity(0.18),
                          ),
                        ),
                      ),
                    // Bottom Accent Line Indicator
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 3.5,
                      child: Container(
                        color: Colors.white10,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: fillProgress > 0 ? fillProgress : 0.0,
                          child: Container(
                            color: isExpired ? Colors.redAccent : TVTheme.accent,
                          ),
                        ),
                      ),
                    ),
                    // Border Highlight on Focus
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isFocused
                                ? Colors.white
                                : (isExpired ? Colors.redAccent.withOpacity(0.5) : Colors.white12),
                            width: _isFocused ? 2.0 : 1.0,
                          ),
                        ),
                      ),
                    ),
                    // Content Label
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isExpired ? Icons.refresh : Icons.play_arrow_rounded,
                              size: 18,
                              color: isExpired ? Colors.redAccent : (_isFocused ? Colors.white : Colors.white70),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '$provider • $quality',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: _isFocused ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (isExpired) ...[
                              const SizedBox(width: 4),
                              const Text(
                                '↺',
                                style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
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
