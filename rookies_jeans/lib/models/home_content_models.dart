// Models for the home-screen content managed through the Shopify metaobjects
// the admin panel (rookies-admin-panel/) edits: promo_block, shop_the_look,
// occasion_tile, instagram_post. `home_banner` already had a model in
// banner_model.dart.
//
// Each `fromMetaobjectJson` expects a node shaped by the field-aliased
// GraphQL query in ShopifyStorefrontService (see e.g. _fetchPromoBlocks),
// i.e. `{ id, image: {...}, label: {...}, sort_order: {...}, ... }` rather
// than the raw `fields: [...]` array shape.

import 'package:rookies_jeans/models/product_model.dart';

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

String? _imageUrlFrom(Map<String, dynamic>? field) {
  return field?['reference']?['image']?['url'] as String?;
}

String? _textFrom(Map<String, dynamic>? field) => field?['value'] as String?;

/// The collection an entry points to: the picked "Collection" field when
/// set, else the old free-text "collection_handle" field (a bare handle or
/// a pasted collection URL). [title] is null unless one was picked.
({String handle, String? title}) _collectionFrom(Map<String, dynamic> json) {
  final picked = json['collection']?['reference'] as Map<String, dynamic>?;
  final pickedHandle = picked?['handle'] as String?;
  if (pickedHandle != null && pickedHandle.isNotEmpty) {
    final title = (picked?['title'] as String?)?.trim();
    return (
      handle: pickedHandle,
      title: title == null || title.isEmpty ? null : title,
    );
  }
  return (handle: _handleFrom(_textFrom(json['collection_handle'])), title: null);
}

/// Accepts either a bare handle ("under-999") or a pasted collection URL
/// ("https://rookiesjeans.com/collections/under-999?x=1") and returns the
/// handle.
String _handleFrom(String? raw) {
  String value = (raw ?? '').trim();
  final int idx = value.indexOf('/collections/');
  if (idx >= 0) value = value.substring(idx + '/collections/'.length);
  value = value.split(RegExp(r'[/?#]')).first;
  return value.trim().toLowerCase();
}

class PromoBlockContent {
  final String id;
  final String? imageUrl;
  final String label;
  final String? buttonLabel;
  final String collectionHandle;

  /// Title of the picked collection; null for entries still using the old
  /// text handle.
  final String? collectionTitle;
  final int sortOrder;

  /// Image width / height, so the block can be shown uncropped; null when
  /// Shopify didn't report the size.
  final double? aspectRatio;

  const PromoBlockContent({
    required this.id,
    this.imageUrl,
    required this.label,
    this.buttonLabel,
    required this.collectionHandle,
    this.collectionTitle,
    this.sortOrder = 0,
    this.aspectRatio,
  });

  factory PromoBlockContent.fromMetaobjectJson(Map<String, dynamic> json) {
    final collection = _collectionFrom(json);
    final image = json['image']?['reference']?['image'];
    final width = _asInt(image?['width']);
    final height = _asInt(image?['height']);
    return PromoBlockContent(
      id: json['id'] as String,
      aspectRatio: width != null && height != null && width > 0 && height > 0
          ? width / height
          : null,
      imageUrl: _imageUrlFrom(json['image']),
      label: _textFrom(json['label']) ?? '',
      buttonLabel: _textFrom(json['button_label']),
      collectionHandle: collection.handle,
      collectionTitle: collection.title,
      sortOrder: _asInt(_textFrom(json['sort_order'])) ?? 0,
    );
  }
}

/// A full-width banner shown between "Explore Categories" and
/// "Shop The Look" (metaobject `feature_banner`).
class FeatureBannerContent {
  final String id;
  final String? imageUrl;
  final String label;
  final String? buttonLabel;

  /// Collection handle, `/collections/...`, `/products/...` or a full URL.
  final String link;

  /// Title of the picked collection, shown on the page it opens.
  final String? collectionTitle;
  final int sortOrder;

  /// Image width / height, so the banner can be shown uncropped; null when
  /// Shopify didn't report the size.
  final double? aspectRatio;

  const FeatureBannerContent({
    required this.id,
    this.imageUrl,
    this.label = '',
    this.buttonLabel,
    required this.link,
    this.collectionTitle,
    this.sortOrder = 0,
    this.aspectRatio,
  });

  factory FeatureBannerContent.fromMetaobjectJson(Map<String, dynamic> json) {
    final picked = json['collection']?['reference'] as Map<String, dynamic>?;
    final pickedHandle = picked?['handle'] as String?;
    final hasPicked = pickedHandle != null && pickedHandle.isNotEmpty;
    final image = json['image']?['reference']?['image'];
    final width = _asInt(image?['width']);
    final height = _asInt(image?['height']);
    return FeatureBannerContent(
      id: json['id'] as String,
      aspectRatio: width != null && height != null && width > 0 && height > 0
          ? width / height
          : null,
      imageUrl: _imageUrlFrom(json['image']),
      label: _textFrom(json['label']) ?? '',
      buttonLabel: _textFrom(json['button_label']),
      // A picked collection wins over the typed link.
      link: hasPicked
          ? '/collections/$pickedHandle'
          : _textFrom(json['link']) ?? '',
      collectionTitle: hasPicked ? _collectionFrom(json).title : null,
      sortOrder: _asInt(_textFrom(json['sort_order'])) ?? 0,
    );
  }
}

class ExploreCategoryContent {
  final String id;
  final String? imageUrl;
  final String label;
  final String collectionHandle;

  /// Title of the picked collection; null for entries still using the old
  /// text handle.
  final String? collectionTitle;
  final String section;
  final int sortOrder;

  const ExploreCategoryContent({
    required this.id,
    this.imageUrl,
    required this.label,
    required this.collectionHandle,
    this.collectionTitle,
    required this.section,
    this.sortOrder = 0,
  });

  bool get isBottomwear => section.trim().toLowerCase() == 'bottom';

  factory ExploreCategoryContent.fromMetaobjectJson(Map<String, dynamic> json) {
    final collection = _collectionFrom(json);
    return ExploreCategoryContent(
      id: json['id'] as String,
      imageUrl: _imageUrlFrom(json['image']),
      label: _textFrom(json['label']) ?? '',
      collectionHandle: collection.handle,
      collectionTitle: collection.title,
      section: _textFrom(json['section']) ?? 'top',
      sortOrder: _asInt(_textFrom(json['sort_order'])) ?? 0,
    );
  }
}

/// A tab in the home screen's "EXPLORE COLLECTIONS" row (HOT DEALS, SALE...);
/// each one shows the products of [collectionHandle].
class ExploreTabContent {
  final String id;
  final String label;
  final String collectionHandle;

  /// Title of the picked collection; null for entries still using the old
  /// text handle.
  final String? collectionTitle;
  final int sortOrder;

  const ExploreTabContent({
    required this.id,
    required this.label,
    required this.collectionHandle,
    this.collectionTitle,
    this.sortOrder = 0,
  });

  factory ExploreTabContent.fromMetaobjectJson(Map<String, dynamic> json) {
    final collection = _collectionFrom(json);
    return ExploreTabContent(
      id: json['id'] as String,
      label: (_textFrom(json['label']) ?? '').trim(),
      collectionHandle: collection.handle,
      collectionTitle: collection.title,
      sortOrder: _asInt(_textFrom(json['sort_order'])) ?? 0,
    );
  }

}

class ShopTheLookEntry {
  final String id;
  final String? imageUrl;
  final int sortOrder;
  final List<ShopifyProduct> products;

  const ShopTheLookEntry({
    required this.id,
    this.imageUrl,
    this.sortOrder = 0,
    this.products = const [],
  });

  factory ShopTheLookEntry.fromMetaobjectJson(Map<String, dynamic> json) {
    final edges = (json['products']?['references']?['edges'] as List?) ?? [];
    return ShopTheLookEntry(
      id: json['id'] as String,
      imageUrl: _imageUrlFrom(json['image']),
      sortOrder: _asInt(_textFrom(json['sort_order'])) ?? 0,
      products: edges
          .map((e) => ShopifyProduct.fromJson(e['node'] as Map<String, dynamic>))
          .toList(),
    );
  }
}

class OccasionTileContent {
  final String id;
  final String? imageUrl;
  final String? label;
  final String collectionHandle;

  /// Title of the picked collection; null for entries still using the old
  /// text handle.
  final String? collectionTitle;
  final int sortOrder;

  const OccasionTileContent({
    required this.id,
    this.imageUrl,
    this.label,
    required this.collectionHandle,
    this.collectionTitle,
    this.sortOrder = 0,
  });

  factory OccasionTileContent.fromMetaobjectJson(Map<String, dynamic> json) {
    final collection = _collectionFrom(json);
    return OccasionTileContent(
      id: json['id'] as String,
      imageUrl: _imageUrlFrom(json['image']),
      label: _textFrom(json['label']),
      collectionHandle: collection.handle,
      collectionTitle: collection.title,
      sortOrder: _asInt(_textFrom(json['sort_order'])) ?? 0,
    );
  }
}
