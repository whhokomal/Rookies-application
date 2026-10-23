import 'package:flutter/material.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/utils/color_names.dart';

/// The row of small color squares under a product card, like the website:
/// up to three swatches plus "+N" for the rest. Empty when the product has
/// only one color.
class ProductSwatchRow extends StatelessWidget {
  const ProductSwatchRow({super.key, required this.product, this.size = 14});

  final ShopifyProduct product;
  final double size;

  static const int _maxVisible = 3;

  /// Shopify's own Color option swatches if set, otherwise one per product
  /// in its Variant King color group (each color is its own product), in
  /// the group's order like the website.
  static List<_Swatch> _swatchesFor(ShopifyProduct product) {
    final fromOptions = product.colorHexCodes
        .map(hexToColor)
        .whereType<Color>()
        .map((c) => _Swatch(color: c))
        .toList();
    if (fromOptions.isNotEmpty) return fromOptions;
    final group = product.colorGroupSwatches;
    if (group.length < 2) return const [];
    return [
      for (final s in group)
        _Swatch(
          imageUrl: s.imageUrl,
          // Used when the group has no custom swatches, or one fails to load.
          color: colorFromHandle(s.handle) ?? const Color(0xFFCCCCCC),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final swatches = _swatchesFor(product);
    if (swatches.isEmpty) return const SizedBox.shrink();
    final visible = swatches.take(_maxVisible).toList();
    final extra = swatches.length - visible.length;
    return Row(
      children: [
        for (final swatch in visible)
          Container(
            margin: const EdgeInsets.only(right: 4),
            width: size,
            height: size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: swatch.imageUrl == null ? swatch.color : null,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: swatch.imageUrl == null
                ? null
                : Image.network(
                    swatch.imageUrl!,
                    fit: BoxFit.cover,
                    // The swatch CDN sends no CORS headers, so a browser
                    // build can't read the image's pixels; fall back to a
                    // plain <img> element, as the website itself uses.
                    // Ignored on Android/iOS.
                    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                    errorBuilder: (_, _, _) => ColoredBox(color: swatch.color),
                  ),
          ),
        if (extra > 0)
          Text(
            '+$extra',
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 10,
              height: 1,
              color: AppColors.secondaryText,
            ),
          ),
      ],
    );
  }
}

/// One square in the row: the website's custom swatch image when there is
/// one, else a solid [color].
class _Swatch {
  const _Swatch({required this.color, this.imageUrl});

  final Color color;
  final String? imageUrl;
}
