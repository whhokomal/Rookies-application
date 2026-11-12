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
import 'package:rookies_jeans/services/reviews_service.dart';
import 'package:rookies_jeans/services/cart_service.dart';
import 'package:rookies_jeans/screens/cart/checkout_flow.dart';
import 'package:rookies_jeans/utils/color_names.dart';
import 'package:rookies_jeans/widgets/delivery_date_checker.dart';
import 'package:rookies_jeans/widgets/price_text.dart';
import 'package:rookies_jeans/widgets/product_reviews_section.dart';
import 'package:rookies_jeans/widgets/trust_strip.dart';
import 'package:rookies_jeans/widgets/product_row_section.dart';
import 'package:rookies_jeans/widgets/sold_out_strike.dart';

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

  /// True while two fingers are pinching a gallery photo; stops the page
  /// and the photo carousel scrolling under the pinch.
  bool _isPinchingImage = false;
  final ScrollController _scrollController = ScrollController();

  Map<String, String> _selectedOptions = {};
  ProductDetailVariant? _selectedVariant;

  /// Set when Add to Cart / Buy Now is tapped before a size is picked;
  /// shows "Please select a size" under the sizes until one is.
  bool _showSizeError = false;

  /// The Size option, when the shopper has to pick one (more than one
  /// size). Sizes are never preselected, like the website.
  ProductDetailOption? get _sizeOption {
    for (final opt in _product?.options ?? const <ProductDetailOption>[]) {
      if (opt.name.toLowerCase().contains('size') && opt.values.length > 1) {
        return opt;
      }
    }
    return null;
  }

  bool get _needsSize {
    final size = _sizeOption;
    return size != null && !_selectedOptions.containsKey(size.name);
  }

  /// Before a size is picked: whether any size can be bought.
  bool get _anySizeInStock =>
      _product?.variants.any((v) => v.availableForSale) ?? false;

  /// Whether picking [val] for [opt], with the other options as currently
  /// selected, lands on a variant that can be bought.
  bool _isOptionValueInStock(ProductDetailOption opt, String val) {
    return _product?.variants.any((v) {
          if (!v.availableForSale) return false;
          for (final s in v.selectedOptions) {
            final want = s.name == opt.name ? val : _selectedOptions[s.name];
            if (want != null && s.value != want) return false;
          }
          return true;
        }) ??
        false;
  }

  List<ShopifyProduct> _goesWellWith = [];
  List<ShopifyProduct> _youMayAlsoLike = [];
  List<ShopifyProduct> _colorSiblings = [];

  /// Which info tab is open: 0 Shipping & Returns, 1 Product Description.
  int _infoTab = 0;

  /// Judge.me reviews for the shown product; null until loaded.
  ProductReviews? _reviews;

  /// Stock left per variant id; empty until loaded, or when the app's
  /// Storefront access can't read inventory.
  Map<String, int> _variantQuantities = const {};

  /// At or below this many left, "Hurry, only N items left in stock!"
  /// replaces "In Stock" (the website's low-inventory threshold).
  static const int _kLowStockThreshold = 8;
  final GlobalKey _reviewsKey = GlobalKey();

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
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
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
      // Above the floating bottom nav bar, which otherwise covers the
      // bottom of the chart.
      useRootNavigator: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          SizeChartView(controller: controller, loading: _sizeChartLoading),
    );
  }

  static const List<String> _descLabels = [
    'STYLE NO & COLOR',
    'STYLE NO',
    'COLLAR/NECK',
    'COLLAR / NECK',
    'STRETCH METER',
    'WASH CARE',
    'FABRIC',
    'SLEEVES',
    'DESIGN',
    'OCCASION',
    'PATTERN',
    'POCKETS',
    'CLOSURE',
    'LENGTH',
    'COLOR',
    'CARE',
    'FIT',
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

      // Every option starts on its first value except a Size with more
      // than one choice, which the shopper must pick.
      final defaults = <String, String>{};
      for (final opt in product.options) {
        final isSizeChoice =
            opt.name.toLowerCase().contains('size') && opt.values.length > 1;
        if (opt.values.isNotEmpty && !isSizeChoice) {
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
      ShopifyStorefrontService.instance
          .getVariantQuantities(product.id)
          .then((quantities) {
        if (mounted && _product?.id == product.id) {
          setState(() => _variantQuantities = quantities);
        }
      });

      debugPrint('=== PRODUCT DEBUG (${product.handle}) ===');
      debugPrint('Options: ${product.options.length}');
      for (final o in product.options) {
        debugPrint('  "${o.name}": ${o.values}');
      }
      debugPrint('Variants: ${product.variants.length}');
      for (final v in product.variants) {
        final sel = v.selectedOptions
            .map((s) => '${s.name}=${s.value}')
            .join(', ');
        debugPrint('  "${v.title}" | available=${v.availableForSale} | $sel');
      }
      debugPrint('==========================================');

      _updateVariant();
      _fetchRelatedProducts();
      _fetchColorSiblings();
      _fetchReviews();
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

  Future<void> _fetchReviews() async {
    final productId = _product?.id;
    if (productId == null) return;
    final reviews = await ReviewsService.instance.getReviews(productId);
    // Skip if the customer switched color while this was loading.
    if (!mounted || _product?.id != productId) return;
    setState(() => _reviews = reviews);
  }

  void _scrollToReviews() {
    final ctx = _reviewsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _fetchRelatedProducts() async {
    if (!mounted) return;

    final pairings = ProductPairings.goesWellWithCollections(_detectCategory());

    try {
      if (pairings.isNotEmpty) {
        final handle = pairings.first;
        final products = await ShopifyStorefrontService.instance
            .getProductsByCollection(handle, first: 6);
        if (mounted) {
          setState(
            () => _goesWellWith = products
                .where((p) => p.handle != _currentHandle)
                .take(4)
                .toList(),
          );
        }
      }

      final similar = await ShopifyStorefrontService.instance
          .getProductsByCollection(_sameCollectionHandle(), first: 8);
      if (mounted) {
        final filtered =
            similar.where((p) => p.handle != _currentHandle).toList()
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
    if (_needsSize) {
      setState(() => _selectedVariant = null);
      return;
    }
    final match = _product!.variants.firstWhere(
      (v) =>
          v.selectedOptions.every((o) => _selectedOptions[o.name] == o.value),
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
      setState(
        () =>
            _isWishlisted = WishlistService.instance.isWishlisted(_product!.id),
      );
    } catch (e, st) {
      debugPrint('Wishlist toggle error: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Wishlist error: $e',
            style: const TextStyle(fontFamily: AppFonts.body),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  void _goToCart() => openGokwikCart(context);

  Future<void> _handleAddToCart() async {
    if (_needsSize) {
      setState(() => _showSizeError = true);
      return;
    }
    final variant = _selectedVariant;
    if (variant == null || _isAddingToCart) return;
    if (!variant.availableForSale) return;

    setState(() => _isAddingToCart = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final success = await CartService.instance.addLine(
      variantId: variant.id,
      quantity: _quantity,
    );

    if (!mounted) return;
    setState(() => _isAddingToCart = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '${_product?.title ?? 'Item'} added to cart'
              : (CartService.instance.lastError ??
                    'Failed to add item to cart'),
          style: const TextStyle(fontFamily: AppFonts.accent),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Checks out only the selected variant (at the chosen qty), leaving the app cart
  /// untouched — the checkout replaces the website cart with these lines.
  Future<void> _handleBuyNow() async {
    if (_needsSize) {
      setState(() => _showSizeError = true);
      return;
    }
    final product = _product;
    final variant = _selectedVariant;
    if (product == null || variant == null || _isBuyingNow) return;
    if (!variant.availableForSale) return;

    setState(() => _isBuyingNow = true);
    try {
      final placed = await runCheckoutFlow(
        context,
        lines: [
          ShopifyCartLine(
            lineId: '',
            variantId: variant.id,
            productTitle: product.title,
            productHandle: product.handle,
            variantTitle: variant.title,
            imageUrl: product.imageUrls.isNotEmpty
                ? product.imageUrls.first
                : null,
            price: variant.price ?? product.price,
            currencyCode: product.currencyCode,
            quantity: _quantity,
          ),
        ],
      );
      if (!mounted || !placed) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Order placed successfully!',
              style: TextStyle(fontFamily: AppFonts.body),
            ),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
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
      _reviews = null;
      _selectedOptions = {};
      _selectedVariant = null;
      _showSizeError = false;
      _infoTab = 0;
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
      physics: _isPinchingImage ? const NeverScrollableScrollPhysics() : null,
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
                    ProductRowSection(
                      title: 'GOES WELL WITH',
                      products: _goesWellWith,
                    ),
                  ],
                  if (_youMayAlsoLike.isNotEmpty) ...[
                    const Divider(height: 1),
                    ProductRowSection(
                      title: 'YOU MAY ALSO LIKE',
                      products: _youMayAlsoLike,
                    ),
                  ],
                  _recentlyViewedSection(p.id),
                  if (_reviews != null) ...[
                    const Divider(height: 1),
                    ProductReviewsSection(
                      key: _reviewsKey,
                      reviews: _reviews!,
                      productId: p.id,
                      productHandle: p.handle,
                    ),
                  ],
                  // Clearance for the floating bottom nav bar.
                  const SizedBox(height: 110),
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
        child: Stack(
          children: [
            Container(
              color: AppColors.fieldFill,
              alignment: Alignment.center,
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 52,
                color: AppColors.hint,
              ),
            ),
            _backButton(),
            _wishlistButton(),
            _shareButton(),
          ],
        ),
      );
    }
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _currentImageIndex = i),
                  // Locked while two fingers are pinching, so the pinch isn't
                  // taken as a swipe to the next photo.
                  physics: _isPinchingImage
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _openImageViewer(images),
                    child: _PinchZoomImage(
                      onPinchChanged: (pinching) =>
                          setState(() => _isPinchingImage = pinching),
                      child: CachedNetworkImage(
                        imageUrl: images[i],
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(color: AppColors.fieldFill),
                        errorWidget: (_, _, _) => Container(
                          color: AppColors.fieldFill,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 52,
                            color: AppColors.hint,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _backButton(),
              _wishlistButton(),
              _shareButton(),
            ],
          ),
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
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 22,
          color: AppColors.primary,
        ),
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
                  strokeWidth: 2,
                  color: Colors.black,
                ),
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
                  color: _isWishlisted ? Colors.red : Colors.black,
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
        child: Icon(Icons.share_outlined, size: 20, color: Colors.black),
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
                    style: TextStyle(
                      fontFamily: AppFonts.accent,
                      color: AppColors.primary,
                    ),
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
                fallbackColor: colorFromHandle(_currentHandle),
                isCurrent: true,
                soldOut: !_anySizeInStock,
                onTap: null,
              ),
              for (final sibling in _colorSiblings)
                _colorSiblingChip(
                  title: sibling.title,
                  imageUrl: sibling.primaryImageUrl,
                  fallbackColor: sibling.colorHexCodes.isNotEmpty
                      ? hexToColor(sibling.colorHexCodes.first)
                      : colorFromHandle(sibling.handle),
                  isCurrent: false,
                  soldOut: !sibling.variants.any((v) => v.availableForSale),
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
    bool soldOut = false,
    VoidCallback? onTap,
  }) {
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    // Sold-out colors are crossed out and can't be opened.
    return GestureDetector(
      onTap: soldOut ? null : onTap,
      child: SizedBox(
        width: 48,
        child: Column(
          children: [
            SoldOutStrike(
              soldOut: soldOut,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasImage
                      ? null
                      : (fallbackColor ?? AppColors.fieldFill),
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
                color: soldOut ? AppColors.secondaryText : AppColors.primary,
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
          if (_reviews != null && _reviews!.reviewCount > 0) ...[
            const SizedBox(height: 4),
            RatingSummaryLine(reviews: _reviews!, onTap: _scrollToReviews),
          ],
          const SizedBox(height: 8),
          _priceBlock(p),
          const SizedBox(height: 16),
          _colorSiblingsSection(),

          ...p.options
              .where((opt) => !opt.isColorOption)
              .map((opt) => _optionSelector(opt)),
          _variantMetafieldsSection(),
          const SizedBox(height: 20),
          const DeliveryDateChecker(),
          const SizedBox(height: 20),
          _availabilityChip(),
          const SizedBox(height: 20),
          _addToCartButton(),
          const SizedBox(height: 16),
          const TrustStrip(),
          const SizedBox(height: 24),
          _infoTabs(p),
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

  Widget _descriptionContent(String raw) {
    final cleaned = _preprocessDescription(raw);
    final lines = cleaned
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    final children = <Widget>[];
    for (final line in lines) {
      final trimmed = line.trim().replaceFirst(RegExp(r'^[•\-]\s*'), '');
      final hasLabel = RegExp(r'^[A-Za-z][A-Za-z\s&/]*:').hasMatch(trimmed);

      if (hasLabel) {
        final colonIdx = trimmed.indexOf(':');
        final label = trimmed.substring(0, colonIdx + 1).trim();
        final value = trimmed.substring(colonIdx + 1).trim();
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Icon(
                    Icons.circle,
                    size: 5,
                    color: AppColors.secondaryText,
                  ),
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
          ),
        );
      } else {
        children.add(
          Padding(
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
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// "Shipping & Returns" and "Product Description" as two tabs, like the
  /// website, with the chosen one's text always shown below.
  Widget _infoTabs(ShopifyProductDetail p) {
    final tabs = <(String, Widget)>[
      ('SHIPPING & RETURNS', _shippingContent(p)),
      if (p.description.isNotEmpty || (p.careInstructions?.isNotEmpty ?? false))
        ('PRODUCT DESCRIPTION', _productDescriptionContent(p)),
    ];
    final selected = _infoTab.clamp(0, tabs.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            for (var i = 0; i < tabs.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _infoTab = i),
                child: Container(
                  padding: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == selected
                            ? AppColors.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    tabs[i].$1,
                    style: TextStyle(
                      fontFamily: AppFonts.accent,
                      fontSize: _s(13),
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w700,
                      color: i == selected
                          ? AppColors.primary
                          : AppColors.secondaryText,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        tabs[selected].$2,
      ],
    );
  }

  /// The product's own shipping text one point per line, or the store's
  /// standard policy.
  Widget _shippingContent(ShopifyProductDetail p) {
    final custom = p.shippingInfo?.trim() ?? '';
    final points = custom.isNotEmpty
        ? custom
              .split(RegExp(r'\n|(?<=\.)\s+'))
              .map((l) => l.trim().replaceFirst(RegExp(r'^[•\-]\s*'), ''))
              .where((l) => l.isNotEmpty)
              .toList()
        : const [
            'Free shipping on prepaid orders.',
            'Returns accepted within 7 days of delivery for unworn items in '
                'original condition.',
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final point in points) _bulletPoint(point)],
    );
  }

  /// The description, plus care instructions when the product has them.
  Widget _productDescriptionContent(ShopifyProductDetail p) {
    final care = p.careInstructions?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p.description.isNotEmpty) _descriptionContent(p.description),
        if (care.isNotEmpty) _bulletPoint('Care: $care'),
      ],
    );
  }

  Widget _bulletPoint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7, right: 8),
          child: Icon(Icons.circle, size: 5, color: AppColors.primary),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: _s(13),
              color: AppColors.primary,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );

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
      return PriceText(
        p.formattedPrice,
        currencyCode: p.currencyCode,
        fontSize: _s(20),
        color: AppColors.primary,
        amountFontFamily: AppFonts.body,
      );
    }
    final saved = (p.compareAtPrice! - p.price).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            PriceText(
              p.formattedPrice,
              currencyCode: p.currencyCode,
              fontSize: _s(20),
              color: AppColors.primary,
              amountFontFamily: AppFonts.body,
            ),
            PriceText(
              p.formattedCompareAtPrice,
              currencyCode: p.currencyCode,
              fontSize: _s(14),
              color: AppColors.secondaryText,
              amountFontFamily: AppFonts.body,
              decoration: TextDecoration.lineThrough,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
          ),
          child: SavedAmountText(
            saved.toString(),
            currencyCode: p.currencyCode,
            fontSize: _s(11),
            color: const Color(0xFF2E7D32),
            fontFamily: AppFonts.body,
          ),
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
        if (_showSizeError && _needsSize && opt.name == _sizeOption?.name)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Please select a size',
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: _s(12),
                fontWeight: FontWeight.w600,
                color: const Color(0xFFD32F2F),
              ),
            ),
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
                Icon(
                  Icons.straighten_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
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
    // Sold-out values are crossed out with a diagonal line and can't be
    // tapped, like the website.
    final inStock = _isOptionValueInStock(opt, val);
    return GestureDetector(
      onTap: !inStock
          ? null
          : () {
              setState(() {
                _selectedOptions[opt.name] = val;
                _showSizeError = false;
              });
              _updateVariant();
            },
      child: SoldOutStrike(
        soldOut: !inStock,
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
              color: isSelected
                  ? AppColors.onPrimary
                  : inStock
                  ? AppColors.primary
                  : AppColors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _colorSwatchChip(
    ProductDetailOption opt,
    String val,
    bool isSelected,
  ) {
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
        ? (hexToColor(swatch?.swatchColorHex) ?? colorFromName(val))
        : null;

    final inStock = _isOptionValueInStock(opt, val);
    return GestureDetector(
      onTap: !inStock
          ? null
          : () {
              setState(() => _selectedOptions[opt.name] = val);
              _updateVariant();
            },
      child: Column(
        children: [
          SoldOutStrike(
            soldOut: !inStock,
            child: AnimatedContainer(
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
          ),
          const SizedBox(height: 4),
          Text(
            val,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: _s(10),
              color: inStock ? AppColors.primary : AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _availabilityChip() {
    final inStock = _needsSize
        ? _anySizeInStock
        : _selectedVariant?.availableForSale ?? false;
    final left = _selectedVariant == null
        ? null
        : _variantQuantities[_selectedVariant!.id];
    if (inStock && left != null && left > 0 && left <= _kLowStockThreshold) {
      return _lowStockNotice(left);
    }
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: inStock ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          inStock ? 'In Stock' : 'Out of Stock',
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: _s(12),
            color: inStock ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
          ),
        ),
      ],
    );
  }

  /// The website's low-stock box: a green dot on a pale green band.
  Widget _lowStockNotice(int left) {
    const green = Color(0xFF10A71F);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: const Color(0x2110A71F),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: green,
              boxShadow: [
                BoxShadow(
                  color: green.withValues(alpha: 0.3),
                  spreadRadius: 3,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              left == 1
                  ? 'Hurry, only 1 item left in stock!'
                  : 'Hurry, only $left items left in stock!',
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: _s(13),
                fontWeight: FontWeight.w500,
                color: green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addToCartButton() {
    final variant = _selectedVariant;
    // With no size picked yet the buttons stay live (tapping asks for a
    // size) unless every size is sold out.
    final inStock = _needsSize
        ? _anySizeInStock
        : variant?.availableForSale ?? false;
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
          child: Text(
            'SOLD OUT',
            style: label.copyWith(color: AppColors.onPrimary),
          ),
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
                  disabledBackgroundColor: AppColors.primary.withValues(
                    alpha: 0.6,
                  ),
                  elevation: 0,
                  shape: AppShapes.button,
                  minimumSize: Size.fromHeight(height),
                ),
                child: _isBuyingNow
                    ? spinner(AppColors.onPrimary)
                    : Text(
                        'BUY NOW',
                        style: label.copyWith(color: AppColors.onPrimary),
                      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
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
                placeholder: (_, _) => Container(color: AppColors.fieldFill),
                errorWidget: (_, _, _) => Container(color: AppColors.fieldFill),
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
          fontSize: (MediaQuery.of(context).size.width * 0.09).clamp(
            20.0,
            40.0,
          ),
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
            Icon(Icons.wifi_off_rounded, size: 52, color: AppColors.hint),
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

  /// Fingers on the screen. Swiping between photos is locked from the
  /// moment a second finger lands, so a pinch always zooms instead of
  /// being taken as a swipe.
  int _pointers = 0;

  void _onPointerCountChanged(int delta) {
    final wasPinching = _pointers >= 2;
    _pointers = (_pointers + delta).clamp(0, 10);
    if ((_pointers >= 2) != wasPinching) setState(() {});
  }

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
          Listener(
            onPointerDown: (_) => _onPointerCountChanged(1),
            onPointerUp: (_) => _onPointerCountChanged(-1),
            onPointerCancel: (_) => _onPointerCountChanged(-1),
            child: PageView.builder(
              controller: _pageController,
              physics: _isZoomed || _pointers >= 2
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
                          strokeWidth: 2,
                          color: Colors.white54,
                        ),
                      ),
                      errorWidget: (_, _, _) => const Icon(
                        Icons.image_not_supported_outlined,
                        size: 52,
                        color: Colors.white38,
                      ),
                    ),
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
                child: const Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Colors.white,
                ),
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
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.imageUrls.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A gallery photo that zooms with a two-finger pinch and springs back
/// when the fingers lift, like Instagram. One-finger drags are left to the
/// carousel and the page. [onPinchChanged] reports when a pinch starts and
/// ends so the parent can stop scrolling meanwhile.
class _PinchZoomImage extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool> onPinchChanged;

  const _PinchZoomImage({required this.child, required this.onPinchChanged});

  @override
  State<_PinchZoomImage> createState() => _PinchZoomImageState();
}

class _PinchZoomImageState extends State<_PinchZoomImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  late final AnimationController _reset = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Animation<Matrix4>? _resetAnimation;
  int _pointers = 0;
  bool _pinching = false;

  @override
  void initState() {
    super.initState();
    _reset.addListener(() {
      final animation = _resetAnimation;
      if (animation != null) _transform.value = animation.value;
    });
  }

  @override
  void dispose() {
    _reset.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _setPinching(bool pinching) {
    if (pinching == _pinching) return;
    _pinching = pinching;
    widget.onPinchChanged(pinching);
  }

  void _springBack() {
    _resetAnimation = Matrix4Tween(
      begin: _transform.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _reset, curve: Curves.easeOut));
    _reset.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        _pointers++;
        if (_pointers >= 2) {
          _reset.stop();
          _setPinching(true);
        }
      },
      onPointerUp: (_) => _onPointerLifted(),
      onPointerCancel: (_) => _onPointerLifted(),
      child: InteractiveViewer(
        transformationController: _transform,
        panEnabled: false,
        minScale: 1.0,
        maxScale: 4.0,
        onInteractionEnd: (_) => _springBack(),
        child: SizedBox.expand(child: widget.child),
      ),
    );
  }

  void _onPointerLifted() {
    _pointers = (_pointers - 1).clamp(0, 10);
    if (_pointers == 0) {
      _setPinching(false);
      _springBack();
    }
  }
}
