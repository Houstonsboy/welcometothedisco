import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Draws the four-quadrant circular logo entirely in code.
///
/// Quadrant layout (Y-down screen coordinates):
///   Top-left  → dark   | Top-right   → yellow
///   ─────────────────────────────────────────
///   Bot-left  → yellow | Bottom-right → dark
///
/// The circular boundary comes from a widget-level [ClipOval], which is
/// applied by Flutter's rendering pipeline before the painter runs — so the
/// shape is always a circle from the very first frame, regardless of the
/// Skia / Impeller backend.
class QuadrantLogo extends StatelessWidget {
  const QuadrantLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      // ClipOval clips the child to a circle at the widget level — guaranteed
      // to take effect on frame 1 on every renderer.
      child: ClipOval(
        child: CustomPaint(
          size: Size(size, size),
          painter: _QuadrantPainter(),
        ),
      ),
    );
  }
}

class _QuadrantPainter extends CustomPainter {
  static final _yellow = Paint()
    ..color = AppTheme.splashLogoYellow
    ..style = PaintingStyle.fill;

  static final _dark = Paint()
    ..color = AppTheme.splashLogoDark
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Plain rectangles — the ClipOval above turns them into circle quadrants.
    canvas.drawRect(Rect.fromLTRB(cx, 0, size.width, cy), _yellow);         // top-right
    canvas.drawRect(Rect.fromLTRB(cx, cy, size.width, size.height), _dark);  // bottom-right
    canvas.drawRect(Rect.fromLTRB(0, cy, cx, size.height), _yellow);         // bottom-left
    canvas.drawRect(Rect.fromLTRB(0, 0, cx, cy), _dark);                     // top-left
  }

  @override
  bool shouldRepaint(covariant _QuadrantPainter oldDelegate) => false;
}
