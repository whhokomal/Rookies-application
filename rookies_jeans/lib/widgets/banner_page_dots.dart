import 'package:flutter/material.dart';

/// Horizontal page indicator for full-bleed image banners (home hero,
/// Collections page). The current page stretches into a short bar; a soft
/// shadow keeps the white dots readable on light photos too.
class BannerPageDots extends StatelessWidget {
  const BannerPageDots({super.key, required this.count, required this.index});

  final int count;
  final int index;

  /// Where both banners place the dots: bottom-right, lifted off the edge.
  static const double right = 16;
  static const double bottom = 28;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 20 : 7,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: i == index ? 1.0 : 0.75),
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
