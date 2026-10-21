import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wishlisted products, newest last. Saved on the device so the list
/// survives app restarts.
class WishlistService extends ChangeNotifier {
  WishlistService._();
  static final WishlistService instance = WishlistService._();

  static const String _prefsKey = 'wishlist_products';

  final Map<String, ShopifyProduct> _wishlistProducts = {};
  Future<void>? _loading;

  /// Loads the saved list. Products toggled before this finishes are kept.
  Future<void> initialize() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      for (final entry in jsonDecode(raw) as List) {
        // Skip a corrupt entry rather than losing the whole list.
        try {
          final product =
              ShopifyProduct.fromCardJson(entry as Map<String, dynamic>);
          _wishlistProducts.putIfAbsent(product.id, () => product);
        } catch (e) {
          debugPrint('WishlistService skipped entry: $e');
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('WishlistService load error: $e');
    }
  }

  bool isWishlisted(String productId) {
    return _wishlistProducts.containsKey(productId);
  }

  List<ShopifyProduct> get items {
    return _wishlistProducts.values.toList();
  }

  int get count => _wishlistProducts.length;

  void toggleProduct(ShopifyProduct product) {
    if (_wishlistProducts.containsKey(product.id)) {
      _wishlistProducts.remove(product.id);
    } else {
      _wishlistProducts[product.id] = product;
    }
    notifyListeners();
    _save();
  }

  void removeById(String productId) {
    _wishlistProducts.remove(productId);
    notifyListeners();
    _save();
  }

  void clear() {
    _wishlistProducts.clear();
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    // Writing before the saved list is merged in would overwrite it.
    await initialize();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey,
          jsonEncode(_wishlistProducts.values.map((p) => p.toCardJson()).toList()));
    } catch (e) {
      debugPrint('WishlistService save error: $e');
    }
  }
}
