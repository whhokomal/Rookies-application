import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/models/cart_model.dart';
import 'package:rookies_jeans/models/product_detail_model.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/screens/products/size_chart_view.dart';
import 'package:rookies_jeans/services/product_pairings.dart';
import 'package:rookies_jeans/services/shopify_storefront_service.dart';
import 'package:rookies_jeans/services/wishlist_service.dart';
import 'package:rookies_jeans/services/recently_viewed_service.dart';
import 'package:rookies_jeans/services/cart_service.dart';
import 'package:rookies_jeans/screens/cart/cart.dart';
import 'package:rookies_jeans/screens/cart/checkout_flow.dart';
import 'package:rookies_jeans/widgets/price_text.dart';
import 'package:rookies_jeans/widgets/product_row_section.dart';

class ProductDetailPage extends StatefulWidget {
  final String handle;
  final String? heroImageUrl;
  final String title;

  const ProductDetailPage({
    super.key,
    required this.handle,
    required this.title,
    this.heroImageUrl,
  });

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  String _numericProductId(String gid) => gid.split('/').last;

  double _s(double base) =>
      Responsive.of(context, baseW: 400, maxScale: 1.25).s(base);
  static const double _maxContentWidth = AppLayout.maxContentMedium;

  ShopifyProductDetail? _product;
  bool _isLoading = true;
  String? _error;
  bool _isWishlisted = false;
  bool _isWishlistLoading = false;
  bool _isAddingToCart = false;
  bool _isBuyingNow = false;
  int _quantity = 1;
  static const int _maxQuantity = 10;

  // Mirrors widget.handle/title/heroImageUrl but is mutable, so tapping a
  // color swatch can swap the product shown on THIS page instead of
  // pushing a new route (the usual ecommerce "select a color" pattern).
  late String _currentHandle;
  late String _currentTitle;
  String? _currentHeroImageUrl;

  int _currentImageIndex = 0;
  final PageController _pageController = PageController();
  final ScrollController _scrollController = ScrollController();

  Map<String, String> _selectedOptions = {};
  ProductDetailVariant? _selectedVariant;

  List<ShopifyProduct> _goesWellWith = [];
  List<ShopifyProduct> _youMayAlsoLike = [];
  List<ShopifyProduct> _colorSiblings = [];
  int? _expandedTileIndex;

  // Kept alive across taps (and across re-fetches for the same product) so
  // that tapping "Size Chart" doesn't pay WebView cold-start + network cost
  // in the critical path — see `_prewarmSizeChart`.
  WebViewController? _sizeChartController;
  final ValueNotifier<bool> _sizeChartLoading = ValueNotifier<bool>(true);
  // true until an availability check (see `_checkSizeChartAvailable`) comes
  // back empty for this product — kept optimistic by default so the button
  // never disappears just because the check is slow or fails.
  final ValueNotifier<bool> _sizeChartAvailable = ValueNotifier<bool>(true);
  String? _sizeChartWarmedForHandle;

  /// Kiwi-issued source id identifying this app as the integration
  /// (per Kiwi support: https://intercom.help/kiwi-sizing-chart/en/articles/10291026).
  static const String _kiwiSourceId = 'testing_only';

  Uri _kiwiSizeChartUri(ShopifyProductDetail product) {
    final params = <String, String>{
      'shop': ShopifyConstants.shopDomain,
      'product': _numericProductId(product.id),
      'source': _kiwiSourceId,
    };
    if (product.vendor.isNotEmpty) params['vendor'] = product.vendor;
    if (product.productType.isNotEmpty) params['type'] = product.productType;
    if (product.tags.isNotEmpty) params['tags'] = product.tags.join(',');
    if (product.collectionIds.isNotEmpty) {
      params['collections'] = product.collectionIds.join(',');
    }
    return Uri.https('app.kiwisizing.com', '/size', params);
  }

  /// Per Kiwi's integration guide: probe the size chart URL first, and
  /// only show the "Size Chart" button if something is actually returned
  /// for this product.
  Future<void> _checkSizeChartAvailable(Uri uri, String forHandle) async {
    try {
      final res = await http
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (!mounted || _product?.handle != forHandle) return;
      final hasData = res.statusCode == 200 && res.body.trim().isNotEmpty;
      _sizeChartAvailable.value = hasData;
    } catch (e) {
      debugPrint('_checkSizeChartAvailable failed: $e');
      // Leave it visible on failure — don't hide a working feature because
      // of a flaky network check.
    }
  }

  // Never let a size-chart failure (e.g. no WebView platform implementation
  // on the current run target) bubble up and take down product loading —
  // this is a background optimization, not a page-critical operation.
  void _prewarmSizeChart() {
    if (_product == null) return;
    if (_sizeChartWarmedForHandle == _product!.handle &&
        _sizeChartController != null) {
      return;
    }
    try {
      final product = _product!;
      _sizeChartWarmedForHandle = product.handle;
      _sizeChartLoading.value = true;
      _sizeChartAvailable.value = true;

      final uri = _kiwiSizeChartUri(product);
      unawaited(_checkSizeChartAvailable(uri, product.handle));

      _sizeChartController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) => _sizeChartLoading.value = false,
          ),
        )
        ..loadRequest(uri);
    } catch (e) {
      debugPrint('_prewarmSizeChart failed: $e');
      _sizeChartController = null;
      _sizeChartWarmedForHandle = null;
    }
  }

  void _openSizeChart() {
    if (_product == null) return;
    _prewarmSizeChart(); // no-op if already warmed for this product
    final controller = _sizeChartController;
    if (controller == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Size chart is unavailable right now.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SizeChartView(
        controller: controller,
        loading: _sizeChartLoading,
      ),
    );
  }

  static const List<String> _descLabels = [
    'STYLE NO & COLOR', 'STYLE NO', 'COLLAR/NECK', 'COLLAR / NECK',
    'STRETCH METER', 'WASH CARE', 'FABRIC', 'SLEEVES', 'DESIGN',
    'OCCASION', 'PATTERN', 'POCKETS', 'CLOSURE', 'LENGTH',
    'COLOR', 'CARE', 'FIT',
  ];

  @override
  void initState() {
    super.initState();
    _currentHandle = widget.handle;
    _currentTitle = widget.title;
    _currentHeroImageUrl = widget.heroImageUrl;
    _fetchProduct();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    _sizeChartLoading.dispose();
    _sizeChartAvailable.dispose();
    super.dispose();
  }

  String _detectCategory() =>
      ProductPairings.detectCategory(_currentHandle, _currentTitle);

  Future<void> _fetchProduct() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final product = await ShopifyStorefrontService.instance
          .getProductByHandle(_currentHandle);

      if (!mounted) return;

      if (product == null) {
        setState(() {
          _error = 'Product not found.';
          _isLoading = false;
        });
        return;
      }

      final defaults = <String, String>{};
      for (final opt in product.options) {
        if (opt.values.isNotEmpty) {
          defaults[opt.name] = opt.values.first;
        }
      }

      setState(() {
        _product = product;
        _selectedOptions = defaults;
        _isWishlisted = WishlistService.instance.isWishlisted(product.id);
        _isLoading = false;
      });
      RecentlyViewedService.instance.record(_asListProduct(product));

debugPrint('=== PRODUCT DEBUG (${product.handle}) ===');
debugPrint('Options: ${product.options.length}');
for (final o in product.options) {
  debugPrint('  "${o.name}": ${o.values}');
}
debugPrint('Variants: ${product.variants.length}');
for (final v in product.variants) {
  final sel = v.selectedOptions.map((s) => '${s.name}=${s.value}').join(', ');
  debugPrint('  "${v.title}" | available=${v.availableForSale} | $sel');
}
debugPrint('==========================================');

      _updateVariant();
      _fetchRelatedProducts();
      _fetchColorSiblings();
      _prewarmSizeChart();
    } catch (e, st) {
      debugPrint('ProductDetailPage _fetchProduct error: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load product: $e';
        _isLoading = false;
      });
    }
  }

  /// Loads the other colors in this product's Variant King (`vkcl.group_data`)
  /// color family, if any, so they can be shown as swatches that jump to the
  /// sibling product's own page.
  Future<void> _fetchColorSiblings() async {
    if (_product == null) return;
    try {
      final siblings = await ShopifyStorefrontService.instance
          .getColorGroupSiblings(_product!.handle);
      if (!mounted) return;
      setState(() => _colorSiblings = siblings);
    } catch (e) {
      debugPrint('Color siblings fetch error: $e');
    }
  }

  Future<void> _fetchRelatedProducts() async {
    if (!mounted) return;

    final pairings =
        ProductPairings.goesWellWithCollections(_detectCategory());

    try {
      if (pairings.isNotEmpty) {
        final handle   = pairings.first;
        final products = await ShopifyStorefrontService.instance
            .getProductsByCollection(handle, first: 6);
        if (mounted) {
          setState(() => _goesWellWith = products
              .where((p) => p.handle != _currentHandle)
              .take(4)
              .toList());
        }
      }

      final similar = await ShopifyStorefrontService.instance
          .getProductsByCollection(_sameCollectionHandle(), first: 8);
      if (mounted) {
        final filtered = similar
            .where((p) => p.handle != _currentHandle)
            .toList()
          ..shuffle();
        setState(() => _youMayAlsoLike = filtered.take(6).toList());
      }
    } catch (e) {
      debugPrint('Related products fetch error: $e');
    }
  }

  String _sameCollectionHandle() =>
      ProductPairings.sameCollectionHandle(_detectCategory(), _currentHandle);

  void _updateVariant() {
    if (_product == null || _product!.variants.isEmpty) return;
    final match = _product!.variants.firstWhere(
      (v) => v.selectedOptions.every(
        (o) => _selectedOptions[o.name] == o.value,
      ),
      orElse: () => _product!.variants.first,
    );
    setState(() {
      if (match.id != _selectedVariant?.id) _quantity = 1;
      _selectedVariant = match;
    });
  }

  /// Card-sized copy of the detail product, for wishlist / recently viewed.
  ShopifyProduct _asListProduct(ShopifyProductDetail p) => ShopifyProduct(
        id: p.id,
        title: p.title,
        handle: p.handle,
        price: p.price,
        compareAtPrice: p.compareAtPrice,
        currencyCode: p.currencyCode,
        imageUrls: List<String>.from(p.imageUrls),
        variants: const [],
        options: const [],
      );

  Future<void> _toggleWishlist() async {
    if (_product == null || _isWishlistLoading) return;
    setState(() => _isWishlistLoading = true);
    try {
      WishlistService.instance.toggleProduct(_asListProduct(_product!));
      if (!mounted) return;
      setState(() =>
          _isWishlisted = WishlistService.instance.isWishlisted(_product!.id));
    } catch (e, st) {
      debugPrint('Wishlist toggle error: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Wishlist error: $e',
          style: const TextStyle(fontFamily: AppFonts.body),
        ),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _isWishlistLoading = false);
    }
  }

  Future<void> _shareProduct() async {
    final p = _product;
    if (p == null) return;
    final link = '${ShopifyConstants.storeUrl}/products/${p.handle}';
    // iPad shows the share sheet as a popover and needs an anchor rect, or
    // sharing fails there. Ignored on iPhone and Android.
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: 'Check out ${p.title} on Rookies Jeans\n$link',
        subject: p.title,
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  void _goToCart() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CartScreen()),
      );

  Future<void> _handleAddToCart() async {
    final variant = _selectedVariant;
    if (variant == null || _isAddingToCart) return;
    if (!variant.availableForSale) return;

    setState(() => _isAddingToCart = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final success = await CartService.instance
        .addLine(variantId: variant.id, quantity: _quantity);

    if (!mounted) return;
    setState(() => _isAddingToCart = false);
    messenger.showSnackBar(SnackBar(
      content: Text(
        success
            ? '${_product?.title ?? 'Item'} added to cart'
            : (CartService.instance.lastError ?? 'Failed to add item to cart'),
        style: const TextStyle(fontFamily: AppFonts.accent),
      ),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Checks out only the selected variant (at the chosen qty), leaving the app cart
  /// untouched — the checkout replaces the website cart with these lines.
  Future<void> _handleBuyNow() async {
    final product = _product;
    final variant = _selectedVariant;
    if (product == null || variant == null || _isBuyingNow) return;
    if (!variant.availableForSale) return;

    setState(() => _isBuyingNow = true);
    try {
      final placed = await runCheckoutFlow(context, lines: [
        ShopifyCartLine(
          lineId: '',
          variantId: variant.id,
          productTitle: product.title,
          productHandle: product.handle,
          variantTitle: variant.title,
          imageUrl: product.imageUrls.isNotEmpty ? product.imageUrls.first : null,
          price: variant.price ?? product.price,
          currencyCode: product.currencyCode,
          quantity: _quantity,
        ),
      ]);
      if (!mounted || !placed) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text(
            'Order placed successfully!',
            style: TextStyle(fontFamily: AppFonts.body),
          ),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
    } finally {
      if (mounted) setState(() => _isBuyingNow = false);
    }
  }

  /// Swaps in [product] as the one shown on THIS page — used when picking a
  /// different color from the same Variant King group — instead of pushing
  /// a new route. This is the familiar "tap a color swatch, the page
  /// updates in place" pattern most ecommerce apps use.
  Future<void> _switchProduct(ShopifyProduct product) async {
    if (product.handle == _currentHandle) return;

    setState(() {
      _currentHandle = product.handle;
      _currentTitle = product.title;
      _currentHeroImageUrl = product.primaryImageUrl;
      _currentImageIndex = 0;
      // Clear stale data from the previous product so nothing mismatched
      // flashes once loading finishes but before these re-fetch.
      _goesWellWith = [];
      _youMayAlsoLike = [];
      _colorSiblings = [];
      _selectedOptions = {};
      _selectedVariant = null;
      _expandedTileIndex = null;
    });

    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    await _fetchProduct();
  }

  void _openImageViewer(List<String> images) async {
    final returnedIndex = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenImageViewer(
          imageUrls: images,
          initialIndex: _currentImageIndex,
        ),
      ),
    );
    if (!mounted) return;
    if (returnedIndex != null && returnedIndex != _currentImageIndex) {
      _pageController.jumpToPage(returnedIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Scaffold(
      backgroundColor: AppColors.bg,
      body: _isLoading
          ? _loadingState()
          : _error != null
              ? _errorState()
              : _buildDetail(),
      ),
    );
  }

  Widget _buildDetail() {
    final p = _product!;
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _imageCarousel(p),
                  _infoSection(p),
                  if (_goesWellWith.isNotEmpty) ...[
                    const Divider(height: 1),
                    ProductRowSection(title: 'GOES WELL WITH', products: _goesWellWith),
                  ],
                  if (_youMayAlsoLike.isNotEmpty) ...[
                    const Divider(height: 1),
                    ProductRowSection(title: 'YOU MAY ALSO LIKE', products: _youMayAlsoLike),
                  ],
                  _recentlyViewedSection(p.id),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _imageCarousel(ShopifyProductDetail p) {
    final images = p.imageUrls;
    if (images.isEmpty) {
      return AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(children: [
          Container(
            color: AppColors.fieldFill,
            alignment: Alignment.center,
            child: Icon(Icons.image_not_supported_outlined,
                size: 52, color: AppColors.hint),
          ),
          _backButton(),
          _wishlistButton(),
          _shareButton(),
        ]),
      );
    }
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: Stack(children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                itemCount: images.length,
                onPageChanged: (i) => setState(() => _currentImageIndex = i),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _openImageViewer(images),
                  child: CachedNetworkImage(
                    imageUrl: images[i],
                    fit: BoxFit.cover,
                    placeholder: (_, _) =>
                        Container(color: AppColors.fieldFill),
                    errorWidget: (_, _, _) => Container(
                      color: AppColors.fieldFill,
                      alignment: Alignment.center,
                      child: Icon(Icons.image_not_supported_outlined,
                          size: 52, color: AppColors.hint),
                    ),
                  ),
                ),
              ),
            ),
            _backButton(),
            _wishlistButton(),
            _shareButton(),
          ]),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              images.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _currentImageIndex == i ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _currentImageIndex == i
                      ? AppColors.primary
                      : AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  /// Top of the overlay buttons. Follows the status bar / notch height so
  /// they never sit under the iPhone notch or Dynamic Island, which is
  /// taller than the Android status bar the old fixed offsets assumed.
  double get _overlayTop =>
      math.max(MediaQuery.paddingOf(context).top, 32.0) + 8;

  Widget _backButton() => Positioned(
        top: _overlayTop,
        left: 4,
        child: GestureDetector(
          // Opaque so taps anywhere in the box hit the button instead of
          // falling through to the image viewer underneath.
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.maybePop(context),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.arrow_back_ios_new_rounded,
                size: 22, color: AppColors.primary),
          ),
        ),
      );

  Widget _wishlistButton() => Positioned(
        top: _overlayTop + 8,
        right: 12,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleWishlist,
          child: SizedBox(
            width: 38,
            height: 38,
            child: _isWishlistLoading
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      _isWishlisted
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      key: ValueKey(_isWishlisted),
                      size: 20,
                      color: _isWishlisted ? Colors.red : Colors.white,
                    ),
                  ),
          ),
        ),
      );

  Widget _shareButton() => Positioned(
        top: _overlayTop + 50,
        right: 12,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _shareProduct,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              Icons.share_outlined,
              size: 20,
              color: AppColors.primary,
            ),
          ),
        ),
      );

        Widget _variantMetafieldsSection() {
    final metafields = _selectedVariant?.metafields ?? const [];
    if (metafields.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: metafields.map((m) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: _s(12),
                  color: AppColors.secondaryText,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: '${m.label}: ',
                    style: TextStyle(fontFamily: AppFonts.accent, color: AppColors.primary),
                  ),
                  TextSpan(text: m.formattedValue),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Maps common apparel color words to a display hex code. Keys are
  /// lowercase; two-word compounds (e.g. "light brown") are matched first,
  /// falling back to the base hue word alone. Extend this as new color
  /// names show up in your catalog.
  static const Map<String, String> _namedColorHex = {
    // compounds — checked before single words
    'light brown': 'B08968',
    'dark brown': '4A2C17',
    'light blue': 'A9C6E8',
    'dark blue': '1B3A6B',
    'light green': '9CC69B',
    'dark green': '234D35',
    'light grey': 'C9C9C9',
    'light gray': 'C9C9C9',
    'dark grey': '4B4B4B',
    'dark gray': '4B4B4B',
    'off white': 'F5F1E8',
    'navy blue': '000080',
    'sky blue': '87CEEB',
    'royal blue': '2551A6',
    'baby pink': 'F7C9D6',
    'hot pink': 'F0508A',
    'dark red': '8B1E1E',
    // single words
    'white': 'FFFFFF',
    'black': '000000',
    'grey': '808080',
    'gray': '808080',
    'charcoal': '36454F',
    'navy': '000080',
    'blue': '2A4B7C',
    'skyblue': '87CEEB',
    'red': 'C1272D',
    'maroon': '800000',
    'wine': '722F37',
    'burgundy': '800020',
    'green': '2E5339',
    'olive': '708238',
    'khaki': 'C3B091',
    'beige': 'D8C4A0',
    'cream': 'FFFDD0',
    'ivory': 'FFFFF0',
    'brown': '5B3A29',
    'tan': 'D2B48C',
    'mustard': 'E1AD01',
    'yellow': 'F2D51D',
    'orange': 'E2711D',
    'rust': 'B7410E',
    'pink': 'F6A6C1',
    'purple': '6A3FA0',
    'lavender': 'B497D6',
    'teal': '2F6D6D',
    'mint': 'A8E0C5',
    'coral': 'FF6F5E',
    'turquoise': '30D5C8',
    'gold': 'D4AF37',
    'silver': 'C0C0C0',
    'denim': '4A6D8C',
    'indigo': '3F3B6C',
  };

  /// Resolves a display color from free-text like an option value
  /// ("Light Brown") or a handle segment. Tries the full normalized string,
  /// then each word from the end backwards (the last word is usually the
  /// base hue, e.g. "dusty rose" -> "rose"). Returns null if nothing in
  /// [_namedColorHex] matches.
  Color? _colorFromName(String name) {
    final normalized =
        name.toLowerCase().trim().replaceAll(RegExp(r'[_\-]+'), ' ');
    if (_namedColorHex.containsKey(normalized)) {
      return _hexToColor(_namedColorHex[normalized]!);
    }
    final words = normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    for (final w in words.reversed) {
      if (_namedColorHex.containsKey(w)) {
        return _hexToColor(_namedColorHex[w]!);
      }
    }
    return null;
  }

  /// Pulls a display color out of a Variant King child product's handle
  /// (e.g. "light-brown-extra-loose-fit-jeans-2233") by trying the first
  /// two hyphen-separated tokens as a compound color name, then the first
  /// token alone, against [_namedColorHex].
  Color? _colorFromHandle(String handle) {
    final tokens = handle.split('-');
    if (tokens.length >= 2) {
      final twoWord = '${tokens[0]} ${tokens[1]}'.toLowerCase();
      if (_namedColorHex.containsKey(twoWord)) {
        return _hexToColor(_namedColorHex[twoWord]!);
      }
    }
    if (tokens.isNotEmpty) {
      final hex = _namedColorHex[tokens.first.toLowerCase()];
      if (hex != null) return _hexToColor(hex);
    }
    return null;
  }

  /// Row of color swatches for the sibling products in this item's Variant
  /// King color group (see `_fetchColorSiblings`). Tapping a swatch that
  /// isn't the currently-open product swaps this same page over to that
  /// sibling (see `_switchProduct`) rather than pushing a new page.
  /// Each swatch shows the product's own photo; if a product has no image
  /// yet, it falls back to a guessed color code, then a plain letter.
  Widget _colorSiblingsSection() {
    if (_colorSiblings.isEmpty) return const SizedBox.shrink();
    final currentImageUrl = (_product?.imageUrls.isNotEmpty ?? false)
        ? _product!.imageUrls.first
        : _currentHeroImageUrl;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AVAILABLE COLORS',
            style: TextStyle(
              fontFamily: AppFonts.accent,
              fontSize: _s(11),
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _colorSiblingChip(
                title: _product?.title ?? _currentTitle,
                imageUrl: currentImageUrl,
                fallbackColor: _colorFromHandle(_currentHandle),
                isCurrent: true,
                onTap: null,
              ),
              for (final sibling in _colorSiblings)
                _colorSiblingChip(
                  title: sibling.title,
                  imageUrl: sibling.primaryImageUrl,
                  fallbackColor: sibling.colorHexCodes.isNotEmpty
                      ? _hexToColor(sibling.colorHexCodes.first)
                      : _colorFromHandle(sibling.handle),
                  isCurrent: false,
                  onTap: () => _switchProduct(sibling),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _colorSiblingChip({
    required String title,
    String? imageUrl,
    Color? fallbackColor,
    required bool isCurrent,
    VoidCallback? onTap,
  }) {
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 48,
        child: Column(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasImage ? null : (fallbackColor ?? AppColors.fieldFill),
                image: hasImage
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(imageUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
                border: Border.all(
                  color: isCurrent ? AppColors.primary : AppColors.border,
                  width: isCurrent ? 2 : 1,
                ),
              ),
              child: (!hasImage && fallbackColor == null)
                  ? Center(
                      child: Text(
                        title.isNotEmpty ? title[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontFamily: AppFonts.body,
                          fontSize: 10,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: _s(9),
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoSection(ShopifyProductDetail p) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.title,
            style: TextStyle(
              // Bebas Neue is condensed and has one weight, so it runs
              // larger than the body font and isn't bolded.
              fontFamily: AppFonts.subheading,
              fontSize: _s(30),
              letterSpacing: 0.5,
              color: AppColors.primary,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          _priceBlock(p),
          const SizedBox(height: 16),
          _colorSiblingsSection(),

          ...p.options
              .where((opt) => !opt.isColorOption)
              .map((opt) => _optionSelector(opt)),
_variantMetafieldsSection(),
          const SizedBox(height: 20),
          _availabilityChip(),
          const SizedBox(height: 20),
          _addToCartButton(),
          const SizedBox(height: 24),
          // const Divider(height: 1),
          if (p.description.isNotEmpty) ...[
            _descriptionTile(p.description, 0),
            const Divider(height: 1),
          ],
          _infoTile(
            'Shipping & Returns',
            (p.shippingInfo?.isNotEmpty ?? false)
                ? p.shippingInfo!
                : 'Free shipping on prepaid orders. Easy returns within 7 days.',
            1,
          ),
          const Divider(height: 1),
          _infoTile(
            'Care Instructions',
            (p.careInstructions?.isNotEmpty ?? false)
                ? p.careInstructions!
                : 'Machine wash cold. Do not bleach. Tumble dry low.',
            2,
          ),
          // const Divider(height: 1),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _preprocessDescription(String raw) {
    var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();

    final sorted = [..._descLabels]
      ..sort((a, b) => b.length.compareTo(a.length));
    final labelPattern = RegExp(
      r'\s*\b(' + sorted.map(RegExp.escape).join('|') + r')\s*:\s*',
      caseSensitive: false,
    );
    text = text.replaceAllMapped(
      labelPattern,
      (m) => '\n${m.group(1)!.toUpperCase()} : ',
    );

    text = text.replaceAll(RegExp(r'\s*\|\s*'), ' | ');
    text = text.replaceAll(RegExp(r'(\s*\|\s*)?"?\s*$', multiLine: true), '');
    text = text.replaceAll(RegExp(r'\s+$', multiLine: true), '');

    return text.trim();
  }

  Widget _descriptionTile(String raw, int index) {
    final cleaned = _preprocessDescription(raw);
    final lines =
        cleaned.split('\n').where((l) => l.trim().isNotEmpty).toList();

    final children = <Widget>[];
    for (final line in lines) {
      final trimmed = line.trim().replaceFirst(RegExp(r'^[•\-]\s*'), '');
      final hasLabel = RegExp(r'^[A-Za-z][A-Za-z\s&/]*:').hasMatch(trimmed);

      if (hasLabel) {
        final colonIdx = trimmed.indexOf(':');
        final label = trimmed.substring(0, colonIdx + 1).trim();
        final value = trimmed.substring(colonIdx + 1).trim();
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Icon(Icons.circle, size: 5, color: AppColors.secondaryText),
              ),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: _s(13),
                      color: AppColors.secondaryText,
                      height: 1.5,
                    ),
                    children: [
                      TextSpan(
                        text: '$label ',
                        style: TextStyle(
                          fontFamily: AppFonts.accent,
                          color: AppColors.primary,
                        ),
                      ),
                      TextSpan(text: value),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            trimmed,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: _s(13),
              color: AppColors.secondaryText,
              height: 1.6,
            ),
          ),
        ));
      }
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('tile-$index-${_expandedTileIndex == index}'),
        initiallyExpanded: _expandedTileIndex == index,
        onExpansionChanged: (expanded) {
          setState(() => _expandedTileIndex = expanded ? index : null);
        },
        tilePadding: EdgeInsets.zero,
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.secondaryText,
        title: Text(
          'Description',
          style: TextStyle(
            fontFamily: AppFonts.accent,
            fontSize: _s(14),
            color: AppColors.primary,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(String label, String content, int index) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('tile-$index-${_expandedTileIndex == index}'),
        initiallyExpanded: _expandedTileIndex == index,
        onExpansionChanged: (expanded) {
          setState(() => _expandedTileIndex = expanded ? index : null);
        },
        tilePadding: EdgeInsets.zero,
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.secondaryText,
        title: Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.accent,
            fontSize: _s(14),
            color: AppColors.primary,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                content,
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: _s(13),
                  color: AppColors.secondaryText,
                  height: 1.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Every product the customer has opened (saved across app restarts)
  /// except this one, newest first.
  Widget _recentlyViewedSection(String currentProductId) => ListenableBuilder(
        listenable: RecentlyViewedService.instance,
        builder: (context, _) {
          final items = RecentlyViewedService.instance.items
              .where((item) => item.id != currentProductId)
              .toList();
          if (items.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1),
              ProductRowSection(title: 'RECENTLY VIEWED', products: items),
            ],
          );
        },
      );

  Widget _priceBlock(ShopifyProductDetail p) {
    if (!p.isOnSale) {
      return PriceText(p.formattedPrice, currencyCode: p.currencyCode, fontSize: _s(20), color: AppColors.primary, amountFontFamily: AppFonts.body);
    }
    final saved = (p.compareAtPrice! - p.price).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            PriceText(p.formattedPrice, currencyCode: p.currencyCode, fontSize: _s(20), color: AppColors.primary, amountFontFamily: AppFonts.body),
            PriceText(p.formattedCompareAtPrice, currencyCode: p.currencyCode, fontSize: _s(14), color: AppColors.secondaryText, amountFontFamily: AppFonts.body, decoration: TextDecoration.lineThrough),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha: 0.1)),
          child: SavedAmountText(saved.toString(), currencyCode: p.currencyCode, fontSize: _s(11), color: const Color(0xFF2E7D32), fontFamily: AppFonts.body),
        ),
      ],
    );
  }

    Widget _optionSelector(ProductDetailOption opt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontFamily: AppFonts.accent,
                    fontSize: _s(11),
                    color: AppColors.primary,
                  ),
                  children: [
                    TextSpan(text: opt.name.toUpperCase()),
                    TextSpan(
                      text: ' ${_selectedOptions[opt.name] ?? ''}',
                      style: TextStyle(
                        fontFamily: AppFonts.body,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (opt.name.toLowerCase().contains('size')) _sizeChartLink(),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: opt.isColorOption ? 12 : 8,
          runSpacing: 12,
          children: opt.values.map((val) {
            final isSelected = _selectedOptions[opt.name] == val;
            return opt.isColorOption
                ? _colorSwatchChip(opt, val, isSelected)
                : _textOptionChip(opt, val, isSelected);
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Ruler icon + underlined "Size Chart", shown beside the size label
  /// only when Kiwi has a chart for this product.
  Widget _sizeChartLink() => ValueListenableBuilder<bool>(
        valueListenable: _sizeChartAvailable,
        builder: (context, available, _) => !available
            ? const SizedBox.shrink()
            : GestureDetector(
                onTap: _openSizeChart,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.straighten_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Size Chart',
                      style: TextStyle(
                        fontFamily: AppFonts.body,
                        fontSize: _s(12),
                        color: AppColors.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
      );

  Widget _textOptionChip(ProductDetailOption opt, String val, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() => _selectedOptions[opt.name] = val);
        _updateVariant();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.card,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 0.8,
          ),
        ),
        child: Text(
          val,
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: _s(12),
            color: isSelected ? AppColors.onPrimary : AppColors.primary,
          ),
        ),
      ),
    );
  }

  Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    final value = int.tryParse(h, radix: 16);
    return value != null ? Color(value) : null;
  }

  Widget _colorSwatchChip(ProductDetailOption opt, String val, bool isSelected) {
    final swatch = opt.swatchFor(val);
    // Prefer a real photo: Shopify's configured swatch image first, then
    // this product's own photo (each Variant King color is its own
    // product, so this genuinely is a picture of "val"). Only fall back to
    // a guessed color code, then a letter, if no photo exists at all.
    final swatchImageUrl = swatch?.swatchImageUrl;
    final ownPhotoUrl = (_product?.imageUrls.isNotEmpty ?? false)
        ? _product!.imageUrls.first
        : null;
    final imageUrl = swatchImageUrl ?? ownPhotoUrl;
    final color = imageUrl == null
        ? (_hexToColor(swatch?.swatchColorHex) ?? _colorFromName(val))
        : null;

    return GestureDetector(
      onTap: () {
        setState(() => _selectedOptions[opt.name] = val);
        _updateVariant();
      },
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color ?? AppColors.fieldFill,
              image: imageUrl != null
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(imageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: (color == null && imageUrl == null)
                ? Center(
                    child: Text(
                      val.isNotEmpty ? val[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontFamily: AppFonts.body,
                        fontSize: 10,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 4),
          Text(
            val,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: _s(10),
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _availabilityChip() {
    final inStock = _selectedVariant?.availableForSale ?? false;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                inStock ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          inStock ? 'In Stock' : 'Out of Stock',
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: _s(12),
            color: inStock
                ? const Color(0xFF2E7D32)
                : const Color(0xFFD32F2F),
          ),
        ),
      ],
    );
  }

  Widget _addToCartButton() {
    final variant = _selectedVariant;
    final inStock = variant?.availableForSale ?? false;
    final height = _s(50).clamp(46.0, 60.0);
    final label = TextStyle(fontFamily: AppFonts.accent, fontSize: _s(13));

    Widget spinner(Color color) => SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        );

    if (!inStock) {
      return SizedBox(
        width: double.infinity,
        height: height,
        child: ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: AppColors.border,
            elevation: 0,
            shape: AppShapes.button,
          ),
          child: Text('SOLD OUT', style: label.copyWith(color: AppColors.onPrimary)),
        ),
      );
    }

    final busy = _isAddingToCart || _isBuyingNow;
    return AnimatedBuilder(
      animation: CartService.instance,
      builder: (context, _) {
        final alreadyInCart =
            variant != null && CartService.instance.isInCart(variant.id);
        return Column(
          children: [
            SizedBox(
              height: height,
              child: Row(
                children: [
                  _quantityStepper(height, enabled: !busy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : alreadyInCart
                          ? _goToCart
                          : _handleAddToCart,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary, width: 1.2),
                        shape: AppShapes.button,
                        minimumSize: Size.fromHeight(height),
                      ),
                      child: _isAddingToCart
                          ? spinner(AppColors.primary)
                          : Text(
                              alreadyInCart ? 'GO TO CART' : 'ADD TO CART',
                              style: label.copyWith(color: AppColors.primary),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: height,
              child: ElevatedButton(
                onPressed: busy ? null : _handleBuyNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.6),
                  elevation: 0,
                  shape: AppShapes.button,
                  minimumSize: Size.fromHeight(height),
                ),
                child: _isBuyingNow
                    ? spinner(AppColors.onPrimary)
                    : Text('BUY NOW', style: label.copyWith(color: AppColors.onPrimary)),
              ),
            ),
          ],
        );
      },
    );
  }

  /// "−  1  +" box beside Add to Cart; the chosen quantity is used by both
  /// Add to Cart and Buy Now.
  Widget _quantityStepper(double height, {required bool enabled}) {
    Widget step(IconData icon, VoidCallback? onTap) => InkWell(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: height * 0.8,
            height: height,
            child: Icon(
              icon,
              size: 18,
              color: onTap == null ? AppColors.secondaryText : AppColors.primary,
            ),
          ),
        );

    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.primary, width: 1.2),
        borderRadius: AppShapes.buttonBorderRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          step(
            Icons.remove_rounded,
            _quantity > 1 ? () => setState(() => _quantity--) : null,
          ),
          SizedBox(
            width: _s(24),
            child: Text(
              '$_quantity',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.accent,
                fontSize: _s(14),
                color: AppColors.primary,
              ),
            ),
          ),
          step(
            Icons.add_rounded,
            _quantity < _maxQuantity ? () => setState(() => _quantity++) : null,
          ),
        ],
      ),
    );
  }

  Widget _loadingState() => Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              Container(
                color: AppColors.card,
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 18),
                      color: AppColors.primary,
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    Expanded(
                      child: Text(
                        _currentTitle.toUpperCase(),
                        style: TextStyle(
                          fontFamily: AppFonts.body,
                          fontSize: _s(12),
                          color: AppColors.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (_currentHeroImageUrl != null)
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: CachedNetworkImage(
                    imageUrl: _currentHeroImageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, _) =>
                        Container(color: AppColors.fieldFill),
                    errorWidget: (_, _, _) =>
                        Container(color: AppColors.fieldFill),
                  ),
                )
              else
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Container(color: AppColors.fieldFill),
                ),
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _errorState() => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.card,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            color: AppColors.primary,
            onPressed: () => Navigator.maybePop(context),
          ),
          leadingWidth: 44,
          titleSpacing: 0,
          centerTitle: false,
          title: Text(
            _currentTitle.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.heading,
              fontSize: (MediaQuery.of(context).size.width * 0.09)
                  .clamp(20.0, 40.0),
              fontStyle: FontStyle.italic,
              height: 1,
              color: AppColors.primary,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off_rounded,
                    size: 52, color: AppColors.hint),
                const SizedBox(height: 14),
                Text(
                  _error ?? 'Something went wrong.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: _s(13),
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _fetchProduct,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text(
                    'RETRY',
                    style: TextStyle(fontFamily: AppFonts.accent),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class FullScreenImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  final Map<int, TransformationController> _controllers = {};
  TapDownDetails? _doubleTapDetails;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TransformationController _controllerFor(int index) =>
      _controllers.putIfAbsent(index, () => TransformationController());

  void _handleDoubleTap(int index) {
    final controller = _controllerFor(index);
    if (controller.value != Matrix4.identity()) {
      controller.value = Matrix4.identity();
      setState(() => _isZoomed = false);
    } else if (_doubleTapDetails != null) {
      final position = _doubleTapDetails!.localPosition;
      controller.value = Matrix4.identity()
        ..translateByDouble(-position.dx * 1.5, -position.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 2.5, 1);
      setState(() => _isZoomed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            physics: _isZoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: widget.imageUrls.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) => GestureDetector(
              onDoubleTapDown: (details) => _doubleTapDetails = details,
              onDoubleTap: () => _handleDoubleTap(i),
              child: InteractiveViewer(
                transformationController: _controllerFor(i),
                minScale: 1.0,
                maxScale: 4.0,
                onInteractionEnd: (_) {
                  final zoomed =
                      _controllerFor(i).value != Matrix4.identity();
                  if (zoomed != _isZoomed) {
                    setState(() => _isZoomed = zoomed);
                  }
                },
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.imageUrls[i],
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white54),
                    ),
                    errorWidget: (_, _, _) => const Icon(
                        Icons.image_not_supported_outlined,
                        size: 52,
                        color: Colors.white38),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: GestureDetector(
              onTap: () => Navigator.pop(context, _currentIndex),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 20, color: Colors.white),
              ),
            ),
          ),
          if (widget.imageUrls.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.imageUrls.length}',
                    style:
                        const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}