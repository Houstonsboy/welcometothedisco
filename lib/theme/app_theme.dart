// lib/theme/app_theme.dart
//
// Single source of truth for every background / brand color in the app.
// Change values here and every screen / widget automatically picks them up.
//
// ─── HOW TO EXPERIMENT ──────────────────────────────────────────────────────
//
// Dark theme example:
//   static const Color gradientStart = Color(0xFF0D0D1A);
//   static const Color gradientEnd   = Color(0xFF1A0D2E);
//
// Retro amber / teal:
//   static const Color gradientStart = Color(0xFF1A2F2F);
//   static const Color gradientEnd   = Color(0xFFD97706);
//
// Current: deep blue → hot pink (original brand).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

abstract final class AppTheme {
  // ── Brand gradient (full-screen backgrounds, panels, headers) ───────────
  static const Color gradientStart = Color(0xFF0A1F5C); // deep navy
  static const Color gradientEnd   = Color(0xFF081848); // darkest navy

  // ── Global typography ─────────────────────────────────────────────────────
  /// Use for decorative/title text (app bars, section headers).
  static const String fontHeader = 'JraotHollow';

  /// Use for standard UI/body text.
  static const String fontBody = 'Satoshi';
  // static const String fontBody = 'Roboto';

  /// Base body font size. 14 = Flutter default (no change); increase to scale up all body text.
  static const double fontBodySize = 14.0;

  /// Default color for body typography (matches Stories friend username green).
  static const Color fontBodyColor = createGreen;

  // ── Glass / surface overlays ────────────────────────────────────────────
  /// Opacity used on the top-layer glass panels (cards, drawers).
  static const double glassPanelOpacity   = 0.45;

  /// Opacity used on the bottom navigation bar glass.
  static const double glassNavOpacity     = 0.35;

  // ── Accent / semantic colors ────────────────────────────────────────────
  /// Spotify brand green (playback buttons, tracks).
  static const Color spotifyGreen         = Color(0xFF17B560);

  /// Positive / success feedback (snackbars, completed states).
  static const Color successGreen         = Color(0xFF22C55E);

  /// "Honk" title accent used in app-bar / auth screen headings.
  static const Color titleAccent          = Color.fromARGB(255, 159, 181, 63);

  /// Bottom-nav selected icon tint (slightly lighter pink than gradientEnd).
  static const Color navSelectedIcon      = Color(0xFFff66a6);

  /// Create-button / UI action green.
  static const Color createGreen          = Color.fromARGB(255, 30, 222, 37);

  /// Author profile chip accent (magenta — inbox tile, collaboration).
  static const Color authorAccent         = Color(0xFFE310EF);

  // ── Collaborator invite banner ───────────────────────────────────────────
  static const Color bannerDark1          = Color(0xFF0E0E1A);
  static const Color bannerDark2          = Color(0xFF14102A);
  static const Color bannerStreak1        = Color(0xFF6C63FF);
  static const Color bannerTeal           = Color(0xFF00C9A7);
  static const Color bannerAmber          = Color(0xFFFFAA00);

  // ── Convenience builders ─────────────────────────────────────────────────

  /// Full-screen gradient decoration (use as `decoration:` on a `Container`).
  static const BoxDecoration backgroundDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0.0, 0.30, 0.45, 0.60, 1.0],
      colors: [
        Color(0xFF0A1F5C),
        Color(0xFF0D3080),
        Color(0xFF0F3A9A),
        Color(0xFF0D3080),
        Color(0xFF081848),
      ],
    ),
  );

  /// Raw gradient (use wherever `Gradient` is expected directly).
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.30, 0.45, 0.60, 1.0],
    colors: [
      Color(0xFF0A1F5C),
      Color(0xFF0D3080),
      Color(0xFF0F3A9A),
      Color(0xFF0D3080),
      Color(0xFF081848),
    ],
  );

  /// Glass-panel gradient for cards / headers at [glassPanelOpacity].
  static LinearGradient glassPanelGradient({
    double opacity = glassPanelOpacity,
  }) =>
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          gradientStart.withOpacity(opacity),
          gradientEnd.withOpacity(opacity),
        ],
      );

  /// Bottom-nav glass gradient at [glassNavOpacity].
  static LinearGradient glassNavGradient({
    double opacity = glassNavOpacity,
  }) =>
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          gradientStart.withOpacity(opacity),
          gradientEnd.withOpacity(opacity),
        ],
      );

  /// App-wide baseline theme:
  /// - Body text uses [fontBody].
  /// - All default text styles are reduced by 1 point.
  static ThemeData appTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    final text = base.textTheme.apply(
      fontFamily: fontBody,
      bodyColor: fontBodyColor,
      fontSizeDelta: fontBodySize - 14,
    );
    TextStyle? minusOne(TextStyle? s) {
      if (s == null) return null;
      final size = s.fontSize;
      return size == null ? s : s.copyWith(fontSize: size - 1);
    }
    return base.copyWith(
      textTheme: text.copyWith(
        displayLarge: minusOne(text.displayLarge),
        displayMedium: minusOne(text.displayMedium),
        displaySmall: minusOne(text.displaySmall),
        headlineLarge: minusOne(text.headlineLarge),
        headlineMedium: minusOne(text.headlineMedium),
        headlineSmall: minusOne(text.headlineSmall),
        titleLarge: minusOne(text.titleLarge),
        titleMedium: minusOne(text.titleMedium),
        titleSmall: minusOne(text.titleSmall),
        bodyLarge: minusOne(text.bodyLarge),
        bodyMedium: minusOne(text.bodyMedium),
        bodySmall: minusOne(text.bodySmall),
        labelLarge: minusOne(text.labelLarge),
        labelMedium: minusOne(text.labelMedium),
        labelSmall: minusOne(text.labelSmall),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: const TextStyle(
          fontFamily: fontHeader,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
