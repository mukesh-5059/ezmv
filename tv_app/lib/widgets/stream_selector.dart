import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import 'tv_shortcuts.dart';

class StreamSelector extends StatelessWidget {
  final List<StreamSource> streams;
  final bool isLoading;
  final String statusMessage;
  final VoidCallback onRetry;
  final ValueChanged<StreamSource> onStreamSelected;
  final FocusNode? firstStreamFocusNode;
  final FocusNode? retryFocusNode;
  final VoidCallback? onSectionFocused;

  const StreamSelector({
    super.key,
    required this.streams,
    required this.isLoading,
    required this.statusMessage,
    required this.onRetry,
    required this.onStreamSelected,
    this.firstStreamFocusNode,
    this.retryFocusNode,
    this.onSectionFocused,
  });

  /// Modal dialog for manual stream selection (quality, audio, provider)
  static Future<StreamSource?> showModal({
    required BuildContext context,
    required List<StreamSource> streams,
    required String title,
  }) {
    return showDialog<StreamSource>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) {
        return _StreamSelectorDialog(
          title: title,
          streams: streams,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Available Streams',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
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
                  child: CircularProgressIndicator(color: TVTheme.primary, strokeWidth: 2),
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
                'No streams found or failed to connect to backend server.',
                style: TextStyle(color: TVTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Focus(
                focusNode: retryFocusNode,
                onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(event, onActivate: onRetry),
                child: Builder(
                  builder: (ctx) {
                    final focused = Focus.of(ctx).hasFocus;
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
            height: 56,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: streams.length,
              itemBuilder: (context, index) {
                final stream = streams[index];
                return _StreamItemButton(
                  key: ValueKey(stream.url),
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
  final StreamSource stream;
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
    final provider = stream.provider.isNotEmpty ? stream.provider : 'Direct';
    final quality = stream.quality.isNotEmpty ? stream.quality : 'HD';
    final size = stream.formattedSize != null && stream.formattedSize!.isNotEmpty
        ? ' • ${stream.formattedSize}'
        : '';

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
        onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(
          event,
          onActivate: widget.onSelect,
        ),
        child: GestureDetector(
          onTap: widget.onSelect,
          child: AnimatedScale(
            scale: _isFocused ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _isFocused ? TVTheme.surfaceElevated : TVTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isFocused ? Colors.white : Colors.white12,
                  width: _isFocused ? 2.0 : 1.0,
                ),
                boxShadow: _isFocused ? TVTheme.focusShadows : TVTheme.restingShadows,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 20,
                    color: _isFocused ? TVTheme.primary : Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$provider • $quality$size',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: _isFocused ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StreamSelectorDialog extends StatefulWidget {
  final String title;
  final List<StreamSource> streams;

  const _StreamSelectorDialog({
    required this.title,
    required this.streams,
  });

  @override
  State<_StreamSelectorDialog> createState() => _StreamSelectorDialogState();
}

class _StreamSelectorDialogState extends State<_StreamSelectorDialog> {
  final FocusNode _firstItemFocus = FocusNode();

  @override
  void dispose() {
    _firstItemFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: TVTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: TVTheme.borderRadiusMd),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 520),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, color: TVTheme.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Select Stream: ${widget.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Select preferred quality, audio language, or source provider:',
              style: TextStyle(fontSize: 13, color: TVTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: widget.streams.isEmpty
                  ? const Center(
                      child: Text(
                        'No streams available.',
                        style: TextStyle(color: TVTheme.textMuted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: widget.streams.length,
                      itemBuilder: (ctx, idx) {
                        final s = widget.streams[idx];
                        return _DialogStreamRow(
                          stream: s,
                          autofocus: idx == 0,
                          focusNode: idx == 0 ? _firstItemFocus : null,
                          onSelect: () => Navigator.of(context).pop(s),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogStreamRow extends StatefulWidget {
  final StreamSource stream;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback onSelect;

  const _DialogStreamRow({
    required this.stream,
    required this.autofocus,
    this.focusNode,
    required this.onSelect,
  });

  @override
  State<_DialogStreamRow> createState() => _DialogStreamRowState();
}

class _DialogStreamRowState extends State<_DialogStreamRow> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stream;
    final langs = s.languages.isNotEmpty ? s.languages.join(', ') : 'Default';

    return Focus(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(event, onActivate: widget.onSelect),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isFocused ? TVTheme.primary.withValues(alpha: 0.25) : TVTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: TVTheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  s.quality,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.filename ?? '${s.provider} Stream',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Provider: ${s.provider}  •  Audio: $langs${s.formattedSize != null ? "  •  Size: ${s.formattedSize}" : ""}',
                      style: const TextStyle(fontSize: 12, color: TVTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.chevron_right,
                color: _isFocused ? Colors.white : Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
