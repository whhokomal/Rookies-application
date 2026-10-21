import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/services/shopify_api.dart';
import 'package:rookies_jeans/models/auth_model.dart';
import 'package:rookies_jeans/models/shopify_customer_model.dart';

class ShopifyAuthService {
  ShopifyAuthService._();
  static final ShopifyAuthService instance = ShopifyAuthService._();

  static const String _customerTokenKey = 'shopify_customer_access_token';
  static const String _customerTokenExpiryKey = 'shopify_customer_access_token_expiry';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String get _endpoint => ShopifyConstants.storefrontEndpoint;

  void _log(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  String _maskToken(String? token) {
    if (token == null || token.isEmpty) return 'null';
    if (token.length <= 8) return '********';
    return '${token.substring(0, 4)}****${token.substring(token.length - 4)}';
  }

  Future<ShopifyAuthResult> login({
    required String email,
    required String password,
  }) async {
    _log('AUTH LOGIN START -> email: $email');
    _log('AUTH ENDPOINT -> $_endpoint');

    const String mutation = r'''
      mutation customerAccessTokenCreate($input: CustomerAccessTokenCreateInput!) {
        customerAccessTokenCreate(input: $input) {
          customerAccessToken {
            accessToken
            expiresAt
          }
          customerUserErrors {
            field
            message
            code
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(
        mutation,
        variables: {
          'input': {
            'email': email.trim(),
            'password': password,
          }
        },
      );

      _log('AUTH LOGIN STATUS -> ${res.statusCode}');

      final Map<String, dynamic> decoded = res.body;

      if (kDebugMode) {
        _log('AUTH LOGIN JSON -> ${jsonEncode(decoded)}');
      }

      if (res.statusCode != 200) {
        _log('AUTH LOGIN FAILED -> HTTP ${res.statusCode}');
        return ShopifyAuthResult(
          success: false,
          message: 'Login failed. HTTP ${res.statusCode}',
        );
      }

      if (decoded['errors'] != null) {
        _log('AUTH GRAPHQL ERROR -> ${decoded['errors']}');
        return ShopifyAuthResult(
          success: false,
          message: decoded['errors'][0]['message'] ?? 'Something went wrong.',
        );
      }

      final data = decoded['data']?['customerAccessTokenCreate'];
      if (data == null) {
        _log('AUTH LOGIN FAILED -> data.customerAccessTokenCreate is null');
        return ShopifyAuthResult(
          success: false,
          message: 'Invalid server response.',
        );
      }

      final List errors = data['customerUserErrors'] ?? [];
      if (errors.isNotEmpty) {
        _log('AUTH CUSTOMER USER ERRORS -> $errors');
        return ShopifyAuthResult(
          success: false,
          message: errors.first['message'] ?? 'Invalid email or password.',
        );
      }

      final tokenData = data['customerAccessToken'];
      final String? accessToken = tokenData?['accessToken'];
      final String? expiresAt = tokenData?['expiresAt'];

      _log('AUTH TOKEN RECEIVED -> ${_maskToken(accessToken)}');
      _log('AUTH TOKEN EXPIRES -> $expiresAt');

      if (accessToken == null || accessToken.isEmpty) {
        _log('AUTH LOGIN FAILED -> accessToken missing');
        return ShopifyAuthResult(
          success: false,
          message: 'Customer token not found.',
        );
      }

      return await signInWithToken(
        accessToken: accessToken,
        expiresAt: expiresAt,
      );
    } catch (e, stack) {
      _log('AUTH LOGIN EXCEPTION -> $e');
      _log('AUTH LOGIN STACK -> $stack');
      return ShopifyAuthResult(
        success: false,
        message: kFriendlyNetworkError,
      );
    }
  }

  /// Saves a customer access token obtained elsewhere (email/password login
  /// above, or phone OTP via OtpAuthService) and loads the customer.
  Future<ShopifyAuthResult> signInWithToken({
    required String accessToken,
    String? expiresAt,
  }) async {
    await _storage.write(key: _customerTokenKey, value: accessToken);
    await _storage.write(key: _customerTokenExpiryKey, value: expiresAt ?? '');

    _log('AUTH TOKEN SAVED -> secure storage');

    final customer = await getCurrentCustomer();

    _log('AUTH LOGIN SUCCESS -> customer: ${customer?.toJson()}');

    return ShopifyAuthResult(
      success: true,
      message: 'Login successful',
      accessToken: accessToken,
      expiresAt: expiresAt,
      customer: customer,
    );
  }

  Future<ShopifyAuthResult> recoverPassword({
    required String email,
  }) async {
    _log('AUTH RECOVER START -> email: $email');
    _log('AUTH ENDPOINT -> $_endpoint');

    const String mutation = r'''
      mutation customerRecover($email: String!) {
        customerRecover(email: $email) {
          customerUserErrors {
            field
            message
            code
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(
        mutation,
        variables: {
          'email': email.trim(),
        },
      );

      _log('AUTH RECOVER STATUS -> ${res.statusCode}');

      final Map<String, dynamic> decoded = res.body;

      if (kDebugMode) {
        _log('AUTH RECOVER JSON -> ${jsonEncode(decoded)}');
      }

      if (res.statusCode != 200) {
        _log('AUTH RECOVER FAILED -> HTTP ${res.statusCode}');
        return ShopifyAuthResult(
          success: false,
          message: 'Request failed. HTTP ${res.statusCode}',
        );
      }

      if (decoded['errors'] != null) {
        _log('AUTH RECOVER GRAPHQL ERROR -> ${decoded['errors']}');
        return ShopifyAuthResult(
          success: false,
          message: decoded['errors'][0]['message'] ?? 'Something went wrong.',
        );
      }

      final data = decoded['data']?['customerRecover'];
      if (data == null) {
        _log('AUTH RECOVER FAILED -> data.customerRecover is null');
        return ShopifyAuthResult(
          success: false,
          message: 'Invalid server response.',
        );
      }

      final List errors = data['customerUserErrors'] ?? [];
      if (errors.isNotEmpty) {
        _log('AUTH RECOVER CUSTOMER USER ERRORS -> $errors');
        return ShopifyAuthResult(
          success: false,
          message: errors.first['message'] ?? 'Could not process that request.',
        );
      }

      _log('AUTH RECOVER SUCCESS -> recovery email dispatched (if account exists)');

      return ShopifyAuthResult(
        success: true,
        message:
            'If an account exists for that email, a password reset link has been sent.',
      );
    } catch (e, stack) {
      _log('AUTH RECOVER EXCEPTION -> $e');
      _log('AUTH RECOVER STACK -> $stack');
      return ShopifyAuthResult(
        success: false,
        message: kFriendlyNetworkError,
      );
    }
  }

  Future<ShopifyCustomer?> getCurrentCustomer() async {
    final token = await _storage.read(key: _customerTokenKey);

    _log('CUSTOMER FETCH START -> token: ${_maskToken(token)}');

    if (token == null || token.isEmpty) {
      _log('CUSTOMER FETCH STOP -> token not found');
      return null;
    }

    const String query = r'''
      query getCustomer($customerAccessToken: String!) {
        customer(customerAccessToken: $customerAccessToken) {
          id
          firstName
          lastName
          email
          phone
          acceptsMarketing
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(
        query,
        variables: {
          'customerAccessToken': token,
        },
      );

      _log('CUSTOMER FETCH STATUS -> ${res.statusCode}');

      final Map<String, dynamic> decoded = res.body;

      if (kDebugMode) {
        _log('CUSTOMER FETCH JSON -> ${jsonEncode(decoded)}');
      }

      if (res.statusCode != 200) {
        _log('CUSTOMER FETCH FAILED -> HTTP ${res.statusCode}');
        return null;
      }

      if (decoded['errors'] != null) {
        _log('CUSTOMER FETCH GRAPHQL ERROR -> ${decoded['errors']}');
        return null;
      }

      final customerJson = decoded['data']?['customer'];
      if (customerJson == null) {
        _log('CUSTOMER FETCH FAILED -> customer is null');
        return null;
      }

      final customer = ShopifyCustomer.fromJson(customerJson);
      _log('CUSTOMER FETCH SUCCESS -> ${customer.toJson()}');
      return customer;
    } catch (e, stack) {
      _log('CUSTOMER FETCH EXCEPTION -> $e');
      _log('CUSTOMER FETCH STACK -> $stack');
      return null;
    }
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: _customerTokenKey);
    final expiry = await _storage.read(key: _customerTokenExpiryKey);

    if (token == null || token.isEmpty) {
      _log('AUTH IS LOGGED IN -> false (no token)');
      return false;
    }

    if (expiry != null && expiry.isNotEmpty) {
      final expiryDate = DateTime.tryParse(expiry);
      if (expiryDate != null && DateTime.now().isAfter(expiryDate)) {
        _log('AUTH IS LOGGED IN -> false (token expired)');
        await logout();
        return false;
      }
    }

    _log('AUTH IS LOGGED IN -> true');
    return true;
  }

  Future<void> logout() async {
    _log('AUTH LOGOUT START');
    final token = await _storage.read(key: _customerTokenKey);
    if (token != null && token.isNotEmpty) {
      // Revoke it at Shopify too, so a copied token stops working. Best
      // effort: signing out on the device must not depend on the network.
      try {
        await ShopifyGraphQL.post(
          r'''
            mutation customerAccessTokenDelete($token: String!) {
              customerAccessTokenDelete(customerAccessToken: $token) {
                deletedAccessToken
              }
            }
          ''',
          variables: {'token': token},
        );
      } catch (e) {
        _log('AUTH LOGOUT REVOKE FAILED -> $e');
      }
    }
    await _storage.delete(key: _customerTokenKey);
    await _storage.delete(key: _customerTokenExpiryKey);
    _log('AUTH LOGOUT DONE');
  }

  Future<String?> getSavedCustomerToken() async {
    final token = await _storage.read(key: _customerTokenKey);
    _log('AUTH SAVED TOKEN -> ${_maskToken(token)}');
    return token;
  }

   Future<ShopifyAuthResult> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? phone,
    bool acceptsMarketing = false,
  }) async {
    _log('AUTH REGISTER START -> email: $email');
    _log('AUTH ENDPOINT -> $_endpoint');
 
    const String mutation = r'''
      mutation customerCreate($input: CustomerCreateInput!) {
        customerCreate(input: $input) {
          customer {
            id
            firstName
            lastName
            email
            phone
          }
          customerUserErrors {
            field
            message
            code
          }
        }
      }
    ''';
 
    final Map<String, dynamic> input = {
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'email': email.trim(),
      'password': password,
      'acceptsMarketing': acceptsMarketing,
      // Shopify requires E.164 format (+919876543210). An invalid phone
      // fails the whole mutation, so only send it when provided.
      if (phone != null && phone.trim().isNotEmpty)
        'phone': _toE164(phone.trim()),
    };
 
    try {
      final res = await ShopifyGraphQL.post(
        mutation,
        variables: {'input': input},
      );
 
      _log('AUTH REGISTER STATUS -> ${res.statusCode}');
 
      final Map<String, dynamic> decoded = res.body;
 
      if (kDebugMode) {
        _log('AUTH REGISTER JSON -> ${jsonEncode(decoded)}');
      }
 
      if (res.statusCode != 200) {
        _log('AUTH REGISTER FAILED -> HTTP ${res.statusCode}');
        return ShopifyAuthResult(
          success: false,
          message: 'Registration failed. HTTP ${res.statusCode}',
        );
      }
 
      if (decoded['errors'] != null) {
        _log('AUTH REGISTER GRAPHQL ERROR -> ${decoded['errors']}');
        return ShopifyAuthResult(
          success: false,
          message: decoded['errors'][0]['message'] ?? 'Something went wrong.',
        );
      }
 
      final data = decoded['data']?['customerCreate'];
      if (data == null) {
        _log('AUTH REGISTER FAILED -> data.customerCreate is null');
        return ShopifyAuthResult(
          success: false,
          message: 'Invalid server response.',
        );
      }
 
      final List errors = data['customerUserErrors'] ?? [];
      if (errors.isNotEmpty) {
        _log('AUTH REGISTER CUSTOMER USER ERRORS -> $errors');
 
        final first = errors.first as Map<String, dynamic>;
        final String? code = first['code']?.toString();
 
        // Friendlier messages for Shopify's most common error codes
        String message;
        switch (code) {
          case 'TAKEN':
            message =
                'An account with this email already exists. Try signing in.';
            break;
          case 'TOO_SHORT':
            message = 'Password is too short (minimum 8 characters).';
            break;
          case 'TOO_LONG':
            message = 'Password is too long (maximum 40 characters).';
            break;
          case 'CUSTOMER_DISABLED':
            message =
                'Account created. Please check your email to activate it.';
            break;
          default:
            message = first['message']?.toString() ?? 'Registration failed.';
        }
 
        return ShopifyAuthResult(success: false, message: message);
      }
 
      final customerJson = data['customer'];
      if (customerJson == null) {
        _log('AUTH REGISTER FAILED -> customer is null');
        return ShopifyAuthResult(
          success: false,
          message: 'Registration failed. Please try again.',
        );
      }
 
      _log('AUTH REGISTER SUCCESS -> customer created, attempting auto-login');
 
      // ------------------------------------------------------------------
      // Auto-login so the token is saved via the same login() flow.
      //
      // NOTE: if your store has email verification enabled for classic
      // customer accounts, the customer is created DISABLED and login
      // fails until they activate via email. We handle that below.
      // ------------------------------------------------------------------
      final loginResult = await login(email: email, password: password);
 
      if (loginResult.success) {
        _log('AUTH REGISTER AUTO-LOGIN SUCCESS');
        return loginResult;
      }
 
      _log('AUTH REGISTER AUTO-LOGIN FAILED -> ${loginResult.message}');
 
      // Account exists but couldn't log in (usually needs activation).
      return ShopifyAuthResult(
        success: true,
        message:
            'Account created! Please check your email to activate it, then sign in.',
        customer: ShopifyCustomer.fromJson(customerJson),
      );
    } catch (e, stack) {
      _log('AUTH REGISTER EXCEPTION -> $e');
      _log('AUTH REGISTER STACK -> $stack');
      return ShopifyAuthResult(
        success: false,
        message: kFriendlyNetworkError,
      );
    }
  }
 
  /// Normalizes a phone number into E.164 format for Shopify.
  /// Defaults to India (+91) for 10-digit numbers — change if needed.
  String _toE164(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.length == 10) return '+91$digits';
    return '+$digits';
  }
}