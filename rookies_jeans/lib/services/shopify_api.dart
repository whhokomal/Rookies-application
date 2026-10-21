import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:rookies_jeans/constants/shopify_constants.dart';

class ShopifyGraphQLResponse {
  final int statusCode;
  final Map<String, dynamic> body;

  const ShopifyGraphQLResponse(this.statusCode, this.body);

  bool get isOk => statusCode == 200;

  List<dynamic>? get errors => body['errors'] as List<dynamic>?;

  bool get hasErrors => errors != null;

  Map<String, dynamic>? get data => body['data'] as Map<String, dynamic>?;
}

class ShopifyGraphQL {
  ShopifyGraphQL._();

  /// Without a limit a request on a bad connection can spin forever.
  static const Duration timeout = Duration(seconds: 20);

  /// Throws on network failure or timeout. A reply that isn't JSON (e.g. an
  /// HTML 502 page during a sale) comes back as a response with `errors`
  /// set, so callers handle it like any other GraphQL error.
  static Future<ShopifyGraphQLResponse> post(
    String query, {
    Map<String, dynamic>? variables,
    String? tag,
  }) async {
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(ShopifyConstants.storefrontEndpoint),
            headers: ShopifyConstants.headers,
            body: jsonEncode({
              'query': query,
              'variables': ?variables,
            }),
          )
          .timeout(timeout);
    } catch (_) {
      _markFailed();
      rethrow;
    }

    if (tag != null) log(tag, '→ ${response.statusCode}');

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      decoded = {
        'errors': [
          {'message': 'Unexpected response (HTTP ${response.statusCode}).'}
        ],
      };
    }
    final result = ShopifyGraphQLResponse(response.statusCode, decoded);
    if (!result.isOk || result.hasErrors) _markFailed();
    return result;
  }

  static const Symbol _failureKey = #shopifyRequestFailed;

  static void _markFailed() {
    final flag = Zone.current[_failureKey];
    if (flag is _FailureFlag) flag.failed = true;
  }

  /// Marks the enclosing [trackFailures] call as failed without a request
  /// of its own (e.g. it reused another call's failed result).
  static void reportFailure() => _markFailed();

  /// Runs [body] and reports whether any Shopify request made inside it
  /// (directly or in nested calls) failed, so callers can avoid caching a
  /// fallback result that was produced by a network or API error. A failure
  /// is also passed on to any enclosing [trackFailures].
  static Future<({T value, bool failed})> trackFailures<T>(
    Future<T> Function() body,
  ) async {
    final flag = _FailureFlag();
    final value = await runZoned(body, zoneValues: {_failureKey: flag});
    if (flag.failed) _markFailed();
    return (value: value, failed: flag.failed);
  }

  static void log(String scope, String message) {
    if (kDebugMode) debugPrint('[$scope] $message');
  }
}

class _FailureFlag {
  bool failed = false;
}

/// Shown when a request fails for a reason the customer can't act on
/// (network down, timeout, server error). Details go to the debug log only.
const String kFriendlyNetworkError =
    'Something went wrong. Please check your connection and try again.';
