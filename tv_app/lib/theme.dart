import 'package:flutter/material.dart';

class TVTheme {
  // --- Color Palette ---
  static const Color background = Color(0xFF07080B);
  static const Color surface = Color(0xFF131418);
  static const Color surfaceElevated = Color(0xFF1C1D24);
  static const Color primary = Color(0xFFE50914);
  static const Color accent = primary; // Backward compatibility alias
  static const Color accentGlow = Color(0xFFFF3B30);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9E9EA7);
  static const Color textMuted = Color(0xFF8E92A2); // 14sp min legibility from 10 feet

  // --- Radii & Shapes ---
  static const double radiusSm = 4.0;
  static const double radiusMd = 10.0;
  static const double radiusFull = 9999.0;

  static final BorderRadius borderRadiusSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderRadiusFull = BorderRadius.circular(radiusFull);

  // --- Spacing & Overscan ---
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 48.0;
  static const double overscanMargin = 48.0;
  static const EdgeInsets overscanPadding = EdgeInsets.all(48.0);

  // --- 10-Foot Focus Constants ---
  static const double focusScale = 1.08;
  static const double buttonFocusScale = 1.06;
  static const double focusBorderWidth = 3.0;
  static const Duration focusDuration = Duration(milliseconds: 250);
  static const Curve focusCurve = Curves.easeOutCubic;

  // Dual-layer Focus Shadows
  static const BoxShadow focusAmbientHalo = BoxShadow(
    color: Color(0x26FFFFFF),
    blurRadius: 10,
    spreadRadius: 1,
  );

  static const BoxShadow focusDropShadow = BoxShadow(
    color: Color(0xD9000000),
    blurRadius: 16,
    offset: Offset(0, 8),
  );

  static List<BoxShadow> get focusShadows => const [
    focusAmbientHalo,
    focusDropShadow,
  ];

  static List<BoxShadow> get restingShadows => const [];

  static Matrix4 focusScaleTransform([double scale = focusScale]) =>
      Matrix4.diagonal3Values(scale, scale, 1.0);

  // Focus Decoration Helper
  static BoxDecoration focusDecoration(
    bool hasFocus, {
    double radius = radiusMd,
    Color? borderColor,
    double borderWidth = focusBorderWidth,
    Color? backgroundColor,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: hasFocus ? (borderColor ?? Colors.white) : Colors.transparent,
        width: hasFocus ? borderWidth : 0,
      ),
      boxShadow: hasFocus ? focusShadows : restingShadows,
    );
  }

  // --- Theme Data ---
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        surface: surface,
        error: primary,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
          height: 1.1,
        ),
        headlineLarge: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          height: 1.2,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          height: 1.25,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: textPrimary,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textSecondary,
          height: 1.3,
        ),
        bodySmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textMuted,
        ),
        labelSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textMuted,
        ),
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
}
