import 'dart:convert';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:rookies_jeans/services/shopify_api.dart';
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/models/product_detail_model.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/models/banner_model.dart';
import 'package:rookies_jeans/models/collection_model.dart';
import 'package:rookies_jeans/models/home_content_models.dart';
import 'package:rookies_jeans/models/shop_menu_model.dart';
import 'package:rookies_jeans/models/shop_policy_model.dart';

class PaginatedProductsResponse {
  final List<ShopifyProduct> products;
  final bool hasNextPage;
  final String? endCursor;
  final List<ShopifyFilter> filters;

  const PaginatedProductsResponse({
    required this.products,
    required this.hasNextPage,
    required this.endCursor,
    this.filters = const [],
  });
}

enum ProductSortOption {
  featured('Featured', 'COLLECTION_DEFAULT', false),
  priceLowToHigh('Price: Low to High', 'PRICE', false),
  priceHighToLow('Price: High to Low', 'PRICE', true),
  newest('Newest', 'CREATED', true),
  bestSelling('Best Selling', 'BEST_SELLING', false),
  titleAZ('Alphabetically: A-Z', 'TITLE', false),
  titleZA('Alphabetically: Z-A', 'TITLE', true);

  final String label;
  final String shopifyKey;
  final bool reverse;

  const ProductSortOption(this.label, this.shopifyKey, this.reverse);
}

class ShopifyStorefrontService {

  static const List<Map<String, String>> _variantMetafieldIdentifiers = [
    {'namespace': 'custom', 'key': 'fit'},
    {'namespace': 'custom', 'key': 'material'},
    {'namespace': 'custom', 'key': 'fabric'},
  ];

  ShopifyStorefrontService._();
  static final ShopifyStorefrontService instance = ShopifyStorefrontService._();

  /// How long a cached result is reused before it is fetched again, so
  /// prices, stock and home content refresh while the app stays open.
  static const Duration _cacheTtl = Duration(minutes: 10);

  final Map<String, ({Object? value, DateTime at})> _cache = {};
  final Map<String, Future<({Object? value, bool failed})>> _inFlight = {};

  void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }

  void _log(String msg) => ShopifyGraphQL.log('ShopifyStorefrontService', msg);

  /// Returns the cached result for [cacheKey], or runs [fetcher]. Results
  /// produced while a Shopify request failed (the fetchers then return an
  /// empty list / null / fallback content) are returned but not cached, so
  /// the next visit tries again instead of staying empty all session.
  Future<T> _cachedFetch<T>(
    String cacheKey,
    Future<T> Function() fetcher,
  ) async {
    final cached = _cache[cacheKey];
    if (cached != null) {
      if (DateTime.now().difference(cached.at) < _cacheTtl) {
        _log('cache HIT: $cacheKey');
        return cached.value as T;
      }
      _cache.remove(cacheKey);
    }

    if (_inFlight.containsKey(cacheKey)) {
      _log('in-flight HIT: $cacheKey');
      final inFlight = await _inFlight[cacheKey]!;
      // Let an enclosing fetch know this result came from a failed request.
      if (inFlight.failed) ShopifyGraphQL.reportFailure();
      return inFlight.value as T;
    }

    final future = ShopifyGraphQL.trackFailures<Object?>(fetcher);
    _inFlight[cacheKey] = future;

    try {
      final result = await future;
      if (result.failed) {
        _log('not caching $cacheKey (request failed)');
      } else {
        _cache[cacheKey] = (value: result.value, at: DateTime.now());
      }
      return result.value as T;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  /// Warms the cache with what HomeScreen loads on open, so it can run while
  /// the splash video plays. Must stay in step with HomeScreen._fetchAll and
  /// _fetchExploreProducts (same calls, same arguments) or the cache misses.
  Future<void> prefetchHomeData() async {
    // Home first loads the default (Hot Deals) grid, then switches to the
    // first configured tab if Hot Deals isn't one of them.
    final explore = getExploreTabs().then((tabs) {
      final handles = {
        ShopifyConstants.hotDealsHandle,
        if (tabs.isNotEmpty) tabs.first.collectionHandle,
      };
      return Future.wait(
        handles.map((h) => getProductsByCollectionPaginated(h, first: 20)),
      );
    });
    // The hero banner is the first thing on screen; download its images too,
    // into the same disk cache CachedNetworkImage reads from.
    final banners = getHomeBanners().then(
      (list) => Future.wait([
        for (final b in list)
          if (b.imageUrl != null)
            DefaultCacheManager()
                .getSingleFile(
                  b.imageUrl!,
                  headers: ShopifyConstants.imageHeaders,
                )
                .then((_) {}, onError: (_) {}),
      ]),
    );
    await Future.wait([
      banners,
      getExploreCategoriesContent(),
      getPromoBlocks(),
      getShopTheLookEntries(),
      getOccasionTilesContent(),
      getFeatureBanners(),
      explore,
    ]);
  }

  Future<List<ShopifyProduct>> getProductsByCollection(
    String handle, {
    int first = 24,
  }) async {
    final response = await getProductsByCollectionPaginated(
      handle,
      first: first,
    );
    return response.products;
  }

  Future<PaginatedProductsResponse> getProductsByCollectionPaginated(
    String handle, {
    int first = 24,
    String? after,
    String sortKey = 'COLLECTION_DEFAULT',
    bool reverse = false,
    List<String> filters = const [],
  }) {
    final filterKey = filters.join('|');
    return _cachedFetch(
      'collection:$handle:$first:${after ?? ''}:$sortKey:$reverse:$filterKey',
      () => _fetchProductsByCollectionPaginated(
        handle,
        first: first,
        after: after,
        sortKey: sortKey,
        reverse: reverse,
        filters: filters,
      ),
    );
  }

  Future<PaginatedProductsResponse> _fetchProductsByCollectionPaginated(
    String handle, {
    int first = 24,
    String? after,
    String sortKey = 'COLLECTION_DEFAULT',
    bool reverse = false,
    List<String> filters = const [],
  }) async {
    const String query = r'''
    query getCollectionProducts(
      $handle: String!
      $first: Int!
      $after: String
      $sortKey: ProductCollectionSortKeys
      $reverse: Boolean
      $filters: [ProductFilter!]
    ) {
      collectionByHandle(handle: $handle) {
        products(
          first: $first
          after: $after
          sortKey: $sortKey
          reverse: $reverse
          filters: $filters
        ) {
          filters {
            id
            label
            type
            values {
              id
              label
              count
              input
            }
          }
          edges {
            cursor
            node {
              id
              title
              handle
              priceRange { minVariantPrice { amount currencyCode } }
              compareAtPriceRange { minVariantPrice { amount currencyCode } }
              images(first: 10) { edges { node { url(transform: {maxWidth: 800}) altText } } }
              groupData: metafield(namespace: "vkcl", key: "group_data") { value }
              options {
                name
                values
                optionValues { name swatch { color } }
              }
              variants(first: 10) {
                edges {
                  node {
                    id
                    title
                    availableForSale
                    selectedOptions { name value }
                  }
                }
              }
            }
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    }
    ''';

    try {
      final decodedFilters = filters
          .map((f) {
            try {
              return jsonDecode(f) as Map<String, dynamic>;
            } catch (_) {
              return null;
            }
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      final res = await ShopifyGraphQL.post(
        query,
        variables: {
          'handle': handle,
          'first': first,
          'after': after,
          'sortKey': sortKey,
          'reverse': reverse,
          'filters': decodedFilters,
        },
      );

      _log(
        'getProductsByCollectionPaginated [$handle, after=$after, sort=$sortKey, reverse=$reverse, filters=$filters] → ${res.statusCode}',
      );
      final decoded = res.body;

      if (decoded['errors'] != null) {
        _log('errors: ${decoded['errors']}');
        return const PaginatedProductsResponse(
          products: [],
          hasNextPage: false,
          endCursor: null,
        );
      }

      final collection = decoded['data']?['collectionByHandle'];
      if (collection == null) {
        return const PaginatedProductsResponse(
          products: [],
          hasNextPage: false,
          endCursor: null,
        );
      }

      final productsMap = collection['products'] as Map<String, dynamic>?;
      final edges = (productsMap?['edges'] as List?) ?? [];
      final pageInfo = productsMap?['pageInfo'] as Map<String, dynamic>?;
      final filtersList = (productsMap?['filters'] as List?) ?? [];

      final products = edges
          .map((e) => ShopifyProduct.fromJson(e['node'] as Map<String, dynamic>))
          .toList();

      final parsedFilters = filtersList
          .map((f) => ShopifyFilter.fromJson(f as Map<String, dynamic>))
          .toList();

      return PaginatedProductsResponse(
        products: products,
        hasNextPage: pageInfo?['hasNextPage'] as bool? ?? false,
        endCursor: pageInfo?['endCursor'] as String?,
        filters: parsedFilters,
      );
    } catch (e) {
      _log('EXCEPTION in _fetchProductsByCollectionPaginated: $e');
      return const PaginatedProductsResponse(
        products: [],
        hasNextPage: false,
        endCursor: null,
      );
    }
  }

  Future<ShopifyProductDetail?> getProductByHandle(String handle) =>
      _cachedFetch(
        'product:$handle',
        () => _fetchProductByHandle(handle),
      );

    Future<ShopifyProductDetail?> _fetchProductByHandle(String handle) async {
    const String query = r'''
query getProduct($handle: String!, $identifiers: [HasMetafieldsIdentifier!]!) {
  productByHandle(handle: $handle) {
    id title handle description
    vendor
    productType
    tags
    collections(first: 10) { edges { node { id } } }
    priceRange { minVariantPrice { amount currencyCode } }
    compareAtPriceRange { minVariantPrice { amount currencyCode } }
    images(first: 10) { edges { node { url(transform: {maxWidth: 1600}) altText } } }
    options {
  name
  values
  optionValues {
    name
    swatch {
      color
      image { previewImage { url(transform: {maxWidth: 200}) } }
    }
  }
}
    variants(first: 50) {
      edges {
        node {
          id title availableForSale
          priceV2 { amount currencyCode }
          compareAtPriceV2 { amount currencyCode }
          selectedOptions { name value }
          metafields(identifiers: $identifiers) {
            namespace
            key
            value
            type
          }
        }
      }
    }
    shippingInfo: metafield(namespace: "custom", key: "shipping_info") { value }
    careInstructions: metafield(namespace: "custom", key: "care_instructions") { value }
  }
}
''';

    try {
      final res = await ShopifyGraphQL.post(
        query,
        variables: {
          'handle': handle,
          'identifiers': _variantMetafieldIdentifiers, // NEW
        },
      );
      _log('getProductByHandle [$handle] → ${res.statusCode}');
      final decoded = res.body;
      if (decoded['errors'] != null || decoded['data'] == null) return null;
      final node = decoded['data']['productByHandle'];
      _log('RAW options: ${node['options']}');
final rawVariantEdges = (node['variants']?['edges'] as List?) ?? [];
_log('RAW variant count: ${rawVariantEdges.length}');
for (final e in rawVariantEdges) {
  final v = e['node'];
  _log('RAW variant: id=${v['id']} title=${v['title']} selectedOptions=${v['selectedOptions']}');
}

      if (node == null) return null;
      return ShopifyProductDetail.fromJson(node as Map<String, dynamic>);
    } catch (e) {
      _log('getProductByHandle EXCEPTION: $e');
      return null;
    }
  }

  /// Fetches the sibling products in the same Variant King / SA Variants
  /// color group as [handle] (metafield `vkcl.group_data` on the Product).
  /// Returns an empty list if the product has no group, or the metafield
  /// isn't present. The current product's own handle is excluded from the
  /// result — this is *other* colors only.
  Future<List<ShopifyProduct>> getColorGroupSiblings(String handle) =>
      _cachedFetch(
        'colorSiblings:$handle',
        () => _fetchColorGroupSiblings(handle),
      );

  Future<List<ShopifyProduct>> _fetchColorGroupSiblings(String handle) async {
    const String groupQuery = r'''
    query getGroupData($handle: String!) {
      productByHandle(handle: $handle) {
        groupData: metafield(namespace: "vkcl", key: "group_data") {
          value
        }
      }
    }
    ''';

    try {
      final res = await ShopifyGraphQL.post(
        groupQuery,
        variables: {'handle': handle},
      );
      _log('getColorGroupSiblings [$handle] → ${res.statusCode}');
      final decoded = res.body;

      if (decoded['errors'] != null || decoded['data'] == null) {
        _log('getColorGroupSiblings errors: ${decoded['errors']}');
        return [];
      }

      final rawValue =
          decoded['data']['productByHandle']?['groupData']?['value']
              as String?;
      if (rawValue == null || rawValue.isEmpty) {
        // No color group on this product — perfectly normal.
        return [];
      }

      final parsed = jsonDecode(rawValue);
      if (parsed is! List || parsed.isEmpty) return [];

      // The app writes one group per product; take the first entry.
      final group = ColorGroup.fromJson(parsed.first as Map<String, dynamic>);

      final siblingHandles = group.products
          .map((p) => p.handle)
          .where((h) => h.isNotEmpty && h != handle)
          .toSet()
          .toList();

      if (siblingHandles.isEmpty) return [];

      return _fetchProductsByHandles(siblingHandles);
    } catch (e) {
      _log('_fetchColorGroupSiblings EXCEPTION: $e');
      return [];
    }
  }

  /// Batches a lightweight fetch (title, image, price, options/variants)
  /// for several products by handle in a single aliased GraphQL request —
  /// aliased per handle.
  Future<List<ShopifyProduct>> _fetchProductsByHandles(
    List<String> handles,
  ) async {
    final buffer = StringBuffer('query getProductsByHandles {\n');
    for (int i = 0; i < handles.length; i++) {
      final safeHandle = handles[i].replaceAll('"', r'\"');
      buffer.write('  p$i: productByHandle(handle: "$safeHandle") {\n');
      buffer.write('    id title handle\n');
      buffer.write(
          '    priceRange { minVariantPrice { amount currencyCode } }\n');
      buffer.write(
          '    compareAtPriceRange { minVariantPrice { amount currencyCode } }\n');
      buffer.write('    images(first: 1) { edges { node { url(transform: {maxWidth: 800}) altText } } }\n');
      buffer.write(
          '    options { name values optionValues { name swatch { color } } }\n');
      buffer.write('    variants(first: 10) {\n');
      buffer.write(
          '      edges { node { id title availableForSale selectedOptions { name value } } }\n');
      buffer.write('    }\n');
      buffer.write('  }\n');
    }
    buffer.write('}');

    try {
      final res = await ShopifyGraphQL.post(buffer.toString());
      _log('_fetchProductsByHandles [$handles] → ${res.statusCode}');
      final decoded = res.body;
      if (decoded['errors'] != null || decoded['data'] == null) {
        _log('_fetchProductsByHandles errors: ${decoded['errors']}');
        return [];
      }

      final data = decoded['data'] as Map<String, dynamic>;
      final products = <ShopifyProduct>[];
      for (int i = 0; i < handles.length; i++) {
        final node = data['p$i'];
        if (node != null) {
          products.add(ShopifyProduct.fromJson(node as Map<String, dynamic>));
        }
      }
      return products;
    } catch (e) {
      _log('_fetchProductsByHandles EXCEPTION: $e');
      return [];
    }
  }

  Future<List<HomeBanner>> getHomeBanners() =>
      _cachedFetch('homeBanners', _fetchHomeBanners);

  Future<List<HomeBanner>> _fetchHomeBanners() async {
    const String query = r'''
      query getHomeBanners {
        metaobjects(type: "home_banner", first: 10) {
          edges {
            node {
              id
              fields {
                key value
                reference {
                  ... on MediaImage { image { url(transform: {maxWidth: 1440}) } }
                }
              }
            }
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(query);
      _log('getHomeBanners → ${res.statusCode}');
      final decoded = res.body;

      if (decoded['errors'] != null || decoded['data'] == null) {
        _log('getHomeBanners errors: ${decoded['errors']}');
        return _staticBanners();
      }

      final edges = (decoded['data']['metaobjects']['edges'] as List?) ?? [];
      if (edges.isEmpty) return _staticBanners();

      return edges
          .map((e) => HomeBanner.fromMetaobjectJson(
                e['node'] as Map<String, dynamic>,
              ))
          .toList();
    } catch (e) {
      _log('getHomeBanners EXCEPTION: $e');
      return _staticBanners();
    }
  }

  Future<PaginatedProductsResponse> searchProductsPaginated(
    String query, {
    int first = 24,
    String? after,
    String sortKey = 'RELEVANCE',
    bool reverse = false,
    double? minPrice,
    double? maxPrice,
    List<String> filters = const [],
  }) {
    final filterKey = filters.join('|');
    final key =
        'searchPaged:${query.toLowerCase()}:$first:${after ?? ''}:$sortKey:$reverse:$minPrice:$maxPrice:$filterKey';
    return _cachedFetch(
      key,
      () => _fetchSearchProductsPaginated(
        query,
        first: first,
        after: after,
        sortKey: sortKey,
        reverse: reverse,
        minPrice: minPrice,
        maxPrice: maxPrice,
        filters: filters,
      ),
    );
  }

  /// The root `search` field only understands plain search terms — it does
  /// NOT support `products(query:)` syntax like `title:*shirt*` or
  /// `variants.price:>=X`. Sending that syntax makes Shopify ignore the
  /// terms and match the whole catalog, so every search returned the same
  /// results. Pass the user's text as-is; Shopify matches it against title,
  /// tags, product type, vendor and variant options (e.g. colors) and ranks
  /// by relevance.
  String _searchQueryString(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Shopify's `search` pads relevance results with loosely related items
  /// (e.g. "black shirt" → 663 hits, only ~70 actually black shirts, spread
  /// across the whole list). Keep a product only when every search word
  /// starts a word in its title, product type, tags or option values (so a
  /// color search also finds products whose color lives in the Color
  /// option). Matching at word starts (hyphens count as part of a word)
  /// keeps "shirt" from matching tees via "TSHIRTS" or a "T-SHIRT" tag.
  /// SKUs ("8903891802796-RJ6572-MED_BLUE-30") are split on hyphens so the
  /// style number (RJ6572) is its own word and a style-no search matches.
  bool _matchesSearchWords(Map<String, dynamic> node, List<RegExp> words) {
    if (words.isEmpty) return true;
    final variantEdges = (node['variants'] as Map?)?['edges'] as List?;
    final haystack = [
      node['title'],
      node['productType'],
      ...((node['tags'] as List?) ?? const []),
      for (final opt in (node['options'] as List?) ?? const [])
        ...(((opt as Map)['values'] as List?) ?? const []),
      for (final edge in variantEdges ?? const [])
        ...?((edge as Map)['node']?['sku'] as String?)?.split('-'),
    ].whereType<String>().join(' ');
    return words.every((w) => w.hasMatch(haystack));
  }

  List<RegExp> _searchWordPatterns(String raw) => raw
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => RegExp(
            '(^|[^a-z0-9-])${RegExp.escape(w)}',
            caseSensitive: false,
          ))
      .toList();

  // Raw page size pulled from Shopify per request while collecting filtered
  // matches — larger than a UI page so sparse queries need fewer round trips.
  static const int _kSearchScanPageSize = 100;

  Future<PaginatedProductsResponse> _fetchSearchProductsPaginated(
    String query, {
    int first = 24,
    String? after,
    String sortKey = 'RELEVANCE',
    bool reverse = false,
    double? minPrice,
    double? maxPrice,
    List<String> filters = const [],
  }) async {
    // Uses the root `search` field rather than `products`: `products(query:)`
    // never computes facets (its `filters` connection field is always empty),
    // while `search` supports both `productFilters` (server-side filtering)
    // and returns real facet counts, matching collection browsing behavior.
    // Trade-off: SearchSortKeys only defines RELEVANCE and PRICE, so callers
    // must restrict sortKey to one of those while in search mode.
    const String gqlQuery = r'''
    query searchProductsPaginated(
      $query: String!
      $first: Int!
      $after: String
      $sortKey: SearchSortKeys
      $reverse: Boolean
      $productFilters: [ProductFilter!]
    ) {
      search(
        query: $query
        first: $first
        after: $after
        sortKey: $sortKey
        reverse: $reverse
        types: [PRODUCT]
        prefix: LAST
        productFilters: $productFilters
      ) {
        productFilters {
          id
          label
          type
          values {
            id
            label
            count
            input
          }
        }
        edges {
          cursor
          node {
            ... on Product {
              id
              title
              handle
              createdAt
              productType
              tags
              priceRange { minVariantPrice { amount currencyCode } }
              compareAtPriceRange { minVariantPrice { amount currencyCode } }
              images(first: 2) { edges { node { url(transform: {maxWidth: 800}) altText } } }
              groupData: metafield(namespace: "vkcl", key: "group_data") { value }
              options {
                name
                values
                optionValues { name swatch { color } }
              }
              variants(first: 10) {
                edges {
                  node {
                    id
                    title
                    sku
                    availableForSale
                    selectedOptions { name value }
                  }
                }
              }
            }
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
    ''';

    const empty = PaginatedProductsResponse(
      products: [],
      hasNextPage: false,
      endCursor: null,
    );

    try {
      final decodedFilters = filters
          .map((f) {
            try {
              return jsonDecode(f) as Map<String, dynamic>;
            } catch (_) {
              return null;
            }
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      // Price bounds go through productFilters since `search` has no
      // query-string syntax for them.
      if (minPrice != null || maxPrice != null) {
        decodedFilters.add({
          'price': {
            'min': ?minPrice,
            'max': ?maxPrice,
          },
        });
      }

      final words = _searchWordPatterns(query);
      final products = <ShopifyProduct>[];
      List<ShopifyFilter>? parsedFilters;
      String? cursor = after;
      bool hasNextPage = true;

      // Keep scanning raw pages until we've collected at least `first` real
      // matches or Shopify runs out, so a page of mostly-unrelated padding
      // never comes back empty and stalls infinite scroll. Whole raw pages
      // are consumed, so the returned cursor never skips a match.
      while (products.length < first && hasNextPage) {
        final res = await ShopifyGraphQL.post(
          gqlQuery,
          variables: {
            'query': _searchQueryString(query),
            'first': _kSearchScanPageSize,
            'after': cursor,
            'sortKey': sortKey,
            'reverse': reverse,
            'productFilters': decodedFilters,
          },
        );

        _log(
          'searchProductsPaginated [$query, after=$cursor, sort=$sortKey, reverse=$reverse, filters=$filters] → ${res.statusCode}',
        );
        final decoded = res.body;

        if (decoded['errors'] != null || decoded['data'] == null) {
          _log('searchProductsPaginated errors: ${decoded['errors']}');
          if (products.isEmpty) return empty;
          break;
        }

        final searchMap = decoded['data']?['search'] as Map<String, dynamic>?;
        final edges = (searchMap?['edges'] as List?) ?? [];
        final pageInfo = searchMap?['pageInfo'] as Map<String, dynamic>?;

        parsedFilters ??= ((searchMap?['productFilters'] as List?) ?? [])
            .map((f) => ShopifyFilter.fromJson(f as Map<String, dynamic>))
            .toList();

        products.addAll(edges
            .map((e) => e['node'] as Map<String, dynamic>?)
            .where((node) =>
                node != null &&
                node.isNotEmpty &&
                _matchesSearchWords(node, words))
            .map((node) => ShopifyProduct.fromJson(node!)));

        hasNextPage = pageInfo?['hasNextPage'] as bool? ?? false;
        cursor = pageInfo?['endCursor'] as String?;
      }

      return PaginatedProductsResponse(
        products: products,
        hasNextPage: hasNextPage,
        endCursor: cursor,
        filters: parsedFilters ?? const [],
      );
    } catch (e) {
      _log('searchProductsPaginated EXCEPTION: $e');
      return empty;
    }
  }

  List<HomeBanner> _staticBanners() => [
        const HomeBanner(
          id: 'static_1',
          imageUrl: null,
          title: 'DEFINE\nYOUR\nVIBE.',
          subtitle: 'NEW COLLECTION',
        ),
      ];

  /// Banners for the Collections page (`collections_banner` metaobjects,
  /// "Collections Banner" in Shopify), separate from Home's hero banners.
  Future<List<HomeBanner>> getCollectionsBanners() =>
      _cachedFetch('collectionsBanners', _fetchCollectionsBanners);

  Future<List<HomeBanner>> _fetchCollectionsBanners() async {
    const String query = r'''
      query getCollectionsBanners {
        metaobjects(type: "collections_banner", first: 20) {
          edges {
            node {
              id
              image: field(key: "image") { reference { ... on MediaImage { image { url(transform: {maxWidth: 1440}) width height } } } }
              link: field(key: "link") { value }
              sort_order: field(key: "sort_order") { value }
            }
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(query);
      _log('getCollectionsBanners → ${res.statusCode}');
      if (res.hasErrors || res.data == null) return [];

      final nodes = ((res.data!['metaobjects']['edges'] as List?) ?? [])
          .map((e) => e['node'] as Map<String, dynamic>)
          .toList();
      int order(Map<String, dynamic> n) =>
          int.tryParse(n['sort_order']?['value']?.toString() ?? '') ?? 0;
      return _sortedStable(nodes, order)
          .map(HomeBanner.fromCollectionsBannerJson)
          .where((b) => b.imageUrl != null)
          .toList();
    } catch (e) {
      _log('getCollectionsBanners EXCEPTION: $e');
      return [];
    }
  }

  Future<List<PromoBlockContent>> getPromoBlocks() =>
      _cachedFetch('promoBlocks', _fetchPromoBlocks);

  Future<List<PromoBlockContent>> _fetchPromoBlocks() async {
    const String query = r'''
      query getPromoBlocks {
        metaobjects(type: "promo_block", first: 20) {
          edges {
            node {
              id
              image: field(key: "image") { reference { ... on MediaImage { image { url(transform: {maxWidth: 1440}) width height } } } }
              label: field(key: "label") { value }
              button_label: field(key: "button_label") { value }
              collection_handle: field(key: "collection_handle") { value }
              sort_order: field(key: "sort_order") { value }
            }
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(query);
      _log('getPromoBlocks → ${res.statusCode}');
      if (res.hasErrors || res.data == null) return [];

      final edges = (res.data!['metaobjects']['edges'] as List?) ?? [];
      final blocks = edges
          .map((e) =>
              PromoBlockContent.fromMetaobjectJson(e['node'] as Map<String, dynamic>))
          .toList();
      blocks.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return blocks;
    } catch (e) {
      _log('getPromoBlocks EXCEPTION: $e');
      return [];
    }
  }

  /// Sorts by `sort_order`, keeping creation order (the query's `id` sort)
  /// for ties, so a newly added entry lands after the existing ones.
  static List<T> _sortedStable<T>(List<T> items, int Function(T) sortOrder) {
    final indexed = items.asMap().entries.toList()
      ..sort((a, b) {
        final c = sortOrder(a.value).compareTo(sortOrder(b.value));
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  Future<List<FeatureBannerContent>> getFeatureBanners() =>
      _cachedFetch('featureBanners', _fetchFeatureBanners);

  Future<List<FeatureBannerContent>> _fetchFeatureBanners() async {
    const String query = r'''
      query getFeatureBanners {
        metaobjects(type: "feature_banner", first: 20, sortKey: "id") {
          edges {
            node {
              id
              image: field(key: "image") { reference { ... on MediaImage { image { url(transform: {maxWidth: 1440}) width height } } } }
              label: field(key: "label") { value }
              button_label: field(key: "button_label") { value }
              link: field(key: "link") { value }
              sort_order: field(key: "sort_order") { value }
            }
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(query);
      _log('getFeatureBanners → ${res.statusCode}');
      if (res.hasErrors || res.data == null) return [];

      final edges = (res.data!['metaobjects']['edges'] as List?) ?? [];
      final banners = edges
          .map((e) => FeatureBannerContent.fromMetaobjectJson(
              e['node'] as Map<String, dynamic>))
          .where((b) => b.imageUrl != null)
          .toList();
      return _sortedStable(banners, (b) => b.sortOrder);
    } catch (e) {
      _log('getFeatureBanners EXCEPTION: $e');
      return [];
    }
  }

  Future<List<ShopTheLookEntry>> getShopTheLookEntries() =>
      _cachedFetch('shopTheLookEntries', _fetchShopTheLookEntries);

  Future<List<ShopTheLookEntry>> _fetchShopTheLookEntries() async {
    const String query = r'''
      query getShopTheLook {
        metaobjects(type: "shop_the_look", first: 100) {
          edges {
            node {
              id
              image: field(key: "image") { reference { ... on MediaImage { image { url(transform: {maxWidth: 1440}) } } } }
              sort_order: field(key: "sort_order") { value }
              products: field(key: "products") {
                references(first: 6) {
                  edges {
                    node {
                      ... on Product {
                        id
                        title
                        handle
                        priceRange { minVariantPrice { amount currencyCode } }
                        compareAtPriceRange { minVariantPrice { amount currencyCode } }
                        images(first: 4) { edges { node { url(transform: {maxWidth: 800}) altText } } }
                        options { name values optionValues { name swatch { color } } }
                        variants(first: 10) {
                          edges { node { id title availableForSale selectedOptions { name value } } }
                        }
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
      final res = await ShopifyGraphQL.post(query);
      _log('getShopTheLookEntries → ${res.statusCode}');
      if (res.hasErrors || res.data == null) return [];

      final edges = (res.data!['metaobjects']['edges'] as List?) ?? [];
      final entries = edges
          .map((e) =>
              ShopTheLookEntry.fromMetaobjectJson(e['node'] as Map<String, dynamic>))
          .toList();
      entries.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return entries;
    } catch (e) {
      _log('getShopTheLookEntries EXCEPTION: $e');
      return [];
    }
  }

  Future<List<OccasionTileContent>> getOccasionTilesContent() =>
      _cachedFetch('occasionTiles', _fetchOccasionTiles);

  Future<List<OccasionTileContent>> _fetchOccasionTiles() async {
    const String query = r'''
      query getOccasionTiles {
        metaobjects(type: "occasion_tile", first: 20) {
          edges {
            node {
              id
              image: field(key: "image") { reference { ... on MediaImage { image { url(transform: {maxWidth: 1440}) } } } }
              label: field(key: "label") { value }
              collection_handle: field(key: "collection_handle") { value }
              sort_order: field(key: "sort_order") { value }
            }
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(query);
      _log('getOccasionTilesContent → ${res.statusCode}');
      if (res.hasErrors || res.data == null) return [];

      final edges = (res.data!['metaobjects']['edges'] as List?) ?? [];
      final tiles = edges
          .map((e) => OccasionTileContent.fromMetaobjectJson(
              e['node'] as Map<String, dynamic>))
          .toList();
      tiles.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return tiles;
    } catch (e) {
      _log('getOccasionTilesContent EXCEPTION: $e');
      return [];
    }
  }

  Future<List<ExploreCategoryContent>> getExploreCategoriesContent() =>
      _cachedFetch('exploreCategoriesContent', _fetchExploreCategoriesContent);

  Future<List<ExploreCategoryContent>> _fetchExploreCategoriesContent() async {
    const String query = r'''
      query getExploreCategories {
        metaobjects(type: "explore_category", first: 30) {
          edges {
            node {
              id
              image: field(key: "image") { reference { ... on MediaImage { image { url(transform: {maxWidth: 1440}) } } } }
              label: field(key: "label") { value }
              collection_handle: field(key: "collection_handle") { value }
              section: field(key: "section") { value }
              sort_order: field(key: "sort_order") { value }
            }
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(query);
      _log('getExploreCategoriesContent → ${res.statusCode}');
      if (res.hasErrors || res.data == null) return [];

      final edges = (res.data!['metaobjects']['edges'] as List?) ?? [];
      final categories = edges
          .map((e) => ExploreCategoryContent.fromMetaobjectJson(
              e['node'] as Map<String, dynamic>))
          .toList();
      categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return categories;
    } catch (e) {
      _log('getExploreCategoriesContent EXCEPTION: $e');
      return [];
    }
  }

  Future<List<ExploreTabContent>> getExploreTabs() =>
      _cachedFetch('exploreTabs', _fetchExploreTabs);

  Future<List<ExploreTabContent>> _fetchExploreTabs() async {
    const String query = r'''
      query getExploreTabs {
        metaobjects(type: "explore_tab", first: 20) {
          edges {
            node {
              id
              label: field(key: "label") { value }
              collection_handle: field(key: "collection_handle") { value }
              sort_order: field(key: "sort_order") { value }
            }
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(query);
      _log('getExploreTabs → ${res.statusCode}');
      if (res.hasErrors || res.data == null) return [];

      final edges = (res.data!['metaobjects']['edges'] as List?) ?? [];
      final tabs = edges
          .map((e) => ExploreTabContent.fromMetaobjectJson(
              e['node'] as Map<String, dynamic>))
          .where((t) =>
              t.label.trim().isNotEmpty && t.collectionHandle.trim().isNotEmpty)
          .toList();
      return _sortedStable(tabs, (t) => t.sortOrder);
    } catch (e) {
      _log('getExploreTabs EXCEPTION: $e');
      return [];
    }
  }

  /// All `product_page_banner` entries as collection handle → image URL.
  Future<Map<String, String>> getProductPageBanners() =>
      _cachedFetch('productPageBanners', _fetchProductPageBanners);

  Future<Map<String, String>> _fetchProductPageBanners() async {
    const String query = r'''
      query getProductPageBanners {
        metaobjects(type: "product_page_banner", first: 100) {
          edges {
            node {
              collection_handle: field(key: "collection_handle") { value }
              image: field(key: "image") { reference { ... on MediaImage { image { url(transform: {maxWidth: 1440}) } } } }
            }
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(query);
      _log('getProductPageBanners → ${res.statusCode}');
      if (res.hasErrors || res.data == null) return {};

      final edges = (res.data!['metaobjects']['edges'] as List?) ?? [];
      final Map<String, String> banners = {};
      for (final e in edges) {
        final node = e['node'] as Map<String, dynamic>;
        final String handle = _normalizeHandle(
            node['collection_handle']?['value'] as String? ?? '');
        final String? url =
            node['image']?['reference']?['image']?['url'] as String?;
        if (handle.isNotEmpty && url != null) banners[handle] = url;
      }
      return banners;
    } catch (e) {
      _log('getProductPageBanners EXCEPTION: $e');
      return {};
    }
  }

  /// The signed-out Profile screen's photo, from the first `welcome_image`
  /// metaobject. Null when there is no entry, so the screen falls back to
  /// the bundled image.
  Future<String?> getWelcomeImage() =>
      _cachedFetch('welcomeImage', _fetchWelcomeImage);

  Future<String?> _fetchWelcomeImage() async {
    const String query = r'''
      query getWelcomeImage {
        metaobjects(type: "welcome_image", first: 1) {
          edges {
            node {
              image: field(key: "image") { reference { ... on MediaImage { image { url(transform: {maxWidth: 1440}) } } } }
            }
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(query);
      _log('getWelcomeImage → ${res.statusCode}');
      if (res.hasErrors || res.data == null) return null;
      final edges = (res.data!['metaobjects']?['edges'] as List?) ?? [];
      if (edges.isEmpty) return null;
      return edges.first['node']?['image']?['reference']?['image']?['url']
          as String?;
    } catch (e) {
      _log('getWelcomeImage EXCEPTION: $e');
      return null;
    }
  }

  /// "SHIRTS", "shirts " or "https://…/collections/shirts?x" → "shirts".
  static String _normalizeHandle(String raw) {
    String value = raw.trim();
    final int idx = value.indexOf('/collections/');
    if (idx >= 0) value = value.substring(idx + '/collections/'.length);
    return value.split(RegExp(r'[/?#]')).first.trim().toLowerCase();
  }

  /// The Explore Categories / Collections tab taxonomy: section → group →
  /// item. Built live from the Shopify navigation menus
  /// [ShopifyConstants.exploreMenuHandles] ("top-wear", "bottom-wear"), so
  /// editing those menus in Shopify admin updates the app on the next
  /// launch or pull-to-refresh. Falls back to the pinned
  /// [ShopifyConstants.exploreMenuSections] if the menus can't be loaded.
  ///
  /// Tabs built from "Shop By Category Image" entries (those with a Tab and
  /// Group set) come first and replace the menu tab of the same name.
  Future<List<ShopMenuSection>> getExploreMenuSections() => _cachedFetch(
        'exploreMenuSections',
        () async {
          final cardsFuture = _fetchExploreSectionsFromCategoryCards();
          final live = await _fetchExploreMenuSectionsFromMenus();
          final menus = live.isNotEmpty ? live : await _fetchExploreMenuSections();
          final cards = await cardsFuture;
          final cardTabs = {for (final s in cards) s.title.toLowerCase()};
          return [
            ...cards,
            ...menus.where((m) => !cardTabs.contains(m.title.toLowerCase())),
          ];
        },
      );

  /// Shop By Category tabs from the `category_card_image` metaobject: each
  /// entry is one card, grouped by its `tab` then `group` fields in order
  /// of `sort_order`, then the order entries were added. Entries without a
  /// tab or group only override card images (see [_fetchCategoryCardImages]).
  Future<List<ShopMenuSection>> _fetchExploreSectionsFromCategoryCards() async {
    const String query = r'''
      query getCategoryCards {
        metaobjects(type: "category_card_image", first: 250, sortKey: "id") {
          edges {
            node {
              collection: field(key: "collection") { reference { ... on Collection { handle title } } }
              image: field(key: "image") { reference { ... on MediaImage { image { url(transform: {maxWidth: 1440}) } } } }
              tab: field(key: "tab") { value }
              group: field(key: "group") { value }
              title: field(key: "title") { value }
              sort_order: field(key: "sort_order") { value }
            }
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(query);
      _log('getCategoryCards → ${res.statusCode}');
      if (res.hasErrors || res.data == null) return [];

      String text(Map node, String key) =>
          ((node[key] as Map?)?['value'] as String? ?? '').trim();
      final cards = [
        for (final e in (res.data!['metaobjects']?['edges'] as List?) ?? [])
          e['node'] as Map<String, dynamic>,
      ].where((n) {
        final handle = n['collection']?['reference']?['handle'] as String?;
        return handle != null &&
            text(n, 'tab').isNotEmpty &&
            text(n, 'group').isNotEmpty;
      }).toList();

      // tab → group → cards, each keyed in first-seen order.
      final tabs = <String, Map<String, List<ShopMenuFit>>>{};
      for (final n in _sortedStable(
          cards, (n) => int.tryParse(text(n, 'sort_order')) ?? 0)) {
        final collection = n['collection']['reference'] as Map;
        final handle = collection['handle'] as String;
        final title = text(n, 'title').isNotEmpty
            ? text(n, 'title')
            : collection['title'] as String? ?? handle;
        tabs
            .putIfAbsent(_menuTitleCase(text(n, 'tab')), () => {})
            .putIfAbsent(_menuTitleCase(text(n, 'group')), () => [])
            .add(ShopMenuFit(
              title: _menuTitleCase(title),
              url: '/collections/$handle',
              collectionHandle: handle,
              imageUrl: n['image']?['reference']?['image']?['url'] as String?,
            ));
      }

      return [
        for (final tab in tabs.entries)
          ShopMenuSection(
            title: tab.key,
            handle: tab.key.toLowerCase().replaceAll(' ', '-'),
            categories: [
              for (final group in tab.value.entries)
                ShopMenuCategory(
                  title: group.key,
                  collectionHandle: '',
                  fits: group.value,
                ),
            ],
          ),
      ];
    } catch (e) {
      _log('_fetchExploreSectionsFromCategoryCards EXCEPTION: $e');
      return [];
    }
  }

  /// Menu item fields shared by every menu query below.
  static const String _menuItemFields =
      'title url resource { ... on Collection { handle } }';

  /// Each section menu (e.g. TOP WEAR) lists groups (SHIRTS, T-SHIRTS, ...)
  /// that link to collections. A group's items come from its own nested
  /// items in that menu when it has any; otherwise from the separate menu
  /// whose handle is the group's collection handle (Shopify suffixes
  /// duplicates, so `<handle>-1` is tried too — e.g. "tshirts-1").
  Future<List<ShopMenuSection>> _fetchExploreMenuSectionsFromMenus() async {
    final handles = ShopifyConstants.exploreMenuHandles;
    final sectionQuery = StringBuffer('query getExploreMenus {\n');
    for (int i = 0; i < handles.length; i++) {
      sectionQuery.write('  s$i: menu(handle: "${handles[i]}") {\n'
          '    title handle\n'
          '    items { $_menuItemFields items { $_menuItemFields } }\n'
          '  }\n');
    }
    sectionQuery.write('}');

    try {
      final res = await ShopifyGraphQL.post(sectionQuery.toString());
      _log('getExploreMenuSections (menus) → ${res.statusCode}');
      if (res.hasErrors || res.data == null) return [];

      final sectionMenus = <Map<String, dynamic>>[
        for (int i = 0; i < handles.length; i++)
          if (res.data!['s$i'] is Map<String, dynamic>)
            res.data!['s$i'] as Map<String, dynamic>,
      ];
      if (sectionMenus.isEmpty) return [];

      // Groups without nested items → look up their own menus in one call.
      final lookupHandles = <String>{};
      for (final menu in sectionMenus) {
        for (final group in (menu['items'] as List? ?? const [])) {
          if (((group as Map)['items'] as List? ?? const []).isNotEmpty) {
            continue;
          }
          final h = _menuItemHandle(group);
          if (h != null) lookupHandles.addAll([h, '$h-1']);
        }
      }
      final subMenus = await _fetchMenusByHandle(lookupHandles.toList());

      List<Map> groupItems(Map group) {
        final nested = (group['items'] as List? ?? const []).cast<Map>();
        if (nested.isNotEmpty) return nested;
        final h = _menuItemHandle(group);
        if (h == null) return const [];
        return subMenus[h] ?? subMenus['$h-1'] ?? const [];
      }

      final sections = sectionMenus.map((menu) {
        final groups = (menu['items'] as List? ?? const []).cast<Map>();
        return (
          title: _menuTitleCase(menu['title'] as String? ?? ''),
          handle: menu['handle'] as String? ?? '',
          groups: [for (final g in groups) (group: g, items: groupItems(g))],
        );
      }).toList();

      final imagesByHandle = await _fetchCollectionImagesByHandle({
        for (final s in sections)
          for (final g in s.groups) ...[
            _menuItemHandle(g.group),
            for (final item in g.items) _menuItemHandle(item),
          ],
      }.whereType<String>().toList());

      return sections.map((s) {
        return ShopMenuSection(
          title: s.title,
          handle: s.handle,
          categories: s.groups.map((g) {
            final groupHandle = _menuItemHandle(g.group) ?? '';
            return ShopMenuCategory(
              title: _menuTitleCase(g.group['title'] as String? ?? ''),
              collectionHandle: groupHandle,
              imageUrl: imagesByHandle[groupHandle],
              fits: g.items.map((item) {
                final itemHandle = _menuItemHandle(item);
                // Items like "/collections/chinos?fit=…" point back at the
                // group's own collection; leave the handle empty so the
                // screen filters the group by this item's title instead.
                final ownCollection =
                    itemHandle != null && itemHandle != groupHandle;
                return ShopMenuFit(
                  title: _menuTitleCase(item['title'] as String? ?? ''),
                  url: item['url'] as String? ?? '',
                  collectionHandle: ownCollection ? itemHandle : null,
                  imageUrl: ownCollection ? imagesByHandle[itemHandle] : null,
                );
              }).toList(),
            );
          }).toList(),
        );
      }).toList();
    } catch (e) {
      _log('_fetchExploreMenuSectionsFromMenus EXCEPTION: $e');
      return [];
    }
  }

  /// Items of each existing menu, keyed by handle, in one aliased request.
  Future<Map<String, List<Map>>> _fetchMenusByHandle(
      List<String> handles) async {
    if (handles.isEmpty) return {};
    final buffer = StringBuffer('query getSubMenus {\n');
    for (int i = 0; i < handles.length; i++) {
      final safeHandle = handles[i].replaceAll('"', r'\"');
      buffer.write(
          '  m$i: menu(handle: "$safeHandle") { items { $_menuItemFields } }\n');
    }
    buffer.write('}');

    try {
      final res = await ShopifyGraphQL.post(buffer.toString());
      if (res.hasErrors || res.data == null) return {};
      return {
        for (int i = 0; i < handles.length; i++)
          if (res.data!['m$i'] is Map)
            handles[i]:
                ((res.data!['m$i'] as Map)['items'] as List? ?? const [])
                    .cast<Map>(),
      };
    } catch (e) {
      _log('_fetchMenusByHandle EXCEPTION: $e');
      return {};
    }
  }

  /// Collection handle a menu item points at, from its linked resource or
  /// its `/collections/<handle>` URL; null for non-collection links.
  static String? _menuItemHandle(Map item) {
    final resourceHandle = (item['resource'] as Map?)?['handle'] as String?;
    if (resourceHandle != null && resourceHandle.isNotEmpty) {
      return resourceHandle;
    }
    final url = item['url'] as String? ?? '';
    if (!url.contains('/collections/')) return null;
    final handle = _normalizeHandle(url);
    return handle.isEmpty ? null : handle;
  }

  /// Menu titles are typed in caps in Shopify ("CARGO SHIRTS"); the app
  /// shows them as "Cargo Shirts" / "T-Shirts" / "Jann (Loose Stretch)".
  static String _menuTitleCase(String raw) {
    final lower = raw.trim().toLowerCase();
    return lower.replaceAllMapped(
      RegExp(r'(^|[\s\-(/&])([a-z])'),
      (m) => '${m[1]}${m[2]!.toUpperCase()}',
    );
  }

  Future<List<ShopMenuSection>> _fetchExploreMenuSections() async {
    final sectionDefs = ShopifyConstants.exploreMenuSections;
    final allHandles = <String>{
      for (final section in sectionDefs)
        for (final group in section['groups'] as List) ...[
          (group as Map)['handle'] as String,
          for (final item in group['items'] as List)
            (item as Map)['handle'] as String,
        ],
    }..remove('');

    final imagesByHandle =
        await _fetchCollectionImagesByHandle(allHandles.toList());

    return sectionDefs.map((section) {
      final categories = (section['groups'] as List).map((raw) {
        final group = raw as Map;
        final handle = group['handle'] as String;
        return ShopMenuCategory(
          title: group['title'] as String,
          collectionHandle: handle,
          imageUrl: imagesByHandle[handle],
          fits: (group['items'] as List).map((rawItem) {
            final item = rawItem as Map;
            final itemHandle = item['handle'] as String;
            return ShopMenuFit(
              title: item['title'] as String,
              url: '/collections/$itemHandle',
              collectionHandle: itemHandle,
              imageUrl: imagesByHandle[itemHandle],
            );
          }).toList(),
        );
      }).toList();

      final title = section['title'] as String;
      return ShopMenuSection(
        title: title,
        handle: title.toLowerCase().replaceAll(' ', '-'),
        categories: categories,
      );
    }).toList();
  }

  /// All `category_card_image` entries ("Shop By Category Image" in
  /// Shopify admin → Metaobjects) as collection handle → image URL.
  Future<Map<String, String>> _fetchCategoryCardImages() async {
    const String query = r'''
      query getCategoryCardImages {
        metaobjects(type: "category_card_image", first: 250) {
          edges {
            node {
              collection: field(key: "collection") { reference { ... on Collection { handle } } }
              image: field(key: "image") { reference { ... on MediaImage { image { url(transform: {maxWidth: 1440}) } } } }
            }
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(query);
      _log('getCategoryCardImages → ${res.statusCode}');
      if (res.hasErrors || res.data == null) return {};

      final edges = (res.data!['metaobjects']?['edges'] as List?) ?? [];
      final Map<String, String> images = {};
      for (final e in edges) {
        final node = e['node'] as Map<String, dynamic>;
        final String? handle =
            node['collection']?['reference']?['handle'] as String?;
        final String? url =
            node['image']?['reference']?['image']?['url'] as String?;
        if (handle != null && handle.isNotEmpty && url != null) {
          images[handle] = url;
        }
      }
      return images;
    } catch (e) {
      _log('getCategoryCardImages EXCEPTION: $e');
      return {};
    }
  }

  /// Image per collection handle for the Shop By Category cards, in order:
  /// its "Shop By Category Image" metaobject entry (set in the Shopify
  /// admin to override the card), the collection's own image, else its
  /// first product's. Handles with none are omitted.
  Future<Map<String, String>> _fetchCollectionImagesByHandle(
    List<String> handles,
  ) async {
    if (handles.isEmpty) return {};

    final cardImagesFuture = _fetchCategoryCardImages();
    final buffer = StringBuffer('query getCollectionImages {\n');
    for (int i = 0; i < handles.length; i++) {
      final safeHandle = handles[i].replaceAll('"', r'\"');
      buffer.write('  c$i: collection(handle: "$safeHandle") {\n');
      buffer.write('    image { url(transform: {maxWidth: 800}) }\n');
      buffer.write('    products(first: 1) { edges { node { featuredImage { url(transform: {maxWidth: 800}) } } } }\n');
      buffer.write('  }\n');
    }
    buffer.write('}');

    try {
      final res = await ShopifyGraphQL.post(buffer.toString());
      _log('getExploreMenuSections (images) → ${res.statusCode}');
      final cardImages = await cardImagesFuture;
      if (res.hasErrors || res.data == null) {
        return {
          for (final h in handles)
            if (cardImages[h] != null) h: cardImages[h]!,
        };
      }

      final data = res.data!;
      final Map<String, String> result = {};
      for (int i = 0; i < handles.length; i++) {
        final override = cardImages[handles[i]];
        if (override != null) {
          result[handles[i]] = override;
          continue;
        }
        final node = data['c$i'] as Map<String, dynamic>?;
        if (node == null) continue;
        String? url = node['image']?['url'] as String?;
        final edges = (node['products']?['edges'] as List?) ?? const [];
        if (url == null && edges.isNotEmpty) {
          final product = edges.first['node'] as Map?;
          url = product?['featuredImage']?['url'] as String?;
        }
        if (url != null) result[handles[i]] = url;
      }
      return result;
    } catch (e) {
      _log('_fetchCollectionImagesByHandle EXCEPTION: $e');
      return {};
    }
  }

  /// Every collection in the store, for the "Collections" page. Unlike
  /// [getExploreCategories]/[getOurCollectionTiles] (which are curated,
  /// hand-picked lists), this is the full catalog of collections as
  /// configured in Shopify.
  Future<List<ShopifyCollection>> getAllCollections({int first = 100}) =>
      _cachedFetch(
        'allCollections:$first',
        () => _fetchAllCollections(first),
      );

  Future<List<ShopifyCollection>> _fetchAllCollections(int first) async {
    const String query = r'''
      query getAllCollections($first: Int!) {
        collections(first: $first, sortKey: TITLE) {
          edges {
            node {
              id
              title
              handle
              image { url(transform: {maxWidth: 800}) altText }
            }
          }
        }
      }
    ''';

    try {
      final res =
          await ShopifyGraphQL.post(query, variables: {'first': first});
      _log('getAllCollections → ${res.statusCode}');
      if (res.hasErrors || res.data == null) {
        _log('getAllCollections errors: ${res.errors}');
        return [];
      }

      final edges = (res.data!['collections']?['edges'] as List?) ?? [];
      return edges.map((e) {
        final node = e['node'] as Map<String, dynamic>;
        return ShopifyCollection.fromJson(
          node,
          label: (node['title'] as String? ?? '').toUpperCase(),
        );
      }).toList();
    } catch (e) {
      _log('getAllCollections EXCEPTION: $e');
      return [];
    }
  }

  /// The store's terms, shipping, refund and privacy policies. Empty when the
  /// request failed (not cached, so opening the page again retries).
  Future<Map<ShopPolicyType, ShopPolicy>> getShopPolicies() =>
      _cachedFetch('shopPolicies', _fetchShopPolicies);

  Future<Map<ShopPolicyType, ShopPolicy>> _fetchShopPolicies() async {
    final fields = ShopPolicyType.values
        .map((t) => '${t.shopField} { title body }')
        .join(' ');
    final query = 'query getShopPolicies { shop { $fields } }';

    try {
      final res = await ShopifyGraphQL.post(query);
      _log('getShopPolicies → ${res.statusCode}');
      if (res.hasErrors || res.data == null) return {};

      final shop = res.data!['shop'] as Map<String, dynamic>? ?? {};
      return {
        for (final t in ShopPolicyType.values)
          if (shop[t.shopField] is Map<String, dynamic>)
            t: ShopPolicy.fromJson(shop[t.shopField] as Map<String, dynamic>),
      };
    } catch (e) {
      _log('getShopPolicies EXCEPTION: $e');
      return {};
    }
  }
}
