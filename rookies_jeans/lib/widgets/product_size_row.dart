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

  /// Sizes on one line; the rest go on a second line.
  static const int sizesPerLine = 6;
  static const int _maxLines = 2;
  static const double _lineGap = 4;

  /// The room to reserve for the row: always two lines, so cards with
  /// few and many sizes line up.
  static double heightFor({double fontSize = 10}) =>
      (fontSize + 2) * _maxLines + _lineGap * (_maxLines - 1);

  static ProductOption? _sizeOption(ShopifyProduct product) {
    for (final opt in product.options) {
      if (opt.name.toLowerCase().contains('size')) return opt;
    }
    return null;
  }

  /// A size is in stock when any variant with that size can be bought.
  static bool _inStock(ShopifyProduct product, String optionName, String size) {
    return product.variants.any(
      (v) =>
          v.availableForSale &&
          v.selectedOptions.any((o) => o.name == optionName && o.value == size),
    );
  }

  @override
  Widget build(BuildContext context) {
    final option = _sizeOption(product);
    if (option == null || option.values.isEmpty) return const SizedBox.shrink();
    final sizes = option.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (
          var start = 0, line = 0;
          start < sizes.length && line < _maxLines;
          start += sizesPerLine, line++
        ) ...[
          if (line > 0) const SizedBox(height: _lineGap),
          SizedBox(
            height: fontSize + 2,
            child: _line(
              option.name,
              sizes.skip(start).take(sizesPerLine).toList(),
            ),
          ),
        ],
      ],
    );
  }

  /// One line of sizes, scaled down if it is still too wide for the card.
  Widget _line(String optionName, List<String> sizes) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          for (final size in sizes)
            Padding(
              padding: const EdgeInsets.only(right: 9),
              child: Builder(
                builder: (context) {
                  final inStock = _inStock(product, optionName, size);
                  return SoldOutStrike(
                    soldOut: !inStock,
                    child: Text(
                      size,
                      style: TextStyle(
                        fontFamily: AppFonts.body,
                        fontSize: fontSize,
                        height: 1,
                        color: inStock
                            ? AppColors.primary
                            : AppColors.secondaryText,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
