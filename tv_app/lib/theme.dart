import 'package:flutter/material.dart';

class TVTheme {
  static const Color background = Color(0xFF0F0F14);
  static const Color surface = Color(0xFF1A1A24);
  static const Color accent = Color(0xFFE50914); // Netflix Red
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF8E8E9E);

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
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textPrimary),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textPrimary),
        bodyLarge: TextStyle(fontSize: 14, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 12, color: textSecondary),
      ),
      useMaterial3: true,
    );
  }

  // TV Card Focus decoration
  static BoxDecoration focusDecoration(bool hasFocus) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: hasFocus ? accent : Colors.transparent,
        width: 3,
      ),
      boxShadow: hasFocus
          ? [
              BoxShadow(
                color: accent.withOpacity(0.5),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ]
          : [],
    );
  }
}
