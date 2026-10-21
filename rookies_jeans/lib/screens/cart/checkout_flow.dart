import 'package:flutter/material.dart';
import 'package:rookies_jeans/models/address_model.dart';
import 'package:rookies_jeans/models/cart_model.dart';
import 'package:rookies_jeans/screens/authentication/login_screen.dart';
import 'package:rookies_jeans/screens/cart/checkout.dart';
import 'package:rookies_jeans/screens/profile/address_book.dart';
import 'package:rookies_jeans/services/address_service.dart';
import 'package:rookies_jeans/services/shopify_auth_service.dart';

/// Runs the full checkout flow for [lines]: sign in if needed, pick a
/// delivery address, then open the GoKwik checkout.
///
/// Returns true when the order was placed, false/null when the user backed
/// out at any step. Shared by the cart's Checkout and the product page's
/// Buy Now.
Future<bool> runCheckoutFlow(
  BuildContext context, {
  required List<ShopifyCartLine> lines,
}) async {
  final navigator = Navigator.of(context);

  final isLoggedIn = await ShopifyAuthService.instance.isLoggedIn();
  if (!isLoggedIn) {
    final loggedInNow = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(isCheckoutFlow: true),
      ),
    );
    if (loggedInNow != true || !context.mounted) return false;
  }

  await AddressService.instance.fetchAddresses();
  if (!context.mounted) return false;

  // Always show the picker: it lists saved addresses, or prompts the
  // user to add one when none exist.
  final selectedAddress = await navigator.push<ShopifyAddress>(
    MaterialPageRoute(
      builder: (_) => const AddressBookScreen(pickMode: true),
      fullscreenDialog: true,
    ),
  );
  if (selectedAddress == null || !context.mounted) return false;

  if (!selectedAddress.isDefault) {
    await AddressService.instance.setDefaultAddress(selectedAddress.id);
    if (!context.mounted) return false;
  }

  // Checkout runs through GoKwik; Shopify's native checkoutUrl is not
  // used (its payment providers are disabled). Pushed on the root navigator
  // so it covers the bottom nav bar instead of opening inside the cart tab.
  final result = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      builder: (_) => CheckoutWebView(lines: lines),
      fullscreenDialog: true,
    ),
  );
  return result == true;
}
