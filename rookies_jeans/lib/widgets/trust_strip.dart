import 'package:flutter/material.dart';
import 'package:rookies_jeans/constants/app_ui.dart';

/// The website's trust strip: four badges in two rows. Shown under Buy Now
/// on the product page and on the home page.
class TrustStrip extends StatelessWidget {
  const TrustStrip({super.key});

  static const List<(IconData, String, String)> _items = [
    (Icons.local_shipping_outlined, 'Free Delivery', 'On prepaid orders'),
    (Icons.replay_rounded, '7-Day Returns', 'Easy returns policy'),
    (Icons.inventory_2_outlined, 'Cash on Delivery', 'Available nationwide'),
    (Icons.lock_outline_rounded, 'Secure Payments', 'UPI, cards & net banking'),
  ];

  Widget _badge(BuildContext context, (IconData, String, String) item) {
    final r = Responsive.of(context, baseW: 400, maxScale: 1.25);
    final (icon, title, subtitle) = item;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: r.s(44),
            height: r.s(44),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.border,
            ),
            child: Icon(icon, size: r.s(20), color: AppColors.primary),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: r.s(12.5),
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: r.s(10.5),
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_badge(context, _items[0]), _badge(context, _items[1])],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_badge(context, _items[2]), _badge(context, _items[3])],
            ),
          ],
        ),
      ),
    );
  }
}
