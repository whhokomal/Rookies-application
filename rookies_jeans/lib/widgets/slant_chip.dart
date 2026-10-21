import 'package:flutter/material.dart';
import 'package:rookies_jeans/constants/app_ui.dart';

/// Slanted "sticker" chip: black with a red offset shadow when selected,
/// white with a black outline and black offset shadow otherwise, with an
/// optional small count after the label (e.g. `TOP WEAR 30`).
class SlantChip extends StatelessWidget {
  const SlantChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.fontSize = 15,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final double fontSize;

  static const Color accent = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? Colors.white : Colors.black;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        // Room for the slant and the offset shadow so neither gets clipped.
        padding: const EdgeInsets.only(left: 4, right: 7),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(-0.18),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? Colors.black : Colors.white,
              border: Border.all(color: Colors.black, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: selected ? accent : Colors.black,
                  offset: const Offset(3, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppFonts.subheading,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: AppFonts.number,
                      fontSize: fontSize * 0.6,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
