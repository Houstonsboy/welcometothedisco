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
  static const Color gradientStart = Color(0xFF1E3DE1); // deep blue / purple
  static const Color gradientEnd   = Color(0xFFf85187); // hot pink

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
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [gradientStart, gradientEnd],
    ),
  );

  /// Raw gradient (use wherever `Gradient` is expected directly).
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientEnd],
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
}
