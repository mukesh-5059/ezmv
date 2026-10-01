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
            if (cacheExpiresIn > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Text(
                  'Cache expires in: ${cacheExpiresIn}s',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            if (!isLoading)
              Focus(
                onKey: (node, event) {
                  if (event is RawKeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.select ||
                        event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                        event.logicalKey == LogicalKeyboardKey.space) {
                      onForceRescrape();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      style: IconButton.styleFrom(
                        backgroundColor: focused ? Colors.red : Colors.white12,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(8),
                      ),
                      onPressed: onForceRescrape,
                      tooltip: 'Force re-scrape',
                    );
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (isLoading)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: TVTheme.accent, strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(statusMessage, style: const TextStyle(color: TVTheme.textSecondary)),
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
                onKey: (node, event) {
                  if (event is RawKeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.select ||
                        event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                        event.logicalKey == LogicalKeyboardKey.space) {
                      onRetry();
                      return KeyEventResult.handled;
                    }
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
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: streams.length,
              itemBuilder: (context, index) {
                final stream = streams[index];
                final String providerName = stream['provider']?.toString() ?? 'Direct';

                return Focus(
                  focusNode: index == 0 ? firstStreamFocusNode : null,
                  onKey: (node, event) {
                    if (event is RawKeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                          event.logicalKey == LogicalKeyboardKey.space) {
                        onStreamSelected(stream);
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      return Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: focused ? TVTheme.accent : TVTheme.surface,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: focused ? Colors.white : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          onPressed: () => onStreamSelected(stream),
                          child: Text(providerName),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
