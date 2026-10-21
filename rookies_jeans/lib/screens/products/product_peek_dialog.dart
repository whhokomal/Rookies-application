import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rookies_jeans/utils/format.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/models/product_model.dart';

class ProductPeekDialog extends StatefulWidget {
  final ShopifyProduct product;
  final Color primary;
  final Color onPrimary;
  final Color cardColor;
  final Color bgColor;
  final Color borderColor;
  final Color secondaryTxt;
  final String numberFont;
  final String rupeeFont;
  final String bodyFont;
  final Future<void> Function(String variantId) onAddToCart;
  final VoidCallback onOpenDetail;

  const ProductPeekDialog({
    super.key,
    required this.product,
    required this.primary,
    required this.onPrimary,
    required this.cardColor,
    required this.bgColor,
    required this.borderColor,
    required this.secondaryTxt,
    required this.numberFont,
    required this.rupeeFont,
    required this.bodyFont,
    required this.onAddToCart,
    required this.onOpenDetail,
  });

  @override
  State<ProductPeekDialog> createState() => ProductPeekDialogState();
}

class ProductPeekDialogState extends State<ProductPeekDialog> {
  late final PageController _pageCtrl;
  int _currentPage = 0;
  String? _selectedVariantId;
  bool _isAddingToCart = false;

  List<_PeekOption> get _peekOptions {
    final product = widget.product;
    final result = <_PeekOption>[];

    for (final opt in product.options) {
      final name = opt.name.toUpperCase();
      if (name == 'COLOR' || name == 'COLOUR') continue;
      result.add(_PeekOption(
        label: opt.name,
        values: opt.values,
      ));
    }
    return result;
  }

  final Map<String, String> _selectedOptions = {};

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();

    final product = widget.product;
    if (product.variants.isNotEmpty) {
      final first = product.variants.first;
      _selectedVariantId = first.id;
      for (final so in first.selectedOptions) {
        _selectedOptions[so.name] = so.value;
      }
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _selectOption(String optionName, String value) {
    setState(() {
      _selectedOptions[optionName] = value;
    });
    for (final v in widget.product.variants) {
      final match = v.selectedOptions.every(
        (so) =>
            _selectedOptions[so.name] == null ||
            _selectedOptions[so.name] == so.value,
      );
      if (match) {
        setState(() => _selectedVariantId = v.id);
        break;
      }
    }
  }

  List<InlineSpan> _amountSpans({
    required num amount,
    required String currencyCode,
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    final isInr = currencyCode.toUpperCase() == 'INR';
    final symbol = isInr ? '₹' : '$currencyCode ';
    final symbolFont = isInr ? widget.rupeeFont : widget.bodyFont;

    return [
      TextSpan(
        text: symbol,
        style: TextStyle(
          fontFamily: symbolFont,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          decoration: decoration,
          decorationColor: decorationColor,
        ),
      ),
      TextSpan(
        text: formatInr(amount),
        style: TextStyle(
          fontFamily: widget.numberFont,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          decoration: decoration,
          decorationColor: decorationColor,
        ),
      ),
    ];
  }

  List<InlineSpan> _priceSpans(
    String text, {
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    String? currentFont;

    void flush() {
      if (buffer.isEmpty) return;
      spans.add(TextSpan(
        text: buffer.toString(),
        style: TextStyle(
          fontFamily: currentFont,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          decoration: decoration,
          decorationColor: decorationColor,
        ),
      ));
      buffer.clear();
    }

    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final isRupeeSymbol = char == '₹';
      final isDigitOrSeparator = RegExp(r'[0-9,.]').hasMatch(char);

      final font = isRupeeSymbol
          ? widget.rupeeFont
          : isDigitOrSeparator
              ? widget.numberFont
              : widget.bodyFont;

      if (font != currentFont) {
        flush();
        currentFont = font;
      }
      buffer.write(char);
    }
    flush();

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final images = product.imageUrls;
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;

    final dialogWidth = (screenWidth * 0.88).clamp(0.0, 460.0);
    final imageHeight =
        (dialogWidth * 1.1).clamp(0.0, screenHeight * 0.5);

    return Center(
      child: GestureDetector(
        onTap: widget.onOpenDetail,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: dialogWidth,
            constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
            decoration: BoxDecoration(
              color: widget.cardColor,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: imageHeight,
                    child: Stack(
                      children: [
                        PageView.builder(
                          controller: _pageCtrl,
                          itemCount: images.isEmpty ? 1 : images.length,
                          onPageChanged: (i) => setState(() => _currentPage = i),
                          itemBuilder: (_, i) {
                            if (images.isEmpty) {
                              return Container(color: widget.bgColor);
                            }
                            return CachedNetworkImage(
                              imageUrl: images[i],
                              fit: BoxFit.cover,
                              placeholder: (_, _) =>
                                  Container(color: widget.bgColor),
                              errorWidget: (_, _, _) =>
                                  Container(color: widget.bgColor),
                            );
                          },
                        ),
                        if (product.isOnSale)
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD32F2F),
                              ),
                              child: RichText(
                                text: TextSpan(
                                  children: _priceSpans(
                                    _discountPercent(product),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.open_in_new_rounded,
                                    color: Colors.white, size: 11),
                                SizedBox(width: 4),
                                Text(
                                  'View details',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (images.length > 1)
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                images.length.clamp(0, 8),
                                (i) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 3),
                                  width: i == _currentPage ? 16 : 6,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: i == _currentPage
                                        ? widget.primary
                                        : Colors.white.withValues(alpha: 0.65),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: GestureDetector(
                      onTap: () {},
                      child: Container(
                        color: widget.cardColor,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: AppFonts.body,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: widget.primary,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _peekPriceRow(product),
                              const SizedBox(height: 12),
                              ..._peekOptions.map((opt) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _peekOptionRow(opt),
                                  )),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: double.infinity,
                                height: 42,
                                child: ElevatedButton(
                                  onPressed: _isAddingToCart ||
                                          _selectedVariantId == null
                                      ? null
                                      : () async {
                                          setState(
                                              () => _isAddingToCart = true);
                                          await widget.onAddToCart(
                                              _selectedVariantId!);
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: widget.primary,
                                    foregroundColor: widget.onPrimary,
                                    shape: AppShapes.button,
                                    elevation: 0,
                                  ),
                                  child: _isAddingToCart
                                      ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: widget.onPrimary,
                                          ),
                                        )
                                      : Text(
                                          'ADD TO CART',
                                          style: TextStyle(
                                            color: widget.onPrimary,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _peekPriceRow(ShopifyProduct product) {
    if (!product.isOnSale) {
      return RichText(
        text: TextSpan(
          children: _amountSpans(
            amount: product.price,
            currencyCode: product.currencyCode,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: widget.primary,
          ),
        ),
      );
    }
    final saved = product.compareAtPrice! - product.price;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        RichText(
          text: TextSpan(
            children: _amountSpans(
              amount: product.compareAtPrice!,
              currencyCode: product.currencyCode,
              fontSize: 12,
              fontWeight: FontWeight.normal,
              color: widget.secondaryTxt,
              decoration: TextDecoration.lineThrough,
              decorationColor: widget.secondaryTxt,
            ),
          ),
        ),
        RichText(
          text: TextSpan(
            children: _amountSpans(
              amount: product.price,
              currencyCode: product.currencyCode,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: widget.primary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
          ),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Save ',
                  style: TextStyle(
                    fontFamily: widget.bodyFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color.fromARGB(255, 84, 184, 89),
                  ),
                ),
                ..._amountSpans(
                  amount: saved,
                  currencyCode: product.currencyCode,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color.fromARGB(255, 84, 184, 89),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _peekOptionRow(_PeekOption opt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          opt.label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: widget.secondaryTxt,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: opt.values.map((val) {
            final isSelected = _selectedOptions[opt.label] == val;
            return GestureDetector(
              onTap: () => _selectOption(opt.label, val),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? widget.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? widget.primary : widget.borderColor,
                    width: 1.2,
                  ),
                ),
                child: Text(
                  val,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? widget.onPrimary : widget.primary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _discountPercent(ShopifyProduct product) {
    if (product.compareAtPrice == null || product.compareAtPrice == 0) {
      return 'SALE';
    }
    final pct =
        ((1 - product.price / product.compareAtPrice!) * 100).round();
    return '$pct% OFF';
  }
}

class _PeekOption {
  final String label;
  final List<String> values;
  const _PeekOption({required this.label, required this.values});
}
