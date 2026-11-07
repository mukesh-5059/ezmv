import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Universal Remote D-Pad Key Engine for Android TV, Fire TV, Google TV,
/// gamepads, and desktop/emulator testing.
///
/// Maps all hardware enter/select triggers to [ActivateIntent] and provides
/// key event helpers for custom focusable widgets.
class TvShortcuts extends StatelessWidget {
  final Widget child;
  final Map<ShortcutActivator, Intent>? additionalShortcuts;

  const TvShortcuts({
    super.key,
    required this.child,
    this.additionalShortcuts,
  });

  /// Universal shortcut map binding all TV remote select and enter keys
  /// to [ActivateIntent].
  static final Map<ShortcutActivator, Intent> shortcuts = {
    const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
  };

  /// Returns true if [key] is an activate key across any remote or gamepad.
  static bool isActivateKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space;
  }

  /// Handles a [KeyEvent] for widgets that implement explicit [Focus.onKeyEvent].
  ///
  /// Returns [KeyEventResult.handled] if an activate key was pressed down,
  /// triggering [onActivate].
  static KeyEventResult handleKeyEvent(
    KeyEvent event, {
    required VoidCallback onActivate,
  }) {
    if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
      onActivate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        ...shortcuts,
        if (additionalShortcuts != null) ...additionalShortcuts!,
      },
      child: child,
    );
  }
}
