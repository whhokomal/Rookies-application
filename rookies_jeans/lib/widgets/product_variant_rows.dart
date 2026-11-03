import 'package:flutter/material.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/services/shopify_storefront_service.dart';
import 'package:rookies_jeans/widgets/product_size_row.dart';
import 'package:rookies_jeans/widgets/product_swatch_row.dart';

/// Color swatches and sizes under a product card, as on the collection
/// grid. Products saved without their options (recently viewed, wishlist)
/// have them looked up by handle. Always [height] tall, so cards in a row
/// line up whether or not they have swatches.
class ProductVariantRows extends StatelessWidget {
  const ProductVariantRows({
    super.key,
    required this.product,
    this.swatchSize = 14,
    this.sizeFontSize = 10,
  });

  final ShopifyProduct product;
  final double swatchSize;
  final double sizeFontSize;

  static const double _gap = 6;

  double get height =>
      heightFor(swatchSize: swatchSize, sizeFontSize: sizeFontSize);

  static double heightFor({double swatchSize = 14, double sizeFontSize = 10}) =>
      swatchSize + _gap + ProductSizeRow.heightFor(fontSize: sizeFontSize);

  @override
  Widget build(BuildContext context) {
    if (product.options.isNotEmpty || product.handle.isEmpty) {
      return _rows(product);
    }
    return FutureBuilder<ShopifyProduct?>(
      future: ShopifyStorefrontService.instance.getProductCard(product.handle),
      builder: (_, snap) => _rows(snap.data),
    );
  }

  Widget _rows(ShopifyProduct? product) {
    return SizedBox(
      height: height,
      child: product == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ProductSwatchRow.hasSwatches(product)) ...[
                  SizedBox(
                    height: swatchSize,
                    child: ProductSwatchRow(product: product, size: swatchSize),
                  ),
                  const SizedBox(height: _gap),
                ],
                SizedBox(
                  height: ProductSizeRow.heightFor(fontSize: sizeFontSize),
                  child: ProductSizeRow(
                    product: product,
                    fontSize: sizeFontSize,
                  ),
                ),
              ],
            ),
    );
  }
}
