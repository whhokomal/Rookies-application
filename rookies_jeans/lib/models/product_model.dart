import 'package:rookies_jeans/utils/format.dart';

class ShopifyFilter {
  final String id;
  final String label;
  final String type;
  final List<ShopifyFilterValue> values;

  const ShopifyFilter({
    required this.id,
    required this.label,
    required this.type,
    required this.values,
  });

  factory ShopifyFilter.fromJson(Map<String, dynamic> json) {
    final valuesList = (json['values'] as List?) ?? [];
    return ShopifyFilter(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      type: json['type'] as String? ?? 'LIST',
      values: valuesList
          .map((v) => ShopifyFilterValue.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ShopifyFilterValue {
  final String id;
  final String label;
  final int count;
  final String input;

  const ShopifyFilterValue({
    required this.id,
    required this.label,
    required this.count,
    required this.input,
  });

  factory ShopifyFilterValue.fromJson(Map<String, dynamic> json) {
    return ShopifyFilterValue(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      input: json['input'] as String? ?? '{}',
    );
  }
}

class ShopifyProduct {
  final String id;
  final String title;
  final String handle;
  final double price;
  final double? compareAtPrice;
  final String currencyCode;
  final List<String> imageUrls;
  final List<ProductVariant> variants;
  final List<ProductOption> options;
  // Only populated by queries that request it (currently just search) — used
  // for the "Newest" client-side sort where Shopify's search API has no
  // server-side CREATED sort key to rely on instead.
  final DateTime? createdAt;

  const ShopifyProduct({
    required this.id,
    required this.title,
    required this.handle,
    required this.price,
    this.compareAtPrice,
    required this.currencyCode,
    required this.imageUrls,
    required this.variants,
    required this.options,
    this.createdAt,
  });

  bool get isOnSale => compareAtPrice != null && compareAtPrice! > price;

  String get formattedPrice =>
      currencyCode == 'INR' ? formatInr(price) : price.toStringAsFixed(2);

  String get formattedCompareAtPrice {
    if (compareAtPrice == null) return '';
    return currencyCode == 'INR'
        ? formatInr(compareAtPrice!)
        : compareAtPrice!.toStringAsFixed(2);
  }

  /// Only what a product card needs, for lists saved on the device
  /// (wishlist, recently viewed). Price is as seen when saved.
  Map<String, dynamic> toCardJson() => {
        'id': id,
        'title': title,
        'handle': handle,
        'price': price,
        'compareAtPrice': compareAtPrice,
        'currencyCode': currencyCode,
        'imageUrls': imageUrls,
      };

  factory ShopifyProduct.fromCardJson(Map<String, dynamic> json) =>
      ShopifyProduct(
        id: json['id'] as String,
        title: json['title'] as String,
        handle: json['handle'] as String,
        price: (json['price'] as num).toDouble(),
        compareAtPrice: (json['compareAtPrice'] as num?)?.toDouble(),
        currencyCode: json['currencyCode'] as String,
        imageUrls: List<String>.from(json['imageUrls'] as List),
        variants: const [],
        options: const [],
      );

  String? get primaryImageUrl => imageUrls.isNotEmpty ? imageUrls.first : null;

  List<String> get colorHexCodes {
    for (final opt in options) {
      if (opt.name.toUpperCase() == 'COLOR' ||
          opt.name.toUpperCase() == 'COLOUR') {
        return opt.optionValues
            .where((v) => v.swatchColor != null)
            .map((v) => v.swatchColor!)
            .toSet()
            .toList();
      }
    }
    return [];
  }

  factory ShopifyProduct.fromJson(Map<String, dynamic> json) {
    final priceStr =
        json['priceRange']?['minVariantPrice']?['amount'] as String? ?? '0';
    final compareStr =
        json['compareAtPriceRange']?['minVariantPrice']?['amount'] as String?;
    final currency =
        json['priceRange']?['minVariantPrice']?['currencyCode'] as String? ??
            'INR';

    final imgEdges = (json['images']?['edges'] as List?) ?? [];
    final images = imgEdges.map((e) => e['node']['url'] as String).toList();

    final varEdges = (json['variants']?['edges'] as List?) ?? [];
    final variants = varEdges
        .map((e) =>
            ProductVariant.fromJson(e['node'] as Map<String, dynamic>))
        .toList();

    final optList = (json['options'] as List?) ?? [];
    final options = optList
        .map((o) => ProductOption.fromJson(o as Map<String, dynamic>))
        .toList();

    return ShopifyProduct(
      id: json['id'] as String,
      title: json['title'] as String,
      handle: json['handle'] as String,
      price: double.tryParse(priceStr) ?? 0,
      compareAtPrice: compareStr != null ? double.tryParse(compareStr) : null,
      currencyCode: currency,
      imageUrls: images,
      variants: variants,
      options: options,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }
}

class ProductVariant {
  final String id;
  final String title;
  final bool availableForSale;
  final List<SelectedOption> selectedOptions;

  const ProductVariant({
    required this.id,
    required this.title,
    required this.availableForSale,
    required this.selectedOptions,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) => ProductVariant(
        id: json['id'] as String,
        title: json['title'] as String,
        availableForSale: json['availableForSale'] as bool? ?? false,
        selectedOptions: ((json['selectedOptions'] as List?) ?? [])
            .map((o) => SelectedOption.fromJson(o as Map<String, dynamic>))
            .toList(),
      );
}

class SelectedOption {
  final String name;
  final String value;
  const SelectedOption({required this.name, required this.value});
  factory SelectedOption.fromJson(Map<String, dynamic> json) => SelectedOption(
        name: json['name'] as String,
        value: json['value'] as String,
      );
}

class ProductOption {
  final String name;
  final List<String> values;
  final List<OptionValue> optionValues;

  const ProductOption({
    required this.name,
    required this.values,
    required this.optionValues,
  });

  factory ProductOption.fromJson(Map<String, dynamic> json) {
    final ovList = (json['optionValues'] as List?) ?? [];
    return ProductOption(
      name: json['name'] as String,
      values: ((json['values'] as List?) ?? []).cast<String>(),
      optionValues:
          ovList.map((o) => OptionValue.fromJson(o as Map<String, dynamic>)).toList(),
    );
  }
}

class OptionValue {
  final String name;
  final String? swatchColor;

  const OptionValue({required this.name, this.swatchColor});

  factory OptionValue.fromJson(Map<String, dynamic> json) {
    final rawColor = json['swatch']?['color'] as String?;
    return OptionValue(
      name: json['name'] as String,
      swatchColor: rawColor,
    );
  }
}

/// A single product reference inside a Variant King (`vkcl.group_data`)
/// color group — just enough to identify and fetch the sibling product.
class ColorGroupProductRef {
  final String id; // numeric Shopify product id, as a string
  final String handle;

  const ColorGroupProductRef({required this.id, required this.handle});

  factory ColorGroupProductRef.fromJson(Map<String, dynamic> json) {
    return ColorGroupProductRef(
      id: json['id']?.toString() ?? '',
      handle: json['handle'] as String? ?? '',
    );
  }
}

/// One color-family grouping as written by the Variant King / SA Variants
/// app into the `vkcl.group_data` product metafield (namespace `vkcl`,
/// key `group_data`, type JSON). The raw metafield value is a JSON string
/// containing a list of these, e.g.:
/// ```json
/// [
///   {
///     "group_name": "RJS3147A , RJS3147B",
///     "products": [
///       { "id": 10230091645223, "handle": "white-..." },
///       { "id": 10230091677991, "handle": "black-..." }
///     ]
///   }
/// ]
/// ```
class ColorGroup {
  final String groupName;
  final List<ColorGroupProductRef> products;

  const ColorGroup({required this.groupName, required this.products});

  factory ColorGroup.fromJson(Map<String, dynamic> json) {
    final list = (json['products'] as List?) ?? [];
    return ColorGroup(
      groupName: json['group_name'] as String? ?? '',
      products: list
          .whereType<Map<String, dynamic>>()
          .map(ColorGroupProductRef.fromJson)
          .toList(),
    );
  }
}