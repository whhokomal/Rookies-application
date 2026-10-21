import 'package:flutter/material.dart';
import 'package:rookies_jeans/constants/shopify_constants.dart';

class PriceText extends StatelessWidget {
  final String amount;
  final String currencyCode;
  final double fontSize;
  final Color color;
  final String? amountFontFamily;
  final FontWeight? fontWeight;
  final TextDecoration? decoration;

  const PriceText(
    this.amount, {
    super.key,
    required this.currencyCode,
    required this.fontSize,
    required this.color,
    this.amountFontFamily,
    this.fontWeight,
    this.decoration,
  });

  static const String _fRupee = ShopifyConstants.fontRupee;

  @override
  Widget build(BuildContext context) {
    final isInr = currencyCode == 'INR';
    return RichText(
      text: TextSpan(
        children: [
          if (isInr)
            TextSpan(
              text: '₹',
              style: TextStyle(
                fontFamily: _fRupee,
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color,
                decoration: decoration,
                decorationColor: color,
              ),
            ),
          TextSpan(
            text: amount,
            style: TextStyle(
              // Archivo unless the caller picks another font.
              fontFamily: amountFontFamily ?? ShopifyConstants.fontBody,
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              decoration: decoration,
              decorationColor: color,
            ),
          ),
        ],
      ),
    );
  }
}

class SavedAmountText extends StatelessWidget {
  final String savedAmount;
  final String currencyCode;
  final double fontSize;
  final Color color;
  final String? fontFamily;
  final FontWeight? fontWeight;
  final String label;

  const SavedAmountText(
    this.savedAmount, {
    super.key,
    required this.currencyCode,
    required this.fontSize,
    required this.color,
    this.fontFamily,
    this.fontWeight,
    this.label = 'Save ',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
          ),
        ),
        PriceText(
          savedAmount,
          currencyCode: currencyCode,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          amountFontFamily: fontFamily,
        ),
      ],
    );
  }
}