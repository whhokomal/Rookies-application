import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/screens/products/product_detail_page.dart';
import 'package:rookies_jeans/widgets/price_text.dart';
import 'package:rookies_jeans/widgets/wishlist_heart_button.dart';

/// Tilted heading + horizontally scrolling product cards ("Goes Well With",
/// "You May Also Like", "Recently Viewed"). Tapping a card opens the product.
class ProductRowSection extends StatelessWidget {
  const ProductRowSection({
    super.key,
    required this.title,
    required this.products,
  });

  final String title;
  final List<ShopifyProduct> products;

  @override
  Widget build(BuildContext context) {
    double s(double base) =>
        Responsive.of(context, baseW: 400, maxScale: 1.25).s(base);

    final cardWidth = s(125).clamp(110.0, 165.0);
    // Product photos are 2:3 portrait; match it so nothing gets cropped.
    final imgHeight = cardWidth * 1.5;
    final listHeight = imgHeight + s(56).clamp(50.0, 74.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 10),
            child: Transform(
              transform: Matrix4.skewX(-0.2),
              alignment: Alignment.bottomLeft,
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: AppFonts.heading,
                  fontSize: s(22).clamp(20.0, 28.0),
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          SizedBox(
            height: listHeight,
            child: ListView.separated(
              // Keeps the scroll position when the row is rebuilt or
              // scrolled off and back on screen.
              key: PageStorageKey('product-row-$title'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 16),
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) =>
                  _card(context, s, products[i], cardWidth, imgHeight),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context,
    double Function(double) s,
    ShopifyProduct product,
    double cardWidth,
    double imgHeight,
  ) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailPage(
            handle: product.handle,
            title: product.title,
            heroImageUrl: product.primaryImageUrl,
          ),
        ),
      ),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              child: SizedBox(
                width: cardWidth,
                height: imgHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    product.primaryImageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: product.primaryImageUrl!,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            placeholder: (_, _) => Container(color: AppColors.fieldFill),
                            errorWidget: (_, _, _) =>
                                Container(color: AppColors.fieldFill),
                          )
                        : Container(color: AppColors.fieldFill),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: WishlistHeartButton(
                        product: product,
                        size: 18,
                        idleColor: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              product.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: s(11),
                color: AppColors.primary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 3),
            _priceText(s, product),
          ],
        ),
      ),
    );
  }

  Widget _priceText(double Function(double) s, ShopifyProduct product) {
    if (!product.isOnSale) {
      return PriceText(
        product.formattedPrice,
        currencyCode: product.currencyCode,
        fontSize: s(11),
        color: AppColors.primary,
        amountFontFamily: AppFonts.body,
      );
    }
    return Row(
      children: [
        Flexible(
          child: PriceText(
            product.formattedPrice,
            currencyCode: product.currencyCode,
            fontSize: s(11),
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: PriceText(
            product.formattedCompareAtPrice,
            currencyCode: product.currencyCode,
            fontSize: s(10),
            color: AppColors.secondaryText,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ],
    );
  }
}
