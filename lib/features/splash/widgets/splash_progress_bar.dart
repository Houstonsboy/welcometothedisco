import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Thin pill-shaped progress bar used on the splash screen.
///
/// [progress] must be in [0.0, 1.0].  The fill animates externally via a
/// TweenAnimationBuilder in SplashScreen — this widget is intentionally dumb.
class SplashProgressBar extends StatelessWidget {
  const SplashProgressBar({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44.0,
      height: 3.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1.5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: AppTheme.splashProgressTrack),
            FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              alignment: Alignment.centerLeft,
              child: const ColoredBox(color: AppTheme.splashProgressFill),
            ),
          ],
        ),
      ),
    );
  }
}
