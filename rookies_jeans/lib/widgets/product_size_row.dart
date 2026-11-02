import 'package:flutter/material.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/widgets/sold_out_strike.dart';

/// The product's sizes under a product card, like the website: "S M L XL"
/// with sold-out sizes greyed and crossed out. Empty when the product
/// has no Size option.
class ProductSizeRow extends StatelessWidget {
  const ProductSizeRow({super.key, required this.product, this.fontSize = 10});

  final ShopifyProduct product;
  final double fontSize;

  static ProductOption? _sizeOption(ShopifyProduct product) {
    for (final opt in product.options) {
      if (opt.name.toLowerCase().contains('size')) return opt;
    }
    return null;
  }

  /// A size is in stock when any variant with that size can be bought.
  static bool _inStock(ShopifyProduct product, String optionName, String size) {
    return product.variants.any((v) =>
        v.availableForSale &&
        v.selectedOptions.any((o) => o.name == optionName && o.value == size));
  }

  @override
  Widget build(BuildContext context) {
    final option = _sizeOption(product);
    if (option == null || option.values.isEmpty) return const SizedBox.shrink();
    // Scaled down rather than wrapped, so a long size list stays on one line.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          for (final size in option.values)
            Padding(
              padding: const EdgeInsets.only(right: 9),
              child: Builder(builder: (context) {
                final inStock = _inStock(product, option.name, size);
                return SoldOutStrike(
                  soldOut: !inStock,
                  child: Text(
                    size,
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: fontSize,
                      height: 1,
                      color:
                          inStock ? AppColors.primary : AppColors.secondaryText,
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}
