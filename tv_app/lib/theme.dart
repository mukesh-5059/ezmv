import 'package:flutter/material.dart';

class TVTheme {
  static const Color background = Color(0xFF07080B);
  static const Color surface = Color(0xFF131418);
  static const Color surfaceElevated = Color(0xFF1C1D24);
  static const Color accent = Color(0xFFE50914);
  static const Color accentGlow = Color(0xFFFF3B30);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF9E9EA7);
  static const Color textMuted = Color(0xFF6E717E);

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
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      useMaterial3: true,
    );
  }

  // Cinematic TV Card Focus Decoration with White border, subtle soft halo & deep OLED drop shadow
  static BoxDecoration focusDecoration(
    bool hasFocus, {
    double radius = 10,
    Color? borderColor,
    double borderWidth = 3.0,
  }) {
    final border = borderColor ?? Colors.white;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: hasFocus ? border : Colors.transparent,
        width: hasFocus ? borderWidth : 0,
      ),
      boxShadow: hasFocus
          ? [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.15),
                blurRadius: 10,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.85),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 6,
                offset: const Offset(0, 4),
              ),
            ],
    );
  }
}
