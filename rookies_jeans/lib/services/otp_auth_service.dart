import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/models/auth_model.dart';
import 'package:rookies_jeans/services/shopify_auth_service.dart';

/// Result of verifying an OTP. Either the customer is signed in ([auth] set),
/// or the phone is verified but name + email are needed to finish creating
/// the account ([needsProfile], use [verificationToken]).
class OtpVerifyResult {
  final ShopifyAuthResult? auth;
  final bool needsProfile;
  final String? verificationToken;
  final String firstName;
  final String lastName;
  final String? error;

  const OtpVerifyResult({
    this.auth,
    this.needsProfile = false,
    this.verificationToken,
    this.firstName = '',
    this.lastName = '',
    this.error,
  });

  bool get success => auth?.success == true;
}

/// Phone OTP login.
///
/// 1. Send / resend / verify the OTP through the website's existing MSG91
///    OTPLOGIN widget, calling the same web widget endpoints its script uses
///    (no separate mobile widget; nothing on the site changes) — widget ID +
///    token are public and safe to ship in the app.
/// 2. Hand MSG91's access token to the otp_login_worker, which checks it with
///    MSG91 and returns a Shopify customer access token — stored exactly like
///    an email/password login.
class OtpAuthService {
  OtpAuthService._();
  static final OtpAuthService instance = OtpAuthService._();

  static const Duration _timeout = Duration(seconds: 20);

  // MSG91 retry channel codes — sent as strings, exactly like the website's
  // widget script does.
  static const String _channelSms      = '11';
  static const String _channelWhatsApp = '12';

  static const String _msg91WidgetApi = 'https://control.msg91.com/api/v5/widget';

  /// MSG91 request id for the OTP currently in flight.
  String? _reqId;

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

  /// "+919876543210" -> "919876543210" (MSG91 wants no "+").
  String _msg91Identifier(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  bool _isReviewPhone(String phone) => phone == ShopifyConstants.reviewPhone;

  /// Returns null on success, otherwise a user-facing error message.
  Future<String?> sendOtp(String phone) async {
    _reqId = null;
    if (_isReviewPhone(phone)) {
      _reqId = 'review';
      return null;
    }
    final res = await _msg91('sendOtp', {
      'identifier': _msg91Identifier(phone),
    });
    if (res.error != null) return res.error;

    _reqId = res.body['message']?.toString();
    if (_reqId == null || _reqId!.isEmpty) return 'Could not send OTP. Please try again.';
    return null;
  }

  /// [channel] is 'text' (SMS) or 'whatsapp'.
  Future<String?> resendOtp(String phone, {String channel = 'text'}) async {
    if (_reqId == null || _isReviewPhone(phone)) return sendOtp(phone);
    final res = await _msg91('retryOtp', {
      'reqId': _reqId,
      'retryChannel': channel == 'whatsapp' ? _channelWhatsApp : _channelSms,
    });
    return res.error;
  }

  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    if (_reqId == null) {
      return const OtpVerifyResult(error: 'Please request an OTP first.');
    }

    final Map<String, dynamic> proof;
    if (_isReviewPhone(phone)) {
      proof = {'reviewOtp': otp};
    } else {
      final verified = await _msg91('verifyOtp', {'reqId': _reqId, 'otp': otp});
      if (verified.error != null) return OtpVerifyResult(error: verified.error);

      final msg91Token = verified.body['message']?.toString() ??
          verified.body['access-token']?.toString();
      if (msg91Token == null || msg91Token.isEmpty) {
        return const OtpVerifyResult(error: 'Invalid response from OTP service.');
      }
      proof = {'accessToken': msg91Token};
    }

    final res = await _worker('/login', {'phone': phone, ...proof});
    if (res.error != null) return OtpVerifyResult(error: res.error);

    _reqId = null;
    if (res.body['status'] == 'profile_required') {
      return OtpVerifyResult(
        needsProfile: true,
        verificationToken: res.body['verificationToken'] as String?,
        firstName: res.body['firstName'] as String? ?? '',
        lastName: res.body['lastName'] as String? ?? '',
      );
    }
    return _signIn(res.body);
  }

  Future<OtpVerifyResult> completeProfile({
    required String verificationToken,
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    final res = await _worker('/complete', {
      'verificationToken': verificationToken,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
    });
    if (res.error != null) return OtpVerifyResult(error: res.error);
    return _signIn(res.body);
  }

  /// Permanently deletes the signed-in customer's Shopify account through the
  /// otp_login_worker (Storefront has no customer delete; the worker holds
  /// the Admin token). Required in-app by the App Store and Google Play.
  /// Returns null on success, otherwise a user-facing error message. The
  /// caller signs out afterwards.
  Future<String?> deleteAccount() async {
    final token = await ShopifyAuthService.instance.getSavedCustomerToken();
    if (token == null || token.isEmpty) {
      return 'Your session has expired. Please sign in again.';
    }
    final res = await _worker('/delete-account', {'customerAccessToken': token});
    return res.error;
  }

  Future<OtpVerifyResult> _signIn(Map<String, dynamic> body) async {
    final token = body['accessToken'] as String?;
    if (body['status'] != 'signed_in' || token == null || token.isEmpty) {
      return const OtpVerifyResult(error: 'Invalid server response.');
    }
    final auth = await ShopifyAuthService.instance.signInWithToken(
      accessToken: token,
      expiresAt: body['expiresAt'] as String?,
    );
    return OtpVerifyResult(auth: auth);
  }

  // ---------------------------------------------------------------------------
  // HTTP

  /// MSG91 web OTP widget endpoint ([action] is sendOtp / retryOtp /
  /// verifyOtp) — the same requests the website's widget script sends.
  /// Success is `{"type": "success", "message": ...}` (sendOtp: the request
  /// id; verifyOtp: the access token); failures are
  /// `{"type": "error", "message": "..."}`.
  Future<({Map<String, dynamic> body, String? error})> _msg91(
    String action,
    Map<String, dynamic> payload,
  ) async {
    final res = await _post(
      '$_msg91WidgetApi/$action',
      {
        'widgetId': ShopifyConstants.msg91WidgetId,
        'tokenAuth': ShopifyConstants.msg91TokenAuth,
        ...payload,
      },
      headers: {'tokenAuth': ShopifyConstants.msg91TokenAuth},
    );
    _log('MSG91 $action -> ${res.body['type']}: ${res.body['message']}');
    if (res.error != null) return res;

    if (res.body['type'] != 'success') {
      return (
        body: res.body,
        error: res.body['message']?.toString() ?? 'OTP request failed.',
      );
    }
    return res;
  }

  Future<({Map<String, dynamic> body, String? error})> _worker(
    String path,
    Map<String, dynamic> payload,
  ) =>
      _post('${ShopifyConstants.otpLoginUrl}$path', payload);

  Future<({Map<String, dynamic> body, String? error})> _post(
    String url,
    Map<String, dynamic> payload, {
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url);
    _log('OTP ${uri.path} START');

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              ...headers,
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      _log('OTP ${uri.path} STATUS -> ${response.statusCode}');

      Map<String, dynamic> body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        body = const {};
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return (
          body: body,
          error: (body['error'] ?? body['message'])?.toString() ??
              'Request failed (${response.statusCode}).',
        );
      }
      return (body: body, error: null);
    } on TimeoutException {
      return (
        body: const <String, dynamic>{},
        error: 'The request timed out. Please try again.${_debugUrl(uri)}',
      );
    } catch (e) {
      _log('OTP ${uri.path} EXCEPTION -> $e');
      return (
        body: const <String, dynamic>{},
        error: 'Could not reach the server. Check your connection.${_debugUrl(uri)}',
      );
    }
  }

  // Debug builds name the host they tried, so a wrong URL is obvious.
  String _debugUrl(Uri uri) => kDebugMode ? '\n(${uri.origin})' : '';
}
