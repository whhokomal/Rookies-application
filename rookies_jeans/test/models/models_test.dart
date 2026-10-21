import 'package:flutter_test/flutter_test.dart';
import 'package:rookies_jeans/models/cart_model.dart';
import 'package:rookies_jeans/models/product_model.dart';

void main() {
  group('ShopifyProduct card JSON', () {
    test('round-trips the fields a product card needs', () {
      const product = ShopifyProduct(
        id: 'gid://shopify/Product/1',
        title: 'Jann Loose Jeans',
        handle: 'jann-loose-jeans',
        price: 1899,
        compareAtPrice: 2499,
        currencyCode: 'INR',
        imageUrls: ['https://cdn.shopify.com/a.jpg'],
        variants: [],
        options: [],
      );

      final restored = ShopifyProduct.fromCardJson(product.toCardJson());

      expect(restored.id, product.id);
      expect(restored.handle, product.handle);
      expect(restored.price, 1899);
      expect(restored.compareAtPrice, 2499);
      expect(restored.isOnSale, isTrue);
      expect(restored.primaryImageUrl, 'https://cdn.shopify.com/a.jpg');
    });
  });

  group('ShopifyCart.fromJson', () {
    test('reads lines, subtotal and quantity', () {
      final cart = ShopifyCart.fromJson({
        'id': 'gid://shopify/Cart/abc',
        'totalQuantity': 3,
        'cost': {
          'subtotalAmount': {'amount': '5697.0', 'currencyCode': 'INR'},
        },
        'lines': {
          'edges': [
            {
              'node': {
                'id': 'line-1',
                'quantity': 3,
                'merchandise': {
                  'id': 'gid://shopify/ProductVariant/9',
                  'title': '32',
                  'availableForSale': true,
                  'priceV2': {'amount': '1899.0', 'currencyCode': 'INR'},
                  'product': {
                    'handle': 'jann-loose-jeans',
                    'title': 'Jann Loose Jeans',
                    'images': {'edges': []},
                  },
                },
              },
            },
          ],
        },
      });

      expect(cart.totalQuantity, 3);
      expect(cart.subtotal, 5697);
      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.variantId, 'gid://shopify/ProductVariant/9');
      expect(cart.lines.single.lineTotal, 5697);
    });
  });
}
