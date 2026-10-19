import 'package:flutter/material.dart';

// Both themes come from one builder so fonts, shapes, radii and spacing are
// identical; only the seed color (and so the whole color scheme) differs.
ThemeData _buildTheme(Color seed) {
  final scheme = ColorScheme.fromSeed(seedColor: seed);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
    ),
  );
}

/// Green/teal, matches the Personal mockup.
const personalBackground = Color(0xFF14211C);
const personalSurface = Color(0xFF1B2C25);
const personalBorder = Color(0xFF2B3E35);
const personalAccent = Color(0xFF37C3A2);
const personalMuted = Color(0xFF9AADA3);
const personalText = Color(0xFFE6EEE9);

final ThemeData personalTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: personalAccent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: personalAccent,
        onPrimary: personalBackground,
        surface: personalSurface,
        onSurface: personalText,
        onSurfaceVariant: personalMuted,
        outline: personalBorder,
      ),
  scaffoldBackgroundColor: personalBackground,
  dividerColor: personalBorder,
  cardTheme: CardThemeData(
    color: personalSurface,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: personalBorder),
    ),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: personalSurface,
  ),
  navigationBarTheme: NavigationBarThemeData(
    height: 76,
    backgroundColor: personalBackground,
    surfaceTintColor: Colors.transparent,
    indicatorColor: Colors.transparent,
    iconTheme: WidgetStateProperty.resolveWith(
      (states) => IconThemeData(
        size: 25,
        color: states.contains(WidgetState.selected)
            ? personalAccent
            : personalMuted,
      ),
    ),
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: states.contains(WidgetState.selected)
            ? personalAccent
            : personalMuted,
      ),
    ),
  ),
);

/// Indigo/violet so Group is obviously a different space.
final ThemeData groupTheme = _buildTheme(const Color(0xFF5C4BD6));
