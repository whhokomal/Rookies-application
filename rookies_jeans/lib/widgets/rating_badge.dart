import 'package:flutter/material.dart';
import 'package:rookies_jeans/constants/app_ui.dart';

/// Star color shared by every rating widget.
const Color kRatingStarColor = Color(0xFFF5A623);

/// Rating to one decimal, e.g. 4.5 → "4.5", 5 → "5.0".
String formatRating(double rating) => rating.toStringAsFixed(1);

/// "4.5 ★ | 12" chip laid over the bottom-left of a product card's image,
/// the way Myntra / Snitch show ratings, so cards without reviews keep the
/// same height as cards with them.
class RatingBadge extends StatelessWidget {
  const RatingBadge({
    super.key,
    required this.rating,
    required this.count,
    this.fontSize = 10,
  });

  final double rating;
  final int count;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: AppFonts.body,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: Colors.black,
      height: 1.1,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatRating(rating), style: style),
          const SizedBox(width: 2),
          Icon(Icons.star_rounded, size: fontSize + 2, color: kRatingStarColor),
          Container(
            width: 1,
            height: fontSize,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: Colors.black26,
          ),
          Text('$count', style: style.copyWith(fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}

/// Five stars filled to [rating] (halves included).
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rating, this.size = 16});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final fill = rating - i;
        final icon = fill >= 0.75
            ? Icons.star_rounded
            : fill >= 0.25
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded;
        return Icon(
          icon,
          size: size,
          color: fill >= 0.25 ? kRatingStarColor : AppColors.hint,
        );
      }),
    );
  }
}
