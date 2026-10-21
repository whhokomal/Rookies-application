import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Products the customer has opened, newest first. Saved on the device so
/// the list survives app restarts; every product detail page records itself
/// here and lists the rest in its "Recently Viewed" row.
class RecentlyViewedService extends ChangeNotifier {
  RecentlyViewedService._();
  static final RecentlyViewedService instance = RecentlyViewedService._();

  static const int _maxItems = 30;
  static const String _prefsKey = 'recently_viewed_products';

  final List<ShopifyProduct> _items = [];
  Future<void>? _loading;

  List<ShopifyProduct> get items => List.unmodifiable(_items);

  /// Loads the saved list. Products recorded before this finishes stay in
  /// front of the saved ones.
  Future<void> initialize() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final saved = <ShopifyProduct>[];
      for (final entry in jsonDecode(raw) as List) {
        // Skip a corrupt entry rather than losing the whole list.
        try {
          saved.add(ShopifyProduct.fromCardJson(entry as Map<String, dynamic>));
        } catch (e) {
          debugPrint('RecentlyViewedService skipped entry: $e');
        }
      }
      _items.addAll(
          saved.where((p) => !_items.any((item) => item.id == p.id)));
      if (_items.length > _maxItems) {
        _items.removeRange(_maxItems, _items.length);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('RecentlyViewedService load error: $e');
    }
  }

  /// Moves [product] to the front (adding it if new).
  void record(ShopifyProduct product) {
    _items.removeWhere((p) => p.id == product.id);
    _items.insert(0, product);
    if (_items.length > _maxItems) _items.removeRange(_maxItems, _items.length);
    notifyListeners();
    _save();
  }

  void clear() {
    _items.clear();
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    // Writing before the saved list is merged in would overwrite it.
    await initialize();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(_items.map((p) => p.toCardJson()).toList()));
    } catch (e) {
      debugPrint('RecentlyViewedService save error: $e');
    }
  }
}
