import 'package:flutter/material.dart';
import 'package:rookies_jeans/constants/app_ui.dart';

/// Crosses out [child] with a diagonal line from bottom-left to top-right
/// when [soldOut], like the website does for sold-out sizes and colors.
class SoldOutStrike extends StatelessWidget {
  const SoldOutStrike({super.key, required this.soldOut, required this.child});

  final bool soldOut;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: soldOut
        ? _StrikeThroughPainter(color: AppColors.secondaryText)
        : null,
    child: child,
  );
}

class _StrikeThroughPainter extends CustomPainter {
  const _StrikeThroughPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(_StrikeThroughPainter old) => old.color != color;
}
