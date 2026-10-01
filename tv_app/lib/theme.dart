import 'package:flutter/material.dart';

class TVTheme {
  static const Color background = Color(0xFF0C0D14);
  static const Color surface = Color(0xFF161824);
  static const Color surfaceElevated = Color(0xFF222638);
  static const Color accent = Color(0xFFE50914);
  static const Color accentGlow = Color(0xFFFF3B30);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFA0A5B8);
  static const Color textMuted = Color(0xFF6B7280);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        surface: surface,
        error: accent,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: textPrimary, letterSpacing: -0.5),
        headlineLarge: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: textPrimary),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textPrimary),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: TextStyle(fontSize: 16, color: textPrimary, height: 1.4),
        bodyMedium: TextStyle(fontSize: 14, color: textSecondary, height: 1.3),
        bodySmall: TextStyle(fontSize: 12, color: textMuted),
      ),
      useMaterial3: true,
    );
  }

  // Cinematic TV Card Focus Decoration
  static BoxDecoration focusDecoration(bool hasFocus, {double radius = 10}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: hasFocus ? Colors.white : Colors.transparent,
        width: hasFocus ? 2.5 : 0,
      ),
      boxShadow: hasFocus
          ? [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.35),
                blurRadius: 18,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 10,
                offset: const Offset(0, 8),
              ),
            ]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 6,
                offset: const Offset(0, 4),
              ),
            ],
    );
  }
}
