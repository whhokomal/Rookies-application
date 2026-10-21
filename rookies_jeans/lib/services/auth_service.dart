import 'package:flutter/foundation.dart';
import 'package:rookies_jeans/models/shopify_customer_model.dart';
import 'package:rookies_jeans/services/address_service.dart';
import 'package:rookies_jeans/services/shopify_auth_service.dart';

/// Who is signed in, for the UI. The customer token itself lives in
/// [ShopifyAuthService]; a saved, unexpired token means signed in, even when
/// the name and email couldn't be loaded yet (e.g. offline at launch).
class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._();
  AuthService._();

  bool _isLoggedIn = false;
  String _firstName = '';
  String _lastName  = '';
  String _email     = '';
  String _phone     = '';

  bool   get isLoggedIn => _isLoggedIn;
  String get firstName  => _firstName;
  String get lastName   => _lastName;
  String get email      => _email;
  String get phone      => _phone;

  String get initials {
    final f = _firstName.isNotEmpty ? _firstName[0].toUpperCase() : '';
    final l = _lastName.isNotEmpty  ? _lastName[0].toUpperCase()  : '';
    return '$f$l';
  }

  Future<void> initialize() async {
    final loggedIn = await ShopifyAuthService.instance.isLoggedIn();
    if (!loggedIn) return;
    _isLoggedIn = true;
    notifyListeners();
    await refreshProfile();
  }

  /// Loads the name and email for the saved token. Keeps the customer
  /// signed in if this fails; the details fill in on the next try.
  Future<void> refreshProfile() async {
    final customer = await ShopifyAuthService.instance.getCurrentCustomer();
    if (customer == null) return;
    _setCustomer(customer);
    notifyListeners();
  }

  /// Marks the customer as signed in after a successful login. [customer]
  /// is null when the token was saved but the details couldn't be loaded.
  void signIn(ShopifyCustomer? customer) {
    _isLoggedIn = true;
    if (customer != null) {
      _setCustomer(customer);
    } else {
      refreshProfile();
    }
    notifyListeners();
  }

  void _setCustomer(ShopifyCustomer customer) {
    _firstName = customer.firstName ?? '';
    _lastName  = customer.lastName  ?? '';
    _email     = customer.email     ?? '';
    _phone     = customer.phone     ?? '';
  }

  /// Saves a new name and phone number to the Shopify account. Returns null
  /// on success, otherwise a message to show the customer.
  Future<String?> updateProfile({
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    final result = await ShopifyAuthService.instance.updateProfile(
      firstName: firstName,
      lastName: lastName,
      phone: phone,
    );
    if (!result.success) return result.message ?? 'Could not update your profile.';
    if (result.customer != null) {
      _setCustomer(result.customer!);
    } else {
      _firstName = firstName.trim();
      _lastName  = lastName.trim();
    }
    notifyListeners();
    return null;
  }

  /// Signs out on this device and at Shopify, and drops this customer's
  /// data so the next person to sign in doesn't see it.
  Future<void> signOut() async {
    await ShopifyAuthService.instance.logout();
    AddressService.instance.clearAddresses();
    _firstName  = '';
    _lastName   = '';
    _email      = '';
    _phone      = '';
    _isLoggedIn = false;
    notifyListeners();
  }
}
