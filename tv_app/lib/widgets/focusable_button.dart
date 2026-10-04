import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FocusableButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final Color? focusedBorderColor;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback onPressed;
  final EdgeInsetsGeometry padding;

  const FocusableButton({
    super.key,
    required this.label,
    this.icon,
    this.color = Colors.white10,
    this.focusedBorderColor,
    this.autofocus = false,
    this.focusNode,
    required this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  @override
  State<FocusableButton> createState() => _FocusableButtonState();
}

class _FocusableButtonState extends State<FocusableButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.focusedBorderColor ?? Colors.white;
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.numpadEnter ||
             event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _isFocused ? widget.color : Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? borderColor : Colors.transparent,
              width: 3.0,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.22),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: _isFocused ? Colors.white : Colors.white70),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: _isFocused ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
