import 'package:flutter/material.dart';
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/services/theme_service.dart';

export 'package:rookies_jeans/services/theme_service.dart';

/// App-wide color constants. Every value below reads the current theme
/// selection from [ThemeService], so switching the theme in Profile ->
/// Theme Appearance changes these for every screen that references them.
class AppColors {
  AppColors._();

  static bool get _dark => ThemeService.instance.isDark;

  static Color get primary =>
      _dark ? Colors.white : const Color(ShopifyConstants.primaryColorHex);

  /// Color for text/icons drawn on TOP of a [primary]-colored surface
  /// (solid buttons, snackbars, badges). Always the inverse of [primary] so
  /// it stays readable in both themes — [primary] itself flips from
  /// near-black to white between light and dark, so content sitting on it
  /// must flip the other way.
  static Color get onPrimary => _dark ? const Color(0xFF121212) : Colors.white;
  static Color get accentOrange => const Color(ShopifyConstants.accentOrangeHex);
  static Color get bg => _dark ? const Color(0xFF121212) : const Color(ShopifyConstants.bgColorHex);
  static Color get card => _dark ? const Color(0xFF1E1E1E) : const Color(ShopifyConstants.cardColorHex);
  static Color get secondaryText =>
      _dark ? const Color(0xFFB0B0B0) : const Color(ShopifyConstants.secondaryTextHex);
  static Color get border => _dark ? const Color(0xFF2C2C2C) : const Color(ShopifyConstants.borderColorHex);

  /// Background for text fields / filled inputs. Distinct from [card] so
  /// inputs still read as "sunken" against a card in both themes.
  static Color get fieldFill => _dark ? const Color(0xFF2A2A2A) : const Color(0xfffafafa);

  /// Placeholder/hint text inside inputs and disabled-looking icons.
  static Color get hint => _dark ? const Color(0xFF8A8A8A) : const Color(0xff9a9a9a);

  static const Color danger  = Color(0xFFD32F2F);
  static const Color success = Color(0xFF2E7D32);
  static const Color muted   = Color(0xFF9A9A9A);
}

class AppFonts {
  AppFonts._();

  static const String heading    = ShopifyConstants.fontHeading;
  static const String subheading = ShopifyConstants.fontSubheading;
  static const String body       = ShopifyConstants.fontBody;
  static const String accent     = ShopifyConstants.fontAccent;
  static const String bold     = ShopifyConstants.fontBodyBold;
  static const String alteBold = ShopifyConstants.fontAlteBold;
  static const String number   = ShopifyConstants.fontNumber;
  static const String rupee    = ShopifyConstants.fontRupee;
}

/// Corner rounding shared by the app's action buttons (Add to Cart, Buy
/// Now, Checkout, Save, ...).
class AppShapes {
  AppShapes._();

  static const double buttonRadius = 8;
  static const BorderRadius buttonBorderRadius =
      BorderRadius.all(Radius.circular(buttonRadius));
  static const RoundedRectangleBorder button =
      RoundedRectangleBorder(borderRadius: buttonBorderRadius);
}

class AppLayout {
  AppLayout._();

  static const double maxContentNarrow = 640;
  static const double maxContentMedium = 720;
}

class Responsive {
  const Responsive._(
    this.size,
    this.padding,
    this.baseW,
    this.baseH,
    this.minScale,
    this.maxScale,
  );

  final Size size;
  final EdgeInsets padding;
  final double baseW;
  final double baseH;
  final double minScale;
  final double maxScale;

  factory Responsive.of(
    BuildContext context, {
    double baseW = 390,
    double baseH = 844,
    double minScale = 0.85,
    double maxScale = 1.35,
  }) {
    final mq = MediaQuery.of(context);
    return Responsive._(
      mq.size,
      mq.padding,
      baseW,
      baseH,
      minScale,
      maxScale,
    );
  }

  double get width => size.width;
  double get height => size.height;

  double get safeWidth =>
   
      (width - padding.left - padding.right).clamp(0.0, width);

  bool get isTablet => width >= 600 && width < 1024;
  bool get isDesktop => width >= 1024;

  double get widthScale =>
      (width / baseW).clamp(minScale, maxScale).toDouble();
  double get heightScale =>
      (height / baseH).clamp(minScale, maxScale).toDouble();

  double s(double base) => base * widthScale;

  double sp(double base) => base * widthScale;

  double dp(double base) => base * widthScale;

  double vp(double base) => base * heightScale;
}

class AppToast {
  AppToast._();

  /// A floating SnackBar in Roboto Mono, matching the "added to cart"
  /// messages (a native toast can't use the app's fonts).
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontFamily: AppFonts.accent,
            color: isError ? Colors.white : null,
          ),
        ),
        backgroundColor: isError ? AppColors.danger : null,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
  }
}
