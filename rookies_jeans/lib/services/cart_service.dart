import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rookies_jeans/services/shopify_api.dart';
import 'package:rookies_jeans/models/cart_model.dart';
import 'package:rookies_jeans/services/notification_service.dart';

class CartService extends ChangeNotifier {
  CartService._();
  static final CartService instance = CartService._();

  static const String _cartIdPrefsKey = 'shopify_cart_id';

  String? _cartId;
  ShopifyCart _cart = ShopifyCart.empty;
  int _pending = 0;
  bool _initialized = false;
  String? _lastError;

  /// Cart operations run one after another, so two quick taps on +/- can't
  /// send overlapping mutations.
  Future<void> _queue = Future.value();

  ShopifyCart get cart => _cart;
  bool get isLoading => _pending > 0;
  int get totalQuantity => _cart.totalQuantity;

  /// Shopify's message for the last failed add/update (e.g. "Only 2 left in
  /// stock"), or null when it failed for another reason.
  String? get lastError => _lastError;

  void _log(String msg) {
    if (kDebugMode) debugPrint('[CartService] $msg');
  }

  bool isInCart(String variantId) =>
      _cart.lines.any((l) => l.variantId == variantId && l.quantity > 0);

  int quantityForVariant(String variantId) {
    final matches = _cart.lines.where((l) => l.variantId == variantId);
    if (matches.isEmpty) return 0;
    return matches.first.quantity;
  }

  Future<void> initialize({bool forceRefresh = false}) async {
    if (_initialized && !forceRefresh) return;

    final prefs = await SharedPreferences.getInstance();
    _cartId = prefs.getString(_cartIdPrefsKey);

    if (_cartId != null) {
      await refresh();
    }

    _initialized = true;
  }

  Future<void> _persistCartId(String id) async {
    _cartId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cartIdPrefsKey, id);
  }

  Future<void> _clearPersistedCartId() async {
    _cartId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cartIdPrefsKey);
  }

  /// Runs [op] after any earlier cart operation finishes, with [isLoading]
  /// true for the whole time.
  Future<T> _run<T>(Future<T> Function() op) {
    final result = _queue.then((_) async {
      _pending++;
      notifyListeners();
      try {
        return await op();
      } finally {
        _pending--;
        notifyListeners();
      }
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static const String _cartFragment = r'''
    fragment CartFields on Cart {
      id
      checkoutUrl
      totalQuantity
      cost {
        subtotalAmount { amount currencyCode }
      }
      lines(first: 100) {
        edges {
          node {
            id
            quantity
            merchandise {
              ... on ProductVariant {
                id
                title
                availableForSale
                priceV2: price { amount currencyCode }
                image { url(transform: {maxWidth: 400}) }
                product {
                  handle
                  title
                  images(first: 1) { edges { node { url(transform: {maxWidth: 400}) } } }
                }
              }
            }
          }
        }
      }
    }
  ''';

  Future<Map<String, dynamic>> _post(String query, Map<String, dynamic> variables) async {
    final res = await ShopifyGraphQL.post(query, variables: variables);
    return res.body;
  }

  /// First userError message from a cart mutation payload, if any.
  String? _userErrorMessage(List userErrors) {
    if (userErrors.isEmpty) return null;
    final message = (userErrors.first as Map?)?['message']?.toString();
    return (message == null || message.isEmpty) ? null : message;
  }

  Future<void> refresh() => _run(_refresh);

  Future<void> _refresh() async {
    if (_cartId == null) {
      _cart = ShopifyCart.empty;
      return;
    }

    final query = '''
      query getCart(\$cartId: ID!) {
        cart(id: \$cartId) {
          ...CartFields
        }
      }
      $_cartFragment
    ''';

    try {
      final decoded = await _post(query, {'cartId': _cartId});
      _log('cart fetch → ${decoded['errors'] ?? 'ok'}');

      final cartNode = decoded['data']?['cart'];
      if (decoded['errors'] == null && cartNode == null) {
        // Shopify no longer knows this cart (expired or converted).
        await _clearPersistedCartId();
        _cart = ShopifyCart.empty;
      } else if (cartNode != null) {
        _cart = ShopifyCart.fromJson(cartNode as Map<String, dynamic>);
      }
      // On a request error keep showing the cart we have.
    } catch (e) {
      _log('refresh EXCEPTION: $e');
    }
  }

  /// Creates a cart holding one line. Returns the new cart id, or null.
  Future<String?> _createCart({required String variantId, required int quantity}) async {
    const mutation = r'''
      mutation cartCreate($input: CartInput) {
        cartCreate(input: $input) {
          cart { id }
          userErrors { field message }
        }
      }
    ''';

    final decoded = await _post(mutation, {
      'input': {
        'lines': [
          {'merchandiseId': variantId, 'quantity': quantity}
        ],
      },
    });

    _log('cartCreate → ${decoded['errors'] ?? 'ok'}');
    final data = decoded['data']?['cartCreate'];
    final userErrors = (data?['userErrors'] as List?) ?? [];
    if (decoded['errors'] != null || userErrors.isNotEmpty) {
      _log('cartCreate userErrors: $userErrors');
      _lastError = _userErrorMessage(userErrors);
      return null;
    }
    return data?['cart']?['id'] as String?;
  }

  Future<bool> addLine({required String variantId, int quantity = 1}) {
    return _run(() async {
      _lastError = null;
      try {
        if (_cartId == null) {
          return _addToNewCart(variantId: variantId, quantity: quantity);
        }

        const mutation = r'''
          mutation cartLinesAdd($cartId: ID!, $lines: [CartLineInput!]!) {
            cartLinesAdd(cartId: $cartId, lines: $lines) {
              cart { id }
              userErrors { field message }
            }
          }
        ''';

        final decoded = await _post(mutation, {
          'cartId': _cartId,
          'lines': [
            {'merchandiseId': variantId, 'quantity': quantity}
          ],
        });

        _log('cartLinesAdd → ${decoded['errors'] ?? 'ok'}');
        if (decoded['errors'] != null) return false;

        final data = decoded['data']?['cartLinesAdd'];
        final userErrors = (data?['userErrors'] as List?) ?? [];
        if (userErrors.isNotEmpty) {
          // E.g. sold out or not enough stock. The rest of the cart is
          // still fine, so keep it and tell the customer why.
          _log('cartLinesAdd userErrors: $userErrors');
          _lastError = _userErrorMessage(userErrors);
          return false;
        }

        if (data?['cart'] == null) {
          // The saved cart no longer exists (expired or already checked
          // out); only then start a new one.
          await _clearPersistedCartId();
          return _addToNewCart(variantId: variantId, quantity: quantity);
        }

        await _refresh();
        _reportCart(added: true);
        return true;
      } catch (e) {
        _log('addLine EXCEPTION: $e');
        return false;
      }
    });
  }

  Future<bool> _addToNewCart({required String variantId, required int quantity}) async {
    final newCartId = await _createCart(variantId: variantId, quantity: quantity);
    if (newCartId == null) return false;
    await _persistCartId(newCartId);
    await _refresh();
    _reportCart(added: true);
    return true;
  }

  /// Tells the notification worker what's in the cart (it plans or cancels
  /// cart reminders), and asks for notification permission after the first
  /// add, when a reminder is obviously useful.
  void _reportCart({bool added = false}) {
    NotificationService.instance.track('cart_updated', {
      'cartId': _cartId,
      'count': _cart.totalQuantity,
    });
    if (added) NotificationService.instance.requestPermission();
  }

  Future<bool> updateLineQuantity({required String lineId, required int quantity}) async {
    if (_cartId == null) return false;

    if (quantity <= 0) {
      return removeLine(lineId: lineId);
    }

    const mutation = r'''
      mutation cartLinesUpdate($cartId: ID!, $lines: [CartLineUpdateInput!]!) {
        cartLinesUpdate(cartId: $cartId, lines: $lines) {
          cart { id }
          userErrors { field message }
        }
      }
    ''';

    return _run(() async {
      _lastError = null;
      try {
        final decoded = await _post(mutation, {
          'cartId': _cartId,
          'lines': [
            {'id': lineId, 'quantity': quantity}
          ],
        });

        _log('cartLinesUpdate → ${decoded['errors'] ?? 'ok'}');
        final data = decoded['data']?['cartLinesUpdate'];
        final userErrors = (data?['userErrors'] as List?) ?? [];
        if (decoded['errors'] != null || userErrors.isNotEmpty) {
          _log('cartLinesUpdate userErrors: $userErrors');
          _lastError = _userErrorMessage(userErrors);
          return false;
        }

        await _refresh();
        _reportCart();
        return true;
      } catch (e) {
        _log('updateLineQuantity EXCEPTION: $e');
        return false;
      }
    });
  }

  Future<bool> removeLine({required String lineId}) async {
    if (_cartId == null) return false;

    const mutation = r'''
      mutation cartLinesRemove($cartId: ID!, $lineIds: [ID!]!) {
        cartLinesRemove(cartId: $cartId, lineIds: $lineIds) {
          cart { id }
          userErrors { field message }
        }
      }
    ''';

    return _run(() async {
      try {
        final decoded = await _post(mutation, {
          'cartId': _cartId,
          'lineIds': [lineId],
        });

        _log('cartLinesRemove → ${decoded['errors'] ?? 'ok'}');
        final data = decoded['data']?['cartLinesRemove'];
        final userErrors = (data?['userErrors'] as List?) ?? [];
        if (decoded['errors'] != null || userErrors.isNotEmpty) {
          _log('cartLinesRemove userErrors: $userErrors');
          return false;
        }

        await _refresh();
        _reportCart();
        return true;
      } catch (e) {
        _log('removeLine EXCEPTION: $e');
        return false;
      }
    });
  }

  Future<void> reset() async {
    await _clearPersistedCartId();
    _cart = ShopifyCart.empty;
    notifyListeners();
    _reportCart();
  }
}
