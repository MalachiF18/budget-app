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
final ThemeData personalTheme = _buildTheme(const Color(0xFF00897B));

/// Indigo/violet so Group is obviously a different space.
final ThemeData groupTheme = _buildTheme(const Color(0xFF5C4BD6));
