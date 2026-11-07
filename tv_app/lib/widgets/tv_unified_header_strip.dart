import 'package:flutter/material.dart';
import '../theme.dart';
import 'tv_shortcuts.dart';

/// Full-width focusable lane header strip for 10-foot TV navigation.
///
/// Displays:
/// - Left: Lane Title (`Title Large` 20sp bold).
/// - Right: Focusable "Show All (N) ›" action.
///
/// When focused via remote D-pad, the strip lights up with a subtle focus glow,
/// raises with dual-layer shadows, and responds to `Select/OK` by triggering [onShowAll].
class TvUnifiedHeaderStrip extends StatefulWidget {
  final String title;
  final int? count;
  final VoidCallback? onShowAll;
  final FocusNode? focusNode;
  final bool autofocus;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const TvUnifiedHeaderStrip({
    super.key,
    required this.title,
    this.count,
    this.onShowAll,
    this.focusNode,
    this.autofocus = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.margin = const EdgeInsets.only(bottom: 6),
  });

  @override
  State<TvUnifiedHeaderStrip> createState() => _TvUnifiedHeaderStripState();
}

class _TvUnifiedHeaderStripState extends State<TvUnifiedHeaderStrip> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final hasAction = widget.onShowAll != null;
    final showAllLabel = widget.count != null
        ? 'Show All (${widget.count})'
        : 'Show All';

    final content = AnimatedContainer(
      duration: TVTheme.focusDuration,
      curve: TVTheme.focusCurve,
      margin: widget.margin,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: _isFocused
            ? TVTheme.surfaceElevated
            : Colors.transparent,
        borderRadius: TVTheme.borderRadiusMd,
        border: Border.all(
          color: _isFocused ? Colors.white : Colors.transparent,
          width: TVTheme.focusBorderWidth,
        ),
        boxShadow: _isFocused ? TVTheme.focusShadows : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Lane Title
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: TVTheme.textPrimary,
              letterSpacing: 0.2,
            ),
          ),

          // Right: "Show All (N) ›"
          if (hasAction)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  showAllLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: _isFocused ? FontWeight.w700 : FontWeight.w500,
                    color: _isFocused ? TVTheme.textPrimary : TVTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: _isFocused ? TVTheme.primary : TVTheme.textSecondary,
                ),
              ],
            ),
        ],
      ),
    );

    if (!hasAction) return content;

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: TVTheme.focusDuration,
            curve: Curves.easeInOut,
          );
        }
      },
      onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(
        event,
        onActivate: () => widget.onShowAll?.call(),
      ),
      child: GestureDetector(
        onTap: widget.onShowAll,
        child: AnimatedScale(
          scale: _isFocused ? 1.02 : 1.0,
          duration: TVTheme.focusDuration,
          curve: TVTheme.focusCurve,
          child: content,
        ),
      ),
    );
  }
}
