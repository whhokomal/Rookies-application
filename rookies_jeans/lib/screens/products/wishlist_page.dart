import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/screens/collections/collections.dart';
import 'package:rookies_jeans/screens/products/product_detail_page.dart';
import 'package:rookies_jeans/services/wishlist_service.dart';
import 'package:rookies_jeans/widgets/price_text.dart';

class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  double _s(double base) =>
      Responsive.of(context, baseW: 400, maxScale: 1.25).s(base);

  double _maxTileExtent(double width) {
    if (width >= 1024) return 240;
    if (width >= 600) return 220;
    return 200;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final titleSize = (width * 0.09).clamp(22.0, 40.0);

    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
            ),
            Expanded(
              child: Text(
                'MY WISHLIST',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: titleSize,
                  height: 1,
                  fontFamily: AppFonts.heading,
                  fontStyle: FontStyle.italic,
                  color: AppColors.primary,
                  // letterSpacing: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: WishlistService.instance,
        builder: (context, _) {
          final products = WishlistService.instance.items;

          if (products.isEmpty) {
            return _emptyWishlistState();
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: products.length,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: _maxTileExtent(width),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.62,
                ),
                itemBuilder: (context, index) {
                  final product = products[index];
                  return _wishlistCard(product);
                },
              ),
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _emptyWishlistState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border_rounded,
              size: _s(70),
              color: AppColors.hint,
            ),
            const SizedBox(height: 16),
            Text(
              'No wishlist items yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.heading,
                fontSize: _s(22),
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Products you like will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: _s(13),
                color: AppColors.secondaryText,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: _s(170).clamp(150.0, 220.0),
              height: _s(42).clamp(40.0, 52.0),
              child: OutlinedButton(
                onPressed: _openExploreProducts,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary, width: 1.1),
                  shape: const RoundedRectangleBorder(
                      // borderRadius: BorderRadius.circular(6),
                      ),
                  elevation: 0,
                ),
                child: Text(
                  'EXPLORE PRODUCT',
                  style: TextStyle(
                    fontFamily: AppFonts.bold,
                    fontSize: _s(11),
                    fontWeight: FontWeight.w800,
                    // letterSpacing: 1.1,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openExploreProducts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExploreCategoriesPage(),
      ),
    );
  }

  Widget _wishlistCard(ShopifyProduct product) {
    final imageUrl =
        product.imageUrls.isNotEmpty ? product.imageUrls.first : null;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailPage(
              handle: product.handle,
              title: product.title,
              heroImageUrl: imageUrl,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          // borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, _) =>
                                  Container(color: AppColors.fieldFill),
                              errorWidget: (_, _, _) => Container(
                                color: AppColors.fieldFill,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  size: 32,
                                  color: AppColors.hint,
                                ),
                              ),
                            )
                          : Container(
                              color: AppColors.fieldFill,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 32,
                                color: AppColors.hint,
                              ),
                            ),
                    ),
                  ),
                  if (_isOnSale(product))
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          // borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _discountPercent(product),
                          style: TextStyle(
                            fontFamily: AppFonts.bold,
                            color: Colors.white,
                            fontSize: _s(9),
                            fontWeight: FontWeight.w800,
                            // letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        WishlistService.instance.removeById(product.id);
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: Colors.red,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: _s(12),
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _priceBlock(product),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceBlock(ShopifyProduct product) {
    if (!_isOnSale(product)) {
      return PriceText(_formattedPrice(product), currencyCode: product.currencyCode, fontSize: _s(14), fontWeight: FontWeight.w800, amountFontFamily: AppFonts.body, color: AppColors.primary);
    }

    final saved = ((product.compareAtPrice ?? 0) - product.price).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            PriceText(_formattedCompareAtPrice(product), currencyCode: product.currencyCode, fontSize: _s(10), color: AppColors.secondaryText, amountFontFamily: AppFonts.body, decoration: TextDecoration.lineThrough),
            PriceText(_formattedPrice(product), currencyCode: product.currencyCode, fontSize: _s(12), fontWeight: FontWeight.w800, amountFontFamily: AppFonts.body, color: AppColors.primary),
          ],
        ),
        const SizedBox(height: 4),
        SavedAmountText(saved.toString(), currencyCode: product.currencyCode, fontSize: _s(9), fontWeight: FontWeight.w600, color: AppColors.success, fontFamily: AppFonts.bold),
      ],
    );
  }

  bool _isOnSale(ShopifyProduct product) {
    return product.compareAtPrice != null &&
        product.compareAtPrice! > product.price;
  }

  String _formattedPrice(ShopifyProduct product) {
    return product.currencyCode == 'INR'
        ? product.price.toStringAsFixed(0)
        : '${product.currencyCode} ${product.price.toStringAsFixed(2)}';
  }

  String _formattedCompareAtPrice(ShopifyProduct product) {
    final compareAtPrice = product.compareAtPrice;
    if (compareAtPrice == null) return '';
    return product.currencyCode == 'INR'
        ? compareAtPrice.toStringAsFixed(0)
        : '${product.currencyCode} ${compareAtPrice.toStringAsFixed(2)}';
  }

  String _discountPercent(ShopifyProduct product) {
    final compareAtPrice = product.compareAtPrice;
    if (compareAtPrice == null || compareAtPrice <= 0) return 'SALE';
    final pct = ((1 - (product.price / compareAtPrice)) * 100).round();
    return '$pct% OFF';
  }
}