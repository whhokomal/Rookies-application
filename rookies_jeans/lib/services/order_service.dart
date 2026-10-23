import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/services/shopify_api.dart';
import 'package:rookies_jeans/services/shopify_auth_service.dart';
import 'package:rookies_jeans/utils/format.dart';

class ShopifyOrderException implements Exception {
  final String code;
  const ShopifyOrderException(this.code);

  String get userMessage {
    switch (code) {
      case 'not_logged_in':
        return 'Please sign in to view your orders.';
      case 'fetch_failed':
        return 'Failed to load orders. Please try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}

/// [placed]: not fulfilled yet. [shipped]: fulfilled (or partly) in Shopify,
/// or the courier reported a pickup / in transit. [delivered]: the courier
/// reported delivery, which the Shopify Flow "Fulfillment event created"
/// copies into the order metafield `custom.delivery_status` because the
/// Storefront API has no shipment status.
enum OrderState { placed, shipped, delivered, cancelled }

class ShopifyOrderService {
  ShopifyOrderService._();
  static final ShopifyOrderService instance = ShopifyOrderService._();

  /// Up to 500 orders (10 pages of 50).
  static const int _maxOrderPages = 10;

  Future<String?> _getToken() async {
    final token = await ShopifyAuthService.instance.getSavedCustomerToken();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<List<Map<String, dynamic>>> fetchOrders() async {
    final token = await _getToken();
    if (token == null) throw const ShopifyOrderException('not_logged_in');

    const String query = r'''
      query getOrders($customerAccessToken: String!, $after: String) {
        customer(customerAccessToken: $customerAccessToken) {
          orders(first: 50, after: $after, sortKey: PROCESSED_AT, reverse: true) {
            pageInfo { hasNextPage endCursor }
            edges {
              node {
                id
                orderNumber
                processedAt
                financialStatus
                fulfillmentStatus
                canceledAt
                deliveryStatus: metafield(namespace: "custom", key: "delivery_status") {
                  value
                }
                successfulFulfillments(first: 5) {
                  trackingInfo(first: 1) { number url }
                }
                currentTotalPrice {
                  amount
                  currencyCode
                }
                subtotalPrice { amount currencyCode }
                totalShippingPrice { amount currencyCode }
                totalTax { amount currencyCode }
                shippingAddress {
                  name
                  address1
                  address2
                  city
                  province
                  zip
                  country
                  phone
                }
                lineItems(first: 50) {
                  edges {
                    node {
                      title
                      quantity
                      variant {
                        image { url(transform: {maxWidth: 300}) }
                        price { amount currencyCode }
                        selectedOptions { name value }
                        product { handle title }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    ''';

    try {
      // Pages of 50, newest first, so repeat customers see all their
      // orders (capped so a huge history can't loop forever).
      final orders = <Map<String, dynamic>>[];
      String? after;
      for (var page = 0; page < _maxOrderPages; page++) {
        final res = await ShopifyGraphQL.post(
          query,
          variables: {'customerAccessToken': token, 'after': after},
        );

        if (res.statusCode != 200 || res.hasErrors) {
          throw const ShopifyOrderException('fetch_failed');
        }

        final ordersNode = res.data?['customer']?['orders'];
        final edges = (ordersNode?['edges'] as List?) ?? [];
        orders.addAll(edges.map((e) => e['node'] as Map<String, dynamic>));

        final pageInfo = ordersNode?['pageInfo'];
        if (pageInfo?['hasNextPage'] != true) break;
        after = pageInfo?['endCursor'] as String?;
        if (after == null) break;
      }
      return orders;
    } on ShopifyOrderException {
      rethrow;
    } catch (_) {
      throw const ShopifyOrderException('fetch_failed');
    }
  }

  OrderState resolveOrderState(Map<String, dynamic> order) {
    final canceledAt      = order['canceledAt'];
    final financialStatus = (order['financialStatus'] ?? '').toString().toUpperCase();

    if (canceledAt != null && canceledAt.toString().isNotEmpty) return OrderState.cancelled;
    if (financialStatus == 'REFUNDED') return OrderState.cancelled;
    final shipment = (order['deliveryStatus']?['value'] ?? '').toString().toUpperCase();
    final fulfillStatus = (order['fulfillmentStatus'] ?? '').toString().toUpperCase();
    if (shipment == 'DELIVERED') return OrderState.delivered;
    if (fulfillStatus == 'FULFILLED' || fulfillStatus == 'PARTIALLY_FULFILLED') {
      return OrderState.shipped;
    }
    if (_shippedStatuses.contains(shipment)) return OrderState.shipped;
    return OrderState.placed;
  }

  // OUT_FOR_DELIVERY / ATTEMPTED_DELIVERY / PICKED_UP only come from the
  // one-off backfill of past orders (tool/backfill_delivery_status.mjs).
  static const Set<String> _shippedStatuses = {
    'CARRIER_PICKED_UP',
    'PICKED_UP',
    'IN_TRANSIT',
    'OUT_FOR_DELIVERY',
    'ATTEMPTED_DELIVERY',
  };

  bool isCod(Map<String, dynamic> order) {
    final financialStatus = (order['financialStatus'] ?? '').toString().toUpperCase();
    return financialStatus == 'PENDING';
  }

  bool canCancelOrder(Map<String, dynamic> order) {
    if (resolveOrderState(order) != OrderState.placed) return false;
    final fulfillStatus = (order['fulfillmentStatus'] ?? '').toString().toUpperCase();
    return fulfillStatus == 'UNFULFILLED';
  }

  // ── Order cancellation ───────────────────────────────────────────────
  //
  // The website cancels orders through the "Codify Order Cancel" app
  // (theme snippet `codify-order-cancel.liquid`), which posts to its
  // app-proxy endpoint. We send the exact same request so cancellations
  // behave identically (refund, restock, customer email), without needing a
  // website login.
  //
  // These mirror the shop metafield `cocapp_config.settings` (set in the
  // Codify app admin). Update them here if those settings change.
  static const List<String> cancelReasons = [
    'Change of Mind',
    'Incorrect Item Ordered',
    'Delivery Time Too Long',
    'Address Error',
    'Found a Better Deal',
  ];
  static const Map<String, dynamic> _cancelSettings = {
    'send_email': true,
    'enable_restock': true,
    'enable_refund': true,
    'refund_shipping': true,
    'only_cod_cancel': false,
    'availability': {'type': 'until_ship', 'value': '7', 'unit': 'days'},
    'restrict_order': false,
    'restrict_product': false,
  };

  /// Cancels [order] for the chosen [reason]. Returns null on success, or a
  /// message to show the customer.
  Future<String?> cancelOrder(
    Map<String, dynamic> order, {
    required String reason,
  }) async {
    final numericId = int.tryParse((order['id'] as String).split('/').last.split('?').first);
    if (numericId == null) return 'This order cannot be cancelled.';

    // The Codify settings require a free-text comment; the app only asks for
    // a reason, so the reason doubles as the comment.
    final body = <String, dynamic>{
      'shop': ShopifyConstants.shopDomain,
      'order_id': numericId,
      ..._cancelSettings,
      'tag': _reasonTag(reason),
      'reason': reason,
    };

    try {
      final res = await http
          .post(
            Uri.parse('${ShopifyConstants.storeUrl}/apps/co/api/order_cancel'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) return 'Could not cancel the order. Please try again.';
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final error = decoded['error'];
      if (error == null) return null;

      switch (error) {
        case 'not-cod':
          return 'This order cannot be cancelled as it was not placed with Cash on Delivery.';
        case 'expired':
          return 'This order can no longer be cancelled.';
        case 'country-block':
          return 'Order cancellation is not available for your location.';
        default:
          return 'This order cannot be cancelled.';
      }
    } catch (_) {
      return 'Could not cancel the order. Please check your connection and try again.';
    }
  }

  /// Same tag format the website uses, e.g. "cancel-change-of-mind".
  String _reasonTag(String reason) {
    final slug = reason
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'cancel-$slug';
  }

  /// Cancellation is processed asynchronously; poll until Shopify reports
  /// the order as cancelled. Returns the updated order, or null if it
  /// hasn't shown up yet.
  Future<Map<String, dynamic>?> waitForCancellation(String orderId) async {
    for (var i = 0; i < 6; i++) {
      await Future.delayed(const Duration(milliseconds: 1500));
      try {
        final orders = await fetchOrders();
        final match = orders.where((o) => o['id'] == orderId).firstOrNull;
        if (match != null && resolveOrderState(match) == OrderState.cancelled) {
          return match;
        }
      } catch (_) {}
    }
    return null;
  }

  String formatPrice(Map<String, dynamic> price) {
    final amount   = double.tryParse(price['amount']?.toString() ?? '0') ?? 0;
    final currency = price['currencyCode']?.toString() ?? 'INR';
    return formatMoney(amount, currency);
  }

  String formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }

  String formatStatus(String status) {
    return status
        .toLowerCase()
        .split('_')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}