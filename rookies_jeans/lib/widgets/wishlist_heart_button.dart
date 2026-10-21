import 'package:flutter/material.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/services/wishlist_service.dart';

/// Heart toggle for a product card's image. Listens to [WishlistService] so
/// every card showing the same product updates together.
class WishlistHeartButton extends StatelessWidget {
  const WishlistHeartButton({
    super.key,
    required this.product,
    this.size = 20,
    this.idleColor = Colors.white,
  });

  final ShopifyProduct product;
  final double size;

  /// Outline colour when not wishlisted (white reads well over photos).
  final Color idleColor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WishlistService.instance,
      builder: (context, _) {
        final wishlisted = WishlistService.instance.isWishlisted(product.id);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => WishlistService.instance.toggleProduct(product),
          child: Padding(
            // Bigger tap target than the icon itself.
            padding: const EdgeInsets.all(6),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                wishlisted
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                key: ValueKey(wishlisted),
                size: size,
                color: wishlisted ? Colors.red : idleColor,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black38)],
              ),
            ),
          ),
        );
      },
    );
  }
}
