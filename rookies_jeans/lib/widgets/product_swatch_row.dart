import 'package:flutter/material.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/services/shopify_storefront_service.dart';
import 'package:rookies_jeans/utils/color_names.dart';
import 'package:rookies_jeans/widgets/sold_out_strike.dart';

/// The row of small color squares under a product card, like the website:
/// up to three swatches plus "+N" for the rest. Empty when the product has
/// only one color. Sold-out colors are crossed out and can't be tapped.
class ProductSwatchRow extends StatelessWidget {
  const ProductSwatchRow({
    super.key,
    required this.product,
    this.size = 14,
    this.onSelectColor,
  });

  final ShopifyProduct product;
  final double size;

  /// Called with another color's product handle when its swatch is tapped,
  /// so the card can swap to that color. Swatches aren't tappable without it.
  final ValueChanged<String>? onSelectColor;

  static const int _maxVisible = 3;

  /// Whether the row would show anything for [product].
  static bool hasSwatches(ShopifyProduct product) =>
      _swatchesFor(product).isNotEmpty;

  /// Shopify's own Color option swatches if set, otherwise one per product
  /// in its Variant King color group (each color is its own product), in
  /// the group's order like the website.
  static List<_Swatch> _swatchesFor(ShopifyProduct product) {
    final fromOptions = _optionSwatches(product);
    if (fromOptions.isNotEmpty) return fromOptions;
    final group = product.colorGroupSwatches;
    if (group.length < 2) return const [];
    return [
      for (final s in group)
        _Swatch(
          // Used when the group has no custom swatch, or while it loads.
          color: colorFromHandle(s.handle) ?? const Color(0xFFCCCCCC),
          handle: s.handle,
          // The group's hand-picked color chip, the same one the website's
          // cards show.
          imageUrl: s.imageUrl,
          // This product's own stock is known; other colors are looked up.
          inStock: s.handle == product.handle
              ? product.variants.any((v) => v.availableForSale)
              : null,
        ),
    ];
  }

  /// One swatch per Color option value with a swatch color, in stock when
  /// any variant of that color can be bought.
  static List<_Swatch> _optionSwatches(ShopifyProduct product) {
    for (final opt in product.options) {
      final name = opt.name.toUpperCase();
      if (name != 'COLOR' && name != 'COLOUR') continue;
      final seen = <String>{};
      return [
        for (final v in opt.optionValues)
          if (v.swatchColor != null && seen.add(v.swatchColor!))
            if (hexToColor(v.swatchColor) case final color?)
              _Swatch(
                color: color,
                inStock: product.variants.any(
                  (variant) =>
                      variant.availableForSale &&
                      variant.selectedOptions.any(
                        (o) => o.name == opt.name && o.value == v.name,
                      ),
                ),
              ),
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final swatches = _swatchesFor(product);
    if (swatches.isEmpty) return const SizedBox.shrink();
    // The color the card is showing always comes first, so it is never
    // hidden behind "+N".
    final current = swatches.indexWhere((s) => s.handle == product.handle);
    if (current > 0) swatches.insert(0, swatches.removeAt(current));
    final visible = swatches.take(_maxVisible).toList();
    final extra = swatches.length - visible.length;
    return Row(
      children: [
        for (final swatch in visible)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: swatch.inStock != null || swatch.handle == null
                ? _tile(swatch, swatch.inStock ?? true)
                : FutureBuilder<ColorSwatchInfo?>(
                    future: ShopifyStorefrontService.instance
                        .getColorSwatchInfo(swatch.handle!),
                    // Shown as in stock until known, or if it can't be checked.
                    builder: (_, snap) =>
                        _tile(swatch, snap.data?.available ?? true),
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

  Widget _tile(_Swatch swatch, bool inStock) {
    final isCurrent = swatch.handle == product.handle;
    final imageUrl = swatch.imageUrl;
    final canTap =
        onSelectColor != null && inStock && swatch.handle != null && !isCurrent;
    return GestureDetector(
      onTap: canTap ? () => onSelectColor!(swatch.handle!) : null,
      child: SoldOutStrike(
        soldOut: !inStock,
        child: Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            // An image swatch stays light grey until its image arrives.
            color: imageUrl != null ? AppColors.fieldFill : swatch.color,
            borderRadius: BorderRadius.circular(3),
          ),
          // A thin outline on every swatch, drawn over the image too, so
          // white and light colors don't vanish on the white card. The color
          // the card is showing gets a dark one.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isCurrent
                  ? AppColors.primary
                  : AppColors.border,
              width: 1,
            ),
          ),
          child: imageUrl == null
              ? null
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  // The swatch CDN sends no CORS headers, so a browser
                  // build can't read the image's pixels; fall back to a
                  // plain <img> element, as the website itself uses.
                  // Ignored on Android/iOS.
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  errorBuilder: (_, _, _) => ColoredBox(color: swatch.color),
                ),
        ),
      ),
    );
  }
}

/// One square in the row: the group's custom color chip when it has one,
/// else a solid [color].
class _Swatch {
  const _Swatch({
    required this.color,
    this.handle,
    this.imageUrl,
    this.inStock,
  });

  final Color color;

  /// The color's own product, for Variant King group swatches.
  final String? handle;

  /// The group's custom color chip image, shown instead of [color].
  final String? imageUrl;

  /// Null when not known yet (another product in the color group).
  final bool? inStock;
}
