import 'package:flutter/material.dart';
import '../theme.dart';
import 'tv_shortcuts.dart';

/// Pill-shaped filter chip for 10-foot TV navigation.
///
/// Features:
/// - Rounded pill geometry (radius 9999dp / `rounded.full`).
/// - Unfocused resting state: `#1C1D24` background with `#9E9EA7` text.
/// - Focused state: 1.08x scale transform, 3dp high-contrast white border, pure white text.
/// - Selected state: `#E50914` subtle accent indicator with leading checkmark.
class TvPillChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;
  final FocusNode? focusNode;
  final bool autofocus;
  final EdgeInsetsGeometry padding;
  final ValueChanged<bool>? onFocusChanged;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  const TvPillChip({
    super.key,
    required this.label,
    required this.onTap,
    this.isSelected = false,
    this.icon,
    this.focusNode,
    this.autofocus = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.onFocusChanged,
    this.onKeyEvent,
  });

  @override
  State<TvPillChip> createState() => _TvPillChipState();
}

class _TvPillChipState extends State<TvPillChip> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Border border;
    List<BoxShadow>? shadows;

    if (_isFocused) {
      backgroundColor = widget.isSelected
          ? TVTheme.primary.withValues(alpha: 0.25)
          : TVTheme.surfaceElevated;
      border = Border.all(
        color: Colors.white,
        width: TVTheme.focusBorderWidth,
      );
      shadows = [
        ...TVTheme.focusShadows,
        if (widget.isSelected)
          BoxShadow(
            color: TVTheme.accentGlow.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 1,
          ),
      ];
    } else if (widget.isSelected) {
      backgroundColor = TVTheme.surfaceElevated;
      border = Border.all(
        color: TVTheme.primary.withValues(alpha: 0.75),
        width: 1.5,
      );
      shadows = TVTheme.restingShadows;
    } else {
      backgroundColor = TVTheme.surfaceElevated;
      border = Border.all(
        color: Colors.transparent,
        width: TVTheme.focusBorderWidth,
      );
      shadows = TVTheme.restingShadows;
    }

    final textColor = _isFocused || widget.isSelected
        ? TVTheme.textPrimary
        : TVTheme.textSecondary;

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
      onKeyEvent: (node, event) {
        if (widget.onKeyEvent != null) {
          final res = widget.onKeyEvent!(node, event);
          if (res != KeyEventResult.ignored) return res;
        }
        return TvShortcuts.handleKeyEvent(
          event,
          onActivate: widget.onTap,
        );
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? TVTheme.focusScale : 1.0,
          duration: TVTheme.focusDuration,
          curve: TVTheme.focusCurve,
          child: AnimatedContainer(
            duration: TVTheme.focusDuration,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: TVTheme.borderRadiusFull,
              border: border,
              boxShadow: shadows,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isSelected) ...[
                  Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: _isFocused ? Colors.white : TVTheme.primary,
                  ),
                  const SizedBox(width: 6),
                ] else if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: 16,
                    color: textColor,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: _isFocused || widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: textColor,
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
