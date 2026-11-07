import 'package:flutter/material.dart';
import '../theme.dart';
import 'tv_shortcuts.dart';

/// Standard 10-Foot Focusable Action Button for Android TV.
///
/// Supports primary CTA ("Play Now", "Watch Trailer") and secondary actions
/// ("Show All", modal options). Elevates with a 1.06x scale transform,
/// high-contrast 3dp white outline, and ambient glow halo when focused.
class TvFocusButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isPrimary;
  final Color? color;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scale;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double fontSize;
  final ValueChanged<bool>? onFocusChanged;

  const TvFocusButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isPrimary = true,
    this.color,
    this.focusNode,
    this.autofocus = false,
    this.scale = TVTheme.buttonFocusScale,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    this.borderRadius = TVTheme.radiusMd,
    this.fontSize = 16,
    this.onFocusChanged,
  });

  @override
  State<TvFocusButton> createState() => _TvFocusButtonState();
}

class _TvFocusButtonState extends State<TvFocusButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.color ??
        (widget.isPrimary
            ? TVTheme.primary
            : (_isFocused ? TVTheme.surfaceElevated : TVTheme.surfaceElevated.withValues(alpha: 0.75)));

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
        widget.onFocusChanged?.call(focused);
      },
      onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(
        event,
        onActivate: widget.onPressed,
      ),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isFocused ? widget.scale : 1.0,
          duration: TVTheme.focusDuration,
          curve: TVTheme.focusCurve,
          child: AnimatedContainer(
            duration: TVTheme.focusDuration,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _isFocused ? Colors.white : Colors.transparent,
                width: TVTheme.focusBorderWidth,
              ),
              boxShadow: _isFocused
                  ? [
                      ...TVTheme.focusShadows,
                      if (widget.isPrimary)
                        BoxShadow(
                          color: TVTheme.accentGlow.withValues(alpha: 0.4),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                    ]
                  : TVTheme.restingShadows,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: widget.fontSize + 2,
                    color: _isFocused
                        ? Colors.white
                        : (widget.isPrimary ? Colors.white : TVTheme.textSecondary),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.w600,
                    color: _isFocused
                        ? Colors.white
                        : (widget.isPrimary ? Colors.white : TVTheme.textSecondary),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
