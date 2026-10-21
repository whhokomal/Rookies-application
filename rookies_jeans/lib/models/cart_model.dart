import 'package:rookies_jeans/utils/format.dart';

class ShopifyCartLine {
  final String lineId;
  final String variantId;
  final String productTitle;
  final String? productHandle;
  final String? variantTitle;
  final String? imageUrl;
  final double price;
  final String currencyCode;
  final int quantity;
  final bool availableForSale;

  const ShopifyCartLine({
    required this.lineId,
    required this.variantId,
    required this.productTitle,
    this.productHandle,
    this.variantTitle,
    this.imageUrl,
    required this.price,
    required this.currencyCode,
    required this.quantity,
    this.availableForSale = true,
  });

  double get lineTotal => price * quantity;

  String get formattedPrice =>
      formatMoney(price, currencyCode);

  String get formattedLineTotal =>
      formatMoney(lineTotal, currencyCode);

  factory ShopifyCartLine.fromJson(Map<String, dynamic> json) {
  final merchandise = json['merchandise'] as Map<String, dynamic>?;
  final product = merchandise?['product'] as Map<String, dynamic>?;
  final priceNode = merchandise?['priceV2'] ?? merchandise?['price'];
  final imageEdges = (product?['images']?['edges'] as List?) ?? [];

  final imageUrl = imageEdges.isNotEmpty
      ? (imageEdges.first['node']?['url'] as String?)
      : (merchandise?['image']?['url'] as String?);

  return ShopifyCartLine(
    lineId: json['id'] as String,
    variantId: merchandise?['id'] as String? ?? '',
    productTitle: product?['title'] as String? ?? merchandise?['title'] as String? ?? '',
    productHandle: product?['handle'] as String?,
    variantTitle: merchandise?['title'] as String?,
    imageUrl: imageUrl,
    price: double.tryParse('${priceNode?['amount'] ?? '0'}') ?? 0,
    currencyCode: priceNode?['currencyCode'] as String? ?? 'INR',
    quantity: json['quantity'] as int? ?? 1,
    availableForSale: merchandise?['availableForSale'] as bool? ?? true,
  );
}
}

class ShopifyCart {
  final String id;
  final String? checkoutUrl;
  final List<ShopifyCartLine> lines;
  final double subtotal;
  final String currencyCode;
  final int totalQuantity;

  const ShopifyCart({
    required this.id,
    this.checkoutUrl,
    required this.lines,
    required this.subtotal,
    required this.currencyCode,
    required this.totalQuantity,
  });

  String get formattedSubtotal => formatMoney(subtotal, currencyCode);

  factory ShopifyCart.fromJson(Map<String, dynamic> json) {
    final linesEdges = (json['lines']?['edges'] as List?) ?? [];
    final lines = linesEdges
        .map((e) => ShopifyCartLine.fromJson(e['node'] as Map<String, dynamic>))
        .toList();

    final costNode = json['cost']?['subtotalAmount'];

    return ShopifyCart(
      id: json['id'] as String,
      checkoutUrl: json['checkoutUrl'] as String?,
      lines: lines,
      subtotal: double.tryParse('${costNode?['amount'] ?? '0'}') ?? 0,
      currencyCode: costNode?['currencyCode'] as String? ?? 'INR',
      totalQuantity: json['totalQuantity'] as int? ?? 0,
    );
  }

  static const empty = ShopifyCart(
    id: '',
    checkoutUrl: null,
    lines: [],
    subtotal: 0,
    currencyCode: 'INR',
    totalQuantity: 0,
  );
}