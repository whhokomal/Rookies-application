import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rookies_jeans/utils/format.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/models/banner_model.dart';
import 'package:rookies_jeans/models/collection_model.dart';
import 'package:rookies_jeans/models/home_content_models.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/screens/products/product_detail_page.dart';
import 'package:rookies_jeans/screens/products/product_peek_dialog.dart';
import 'package:rookies_jeans/screens/products/products.dart';
import 'package:rookies_jeans/screens/search/search_tab_page.dart';
import 'package:rookies_jeans/services/cart_service.dart';
import 'package:rookies_jeans/services/shopify_storefront_service.dart';
import 'package:rookies_jeans/widgets/product_swatch_row.dart';
import 'package:rookies_jeans/widgets/wishlist_heart_button.dart';
import 'package:rookies_jeans/widgets/banner_page_dots.dart';
import 'package:rookies_jeans/widgets/sticker_chip.dart';

typedef R = Responsive;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _kBottomNavHeight = 60.0;
  static const double _kBottomNavClearance = 84.0;

  bool _isLoading = true;

  List<HomeBanner> _heroBanners = [];
  List<ExploreCategoryContent> _exploreCategories = [];
  List<PromoBlockContent> _promoBlocksContent = [];
  List<ShopTheLookEntry> _shopTheLookEntries = [];
  List<OccasionTileContent> _occasionTilesContent = [];
  List<FeatureBannerContent> _featureBanners = [];

  final ScrollController _scrollController = ScrollController();

  // "EXPLORE COLLECTIONS" section: a tab (its own collection) plus Shopify's
  // native "Category" and "Fit" facet filters on that collection, combinable
  // simultaneously, backed by an infinite-scrolling product grid.
  // Tabs come from the `explore_tab` metaobjects; these are the fallback
  // until any exist (or if the fetch fails).
  static const List<_ExploreTabDef> _defaultExploreTabDefs = [
    _ExploreTabDef('HOT DEALS', ShopifyConstants.hotDealsHandle),
    _ExploreTabDef('SALE', 'mid-season-deals'),
    _ExploreTabDef('TRENDING NOW', ShopifyConstants.trendingNowHandle),
  ];
  List<_ExploreTabDef> _exploreTabDefs = _defaultExploreTabDefs;

  int _exploreTabIndex = 0;
  ShopifyFilter? _exploreCategoryFilter;
  ShopifyFilter? _exploreFitFilter;
  // Fits available in the current category, captured while no fit is
  // selected. Once a fit is picked Shopify's counts drop the other fits to
  // zero, so the row keeps showing this list instead.
  List<ShopifyFilterValue> _exploreFitOptions = const [];
  String? _selectedExploreCategoryInput;
  String? _selectedExploreFitInput;
  int _exploreRequestId = 0;

  List<ShopifyProduct> _exploreProducts = [];
  String? _exploreEndCursor;
  bool _exploreHasMore = true;
  bool _exploreLoadingFirst = true;
  bool _exploreLoadingMore = false;

  _ShopifyProductItem _mapShopifyProduct(ShopifyProduct product) {
    String? compareAtPrice;
    String? discountLabel;
    if (product.isOnSale) {
      final double comparePrice = product.compareAtPrice!;
      compareAtPrice = '₹ ${formatInr(comparePrice)}';
      final int percentOff =
          (((comparePrice - product.price) / comparePrice) * 100).round();
      discountLabel = '-$percentOff%';
    }

    return _ShopifyProductItem(
      product: product,
      id: product.id,
      handle: product.handle,
      title: product.title,
      price: '₹ ${formatInr(product.price)}',
      compareAtPrice: compareAtPrice,
      discountLabel: discountLabel,
      imageUrl: product.primaryImageUrl,
    );
  }

  final List<_OccasionTile> _defaultOccasionTiles = const [
    _OccasionTile(imageAsset: 'assets/jeans_jann.jpeg', handle: 'jeans-jann'),
    _OccasionTile(imageAsset: 'assets/jeans_jesse.jpeg', handle: 'jeans-jesse'),
    _OccasionTile(
      imageAsset: 'assets/jeans_lennon.jpeg',
      handle: 'jeans-lennon',
    ),
    _OccasionTile(imageAsset: 'assets/jeans_mojo.jpeg', handle: 'jeans-mojo'),
    _OccasionTile(imageAsset: 'assets/jeans_nikki.jpeg', handle: 'jeans-nikki'),
    _OccasionTile(
      imageAsset: 'assets/jeans_springsteen.jpeg',
      handle: 'jeans-springsteen',
    ),
  ];

  final List<_PromoBlockData> _defaultPromoBlocks = const [
    _PromoBlockData(
      assetPath: 'assets/denim.png',
      label: 'Denim',
      buttonLabel: 'Explore',
      collectionHandle: 'JEANS',
    ),
    _PromoBlockData(
      assetPath: 'assets/cargo.png',
      label: 'Cargos',
      buttonLabel: 'Explore',
      collectionHandle: 'CARGOS',
    ),
    // _PromoBlockData(
    //   assetPath: 'assets/shoes.jpg',
    //   label: 'Shoes',
    //   buttonLabel: 'Shop Shoes',
    //   collectionHandle: 'shoes',P
    // ),
    // _PromoBlockData(
    //   assetPath: 'assets/accessories.jpg',
    //   label: 'Accessories',
    //   buttonLabel: 'Shop Accessories',
    //   collectionHandle: 'accessories',
    // ),
  ];

  /// Every hero banner with an uploaded image, in order; the hero pages
  /// through them and a tap opens that banner's redirect link.
  List<HomeBanner> get _heroBannersWithImage =>
      _heroBanners.where((b) => b.imageUrl != null).toList();

  List<_PromoBlockData> get _promoBlocksToDisplay {
    if (_promoBlocksContent.isEmpty) return _defaultPromoBlocks;
    // Entries sharing a label merge into one block whose images rotate; the
    // first entry supplies the button and collection.
    final Map<String, PromoBlockContent> firstByLabel = {};
    final Map<String, List<String>> imagesByLabel = {};
    for (final p in _promoBlocksContent) {
      final key = p.label.trim().toLowerCase();
      firstByLabel.putIfAbsent(key, () => p);
      final images = imagesByLabel.putIfAbsent(key, () => []);
      if (p.imageUrl != null) images.add(p.imageUrl!);
    }
    return firstByLabel.entries.map((e) {
      final p = e.value;
      return _PromoBlockData(
        assetPath: null,
        imageUrls: imagesByLabel[e.key]!,
        label: p.label,
        buttonLabel: p.buttonLabel ?? 'Shop ${p.label}',
        collectionHandle: p.collectionHandle,
      );
    }).toList();
  }

  List<_ShopTheLookOutfit> get _shopTheLookOutfitsToDisplay {
    // Nothing set up in Shopify (or it failed to load): hide the section.
    if (_shopTheLookEntries.isEmpty) return const [];
    return _shopTheLookEntries
        .where((e) => e.imageUrl != null && e.products.isNotEmpty)
        .map(
          (e) => _ShopTheLookOutfit(
            imageAsset: 'assets/shop_the_look_outfit_1.jpg',
            imageUrl: e.imageUrl,
            products: e.products
                .map(
                  (p) => _ShopTheLookProduct(
                    title: p.title,
                    price: '₹ ${formatInr(p.price)}',
                    imageAsset: 'assets/shop_the_look_item_1.jpg',
                    imageUrl: p.primaryImageUrl,
                    product: p,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  List<_OccasionTile> get _occasionTilesToDisplay {
    if (_occasionTilesContent.isEmpty) return _defaultOccasionTiles;
    return _occasionTilesContent
        .map(
          (t) => _OccasionTile(
            imageAsset: 'assets/jeans_jann.jpeg',
            imageUrl: t.imageUrl,
            handle: t.collectionHandle,
            label: t.label,
          ),
        )
        .toList();
  }

  List<_PromoBlockData> get _promoBlocksFirstHalf {
    return _promoBlocksToDisplay;
  }

  List<_PromoBlockData> get _promoBlocksSecondHalf {
    return const [];
  }

  List<Widget> _promoBlockSlivers(List<_PromoBlockData> blocks) {
    return blocks
        .map(
          (block) => SliverToBoxAdapter(
            child: _PromoBlockCard(
              assetPath: block.assetPath,
              imageUrls: block.imageUrls,
              label: block.label,
              buttonLabel: block.buttonLabel,
              height: _promoBlockHeight(context),
              // The handle field often holds a full collection URL.
              onTap: () => _openLink(block.collectionHandle, title: block.label),
            ),
          ),
        )
        .toList();
  }

  /// Feature banners, stacked in the order they were added. Each one is as
  /// tall as its image's shape needs at full width, so artwork with text
  /// (e.g. a square "Last sizes left" poster) is never cropped; banners
  /// without a known size fall back to the Denim / Cargos promo height.
  List<Widget> _featureBannerSlivers() {
    if (_featureBanners.isEmpty) return const [];
    final screenWidth = MediaQuery.of(context).size.width;
    // Breathing room between the banners and the sections around them.
    final gap = SliverToBoxAdapter(
      child: SizedBox(height: R.of(context).dp(20)),
    );
    return [
      gap,
      ..._featureBanners.map(
        (b) => SliverToBoxAdapter(
          child: _PromoBlockCard(
            imageUrls: [if (b.imageUrl != null) b.imageUrl!],
            label: b.label,
            buttonLabel: b.buttonLabel ?? '',
            height: b.aspectRatio != null
                ? screenWidth / b.aspectRatio!
                : _promoBlockHeight(context),
            onTap: () => _openLink(b.link, title: b.label),
          ),
        ),
      ),
      gap,
    ];
  }

  /// Opens a metaobject link: a collection handle, a `/collections/...` or
  /// `/products/...` path (full store URLs too), or any other web URL.
  void _openLink(String link, {String? title}) {
    final String url = link.trim();
    if (url.isEmpty) return;
    final String? name = (title == null || title.trim().isEmpty) ? null : title;

    final product = RegExp(r'/products/([^/?#]+)').firstMatch(url);
    if (product != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ProductDetailPage(handle: product.group(1)!, title: name ?? ''),
        ),
      );
      return;
    }
    final collection = RegExp(r'/collections/([^/?#]+)').firstMatch(url);
    if (collection != null) {
      _openCollectionByHandle(collection.group(1)!, title: name);
    } else if (url.startsWith('http://') || url.startsWith('https://')) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      // A bare collection handle; Shopify handles are lower case.
      _openCollectionByHandle(url.toLowerCase(), title: name);
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchAll();
    _fetchExploreProducts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchAll({bool forceRefresh = false}) async {
    if (mounted) setState(() => _isLoading = true);
    if (forceRefresh) {
      ShopifyStorefrontService.instance.clearCache();
    }
    final service = ShopifyStorefrontService.instance;
    final results = await Future.wait([
      service.getHomeBanners(),
      service.getExploreCategoriesContent(),
      service.getPromoBlocks(),
      service.getShopTheLookEntries(),
      service.getOccasionTilesContent(),
      service.getFeatureBanners(),
      service.getExploreTabs(),
    ]);
    if (!mounted) return;

    final exploreTabs = results[6] as List<ExploreTabContent>;
    final List<_ExploreTabDef> newTabDefs = exploreTabs.isEmpty
        ? _defaultExploreTabDefs
        : exploreTabs
              .map(
                (t) =>
                    _ExploreTabDef(t.label.toUpperCase(), t.collectionHandle),
              )
              .toList();
    // Stay on the same collection if it's still a tab; otherwise jump to the
    // first tab and reload the grid.
    final String activeHandle = _exploreTabDefs[_exploreTabIndex].handle;
    final int keptIndex = newTabDefs.indexWhere(
      (t) => t.handle == activeHandle,
    );

    setState(() {
      _exploreTabDefs = newTabDefs;
      if (keptIndex < 0) {
        _exploreTabIndex = 0;
        _selectedExploreCategoryInput = null;
        _selectedExploreFitInput = null;
        _exploreCategoryFilter = null;
        _exploreFitFilter = null;
        _exploreFitOptions = const [];
      } else {
        _exploreTabIndex = keptIndex;
      }
      _heroBanners = results[0] as List<HomeBanner>;
      _exploreCategories = results[1] as List<ExploreCategoryContent>;
      _promoBlocksContent = results[2] as List<PromoBlockContent>;
      _shopTheLookEntries = results[3] as List<ShopTheLookEntry>;
      _occasionTilesContent = results[4] as List<OccasionTileContent>;
      _featureBanners = results[5] as List<FeatureBannerContent>;
      _isLoading = false;
    });
    if (keptIndex < 0) _fetchExploreProducts();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >=
        position.maxScrollExtent - _exploreLoadMoreThreshold) {
      _loadMoreExploreProducts();
    }
  }

  double get _exploreLoadMoreThreshold {
    final r = R.of(context);
    final double gridWidth = MediaQuery.of(context).size.width - r.dp(16) * 2;
    final double cardWidth = (gridWidth - r.dp(12)) / 2;
    final double rowHeight = cardWidth / 0.62 + r.dp(16);
    // ~10 products at 2 columns per row = 5 rows.
    return rowHeight * 5;
  }

  List<String> get _exploreFilterInputs => [
    ?_selectedExploreCategoryInput,
    ?_selectedExploreFitInput,
  ];

  /// Loads the first page for the current tab and filters. The previous
  /// products (and filter rows) stay on screen until the new ones arrive so
  /// the section keeps its height and the page doesn't jump on every tap.
  /// [replaceFilters] drops filter rows the new response doesn't have
  /// (used when switching tabs).
  Future<void> _fetchExploreProducts({bool replaceFilters = false}) async {
    final int requestId = ++_exploreRequestId;
    setState(() {
      _exploreLoadingFirst = true;
      _exploreLoadingMore = false;
      _exploreEndCursor = null;
      _exploreHasMore = true;
    });

    final String handle = _exploreTabDefs[_exploreTabIndex].handle;
    final bool fitSelected = _selectedExploreFitInput != null;

    try {
      final response = await ShopifyStorefrontService.instance
          .getProductsByCollectionPaginated(
            handle,
            first: 20,
            filters: _exploreFilterInputs,
          );
      if (!mounted || requestId != _exploreRequestId) return;

      setState(() {
        _exploreProducts = response.products;
        _exploreEndCursor = response.endCursor;
        _exploreHasMore = response.hasNextPage;
        _exploreLoadingFirst = false;
        if (replaceFilters) {
          _exploreCategoryFilter = null;
          _exploreFitFilter = null;
          _exploreFitOptions = const [];
        }
        for (final filter in response.filters) {
          final label = filter.label.trim().toLowerCase();
          if (label == 'category') _exploreCategoryFilter = filter;
          if (label == 'fit') _exploreFitFilter = filter;
        }
        // Counts here reflect only the category, so this is the full set of
        // fits for it. With a fit applied, keep the list from before.
        if (!fitSelected) {
          _exploreFitOptions = (_exploreFitFilter?.values ?? const [])
              .where((v) => v.count > 0)
              .toList();
        }
      });
    } catch (e) {
      debugPrint('Failed to fetch explore products for "$handle": $e');
      if (!mounted || requestId != _exploreRequestId) return;
      setState(() {
        _exploreLoadingFirst = false;
        _exploreProducts = [];
      });
    }
  }

  Future<void> _loadMoreExploreProducts() async {
    if (_exploreLoadingMore || !_exploreHasMore || _exploreLoadingFirst) return;

    final int requestId = _exploreRequestId;
    setState(() => _exploreLoadingMore = true);

    final String handle = _exploreTabDefs[_exploreTabIndex].handle;

    try {
      final response = await ShopifyStorefrontService.instance
          .getProductsByCollectionPaginated(
            handle,
            first: 20,
            after: _exploreEndCursor,
            filters: _exploreFilterInputs,
          );
      if (!mounted || requestId != _exploreRequestId) return;

      setState(() {
        _exploreProducts = [..._exploreProducts, ...response.products];
        _exploreEndCursor = response.endCursor;
        _exploreHasMore = response.hasNextPage;
        _exploreLoadingMore = false;
      });
    } catch (e) {
      debugPrint('Failed to load more explore products for "$handle": $e');
      if (!mounted || requestId != _exploreRequestId) return;
      setState(() => _exploreLoadingMore = false);
    }
  }

  void _selectExploreTab(int index) {
    if (_exploreTabIndex == index) return;
    setState(() {
      _exploreTabIndex = index;
      _selectedExploreCategoryInput = null;
      _selectedExploreFitInput = null;
    });
    _fetchExploreProducts(replaceFilters: true);
  }

  void _selectExploreCategory(ShopifyFilterValue? value) {
    if (_selectedExploreCategoryInput == value?.input) return;
    // A new category starts fresh: drop the fit selection so the grid shows
    // every product in that category.
    setState(() {
      _selectedExploreCategoryInput = value?.input;
      _selectedExploreFitInput = null;
    });
    _fetchExploreProducts();
  }

  void _selectExploreFit(ShopifyFilterValue? value) {
    if (_selectedExploreFitInput == value?.input) return;
    setState(() => _selectedExploreFitInput = value?.input);
    _fetchExploreProducts();
  }

  void _openCollectionByHandle(String handle, {String? title, String? label}) {
    final collection = ShopifyCollection(
      id: handle,
      title: title ?? label ?? handle,
      handle: handle,
      label: label ?? (title ?? handle).toUpperCase(),
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductsPage(collection: collection)),
    );
  }

  void _openSearch() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, _) => const SearchTabPage(),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: _isLoading
              ? _shimmer()
              : Container(
                  color: AppColors.bg,
                  child: RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _fetchAll,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: _heroSection()),
                        ..._promoBlockSlivers(_promoBlocksFirstHalf),
                        SliverToBoxAdapter(child: _exploreCategoriesCarousel()),
                        ..._promoBlockSlivers(_promoBlocksSecondHalf),
                        ..._featureBannerSlivers(),
                        if (_shopTheLookOutfitsToDisplay.isNotEmpty)
                          SliverToBoxAdapter(child: _shopTheLookSection()),
                        SliverToBoxAdapter(child: _shopByOccasionsSection()),
                        SliverToBoxAdapter(child: _exploreCollectionsSection()),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: _kBottomNavClearance),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  double _fullScreenBannerHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    return mq.size.height - mq.padding.top - mq.padding.bottom;
  }

  double _promoBlockHeight(BuildContext context) =>
      (MediaQuery.of(context).size.height * 0.46).clamp(220.0, 420.0);

  Widget _topBar() {
    final r = R.of(context);
    return SizedBox(
      height: r.dp(56),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: r.dp(8), vertical: r.dp(6)),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: Icon(Icons.search_rounded, size: r.dp(22)),
                  color: Colors.white,
                  onPressed: _openSearch,
                ),
              ),
            ),
            Image.asset(
              'assets/logo2.png',
              height: r.dp(14),
              fit: BoxFit.contain,
              color: Colors.white,
              colorBlendMode: BlendMode.srcIn,
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.favorite_border_rounded, size: r.dp(22)),
                      color: Colors.white,
                      onPressed: () => context.push('/wishlist'),
                    ),
                    IconButton(
                      icon: Icon(Icons.person_outline_rounded, size: r.dp(22)),
                      color: Colors.white,
                      tooltip: 'Account',
                      onPressed: () => context.go('/profile'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroSection() {
    return SizedBox(
      height: _fullScreenBannerHeight(context),
      width: double.infinity,
      child: Stack(
        children: [
          _heroBannerImage(),
          Positioned(top: 0, left: 0, right: 0, child: _topBar()),
        ],
      ),
    );
  }

  Widget _heroBannerImage() {
    // Top/bottom scrims. The pager paints them beneath its page dots so the
    // dots stay at full brightness.
    final scrims = <Widget>[
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [
                  Colors.black.withValues(alpha: 0.28),
                  Colors.black.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.18, 0.38],
              ),
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [
                  Colors.black.withValues(alpha: 0.60),
                  Colors.black.withValues(alpha: 0.38),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.30, 0.58],
              ),
            ),
          ),
        ),
      ),
    ];
    final banners = _heroBannersWithImage;
    if (banners.isNotEmpty) {
      return _HeroBannerPager(
        imageUrls: [for (final b in banners) b.imageUrl!],
        overlays: scrims,
        onTap: (i) {
          final link = banners[i].link;
          if (link != null) _openLink(link, title: banners[i].title);
        },
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/banner.jpeg',
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const ColoredBox(color: Colors.black),
        ),
        ...scrims,
      ],
    );
  }

  Widget _sliverHeadAsBox(String title) {
    final r = R.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(r.dp(16), r.dp(26), r.dp(16), r.dp(12)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _tiltedHeading(title, r, color: AppColors.primary),
      ),
    );
  }

  Widget _exploreCategoriesCarousel() {
    final r = R.of(context);
    if (_exploreCategories.isEmpty) return _empty();

    // Sized so 2.5 cards are visible: left padding + two gaps + 2.5 cards.
    final double cardWidth =
        (MediaQuery.of(context).size.width - r.dp(16) - r.dp(10) * 2) / 2.5;
    final double cardHeight = cardWidth * 1.3;

    final List<ExploreCategoryContent> topwear = _exploreCategories
        .where((c) => !c.isBottomwear)
        .toList();
    final List<ExploreCategoryContent> bottomwear = _exploreCategories
        .where((c) => c.isBottomwear)
        .toList();

    return Padding(
      padding: EdgeInsets.only(top: r.dp(28), bottom: r.dp(28)),
      child: Column(
        children: [
          if (topwear.isNotEmpty) ...[
            _categoryRowLabel('TOP WEAR', r),
            _categoryRow(topwear, cardWidth, cardHeight, r),
          ],
          if (topwear.isNotEmpty && bottomwear.isNotEmpty)
            SizedBox(height: r.dp(20)),
          if (bottomwear.isNotEmpty) ...[
            _categoryRowLabel('BOTTOM WEAR', r),
            _categoryRow(bottomwear, cardWidth, cardHeight, r),
          ],
        ],
      ),
    );
  }

  Widget _categoryRowLabel(String title, R r) {
    return Padding(
      padding: EdgeInsets.fromLTRB(r.dp(16), 0, r.dp(16), r.dp(16)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _tiltedHeading(title, r, color: AppColors.primary),
      ),
    );
  }

  Widget _categoryRow(
    List<ExploreCategoryContent> items,
    double cardWidth,
    double cardHeight,
    R r,
  ) {
    return SizedBox(
      // Card plus the label underneath it.
      height: cardHeight + r.dp(8) + r.sp(12) * 1.4,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: r.dp(16)),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => SizedBox(width: r.dp(10)),
        itemBuilder: (_, i) {
          final cat = items[i];
          return _categoryCard(
            image: cat.imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: cat.imageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, _) =>
                        Container(color: const Color(0xFF555555)),
                    errorWidget: (_, _, _) =>
                        Container(color: const Color(0xFF555555)),
                  )
                : Container(color: const Color(0xFF555555)),
            label: cat.label,
            width: cardWidth,
            height: cardHeight,
            onTap: () =>
                _openCollectionByHandle(cat.collectionHandle, label: cat.label),
            r: r,
          );
        },
      ),
    );
  }

  Widget _categoryCard({
    required Widget image,
    required String label,
    required double width,
    required double height,
    required VoidCallback onTap,
    required R r,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: width, height: height, child: image),
            SizedBox(height: r.dp(8)),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.accent,
                color: AppColors.primary,
                fontSize: r.sp(12),
                letterSpacing: 1.0,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openProductDetailFromExplore(_ShopifyProductItem product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(
          handle: product.handle,
          title: product.title,
          heroImageUrl: product.imageUrl,
        ),
      ),
    );
  }

  Widget _collectionProductCard(_ShopifyProductItem product, R r) {
    return GestureDetector(
      onTap: () => _openProductDetailFromExplore(product),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: const Color(0xFFECECEC),
                  child: product.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: product.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => const SizedBox(),
                          errorWidget: (_, _, _) => const SizedBox(),
                        )
                      : Image.asset(
                          product.imageAssetFallback,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(),
                        ),
                ),
                if (product.discountLabel != null)
                  Positioned(
                    left: r.dp(8),
                    top: r.dp(8),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: r.dp(10),
                        vertical: r.dp(5),
                      ),
                      color: const Color(0xFFB3261E),
                      child: Text(
                        product.discountLabel!,
                        style: TextStyle(
                          fontFamily: AppFonts.bold,
                          color: Colors.white,
                          fontSize: r.sp(10),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                if (product.product != null)
                  Positioned(
                    top: r.dp(2),
                    right: r.dp(2),
                    child: WishlistHeartButton(product: product.product!),
                  ),
              ],
            ),
          ),
          SizedBox(height: r.dp(8)),
          Text(
            product.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: r.sp(12),
              color: AppColors.primary,
              height: 1.25,
            ),
          ),
          SizedBox(height: r.dp(4)),
          Row(
            children: [
              Text(
                product.price,
                style: TextStyle(
                  fontFamily: AppFonts.number,
                  fontSize: r.sp(13),
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              if (product.compareAtPrice != null) ...[
                SizedBox(width: r.dp(6)),
                Text(
                  product.compareAtPrice!,
                  style: TextStyle(
                    fontFamily: AppFonts.number,
                    fontSize: r.sp(12),
                    color: AppColors.secondaryText,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ],
          ),
          // Reserved even when empty so every card's image is the same
          // height.
          SizedBox(height: r.dp(6)),
          SizedBox(
            height: 14,
            child: product.product != null
                ? ProductSwatchRow(product: product.product!)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _shopTheLookSection() {
    final double sectionHeight =
        _fullScreenBannerHeight(context) - _kBottomNavHeight;
    return SizedBox(
      height: sectionHeight,
      child: Column(
        children: [
          _sliverHeadAsBox('SHOP THE LOOK'),
          Expanded(child: _shopTheLookAsBox()),
        ],
      ),
    );
  }

  Widget _shopTheLookAsBox() {
    final List<_ShopTheLookOutfit> outfits = _shopTheLookOutfitsToDisplay;
    final int maxProducts = outfits
        .map((o) => o.products.length)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double available = constraints.maxHeight;
        final double usable = available.clamp(0.0, available);

        double heroHeight = usable * 0.6;
        heroHeight = heroHeight < 160.0 ? 160.0 : heroHeight;
        heroHeight = heroHeight > usable ? usable : heroHeight;

        final double remainingForRows = (usable - heroHeight).clamp(
          0.0,
          usable,
        );
        double productRowHeight = maxProducts > 0
            ? remainingForRows / maxProducts
            : 0.0;
        if (maxProducts > 0 && productRowHeight < 84.0) {
          productRowHeight = 84.0;
        }

        final double cardHeight = heroHeight + (productRowHeight * maxProducts);

        // Edge to edge: card spans the full screen width.
        return SizedBox(
          height: cardHeight,
          width: double.infinity,
          child: _ShopTheLookAutoSlideCard(
            // Rebuild the slider (and its loop start page) when the looks
            // swap from the built-in defaults to the ones from Shopify.
            key: ValueKey(outfits.length),
            outfits: outfits,
            heroHeight: heroHeight,
            productRowHeight: productRowHeight,
          ),
        );
      },
    );
  }

  Widget _shopByOccasionsSection() {
    final r = R.of(context);
    final double screenW = MediaQuery.of(context).size.width;

    // Portrait cards matching the 3:4 tile photos so the whole image fits
    // without cropping. One large column visible, with a generous peek of the
    // next one so it's clear the row scrolls.
    final double cardWidth = screenW * 0.62;
    final double cardHeight = cardWidth * 4 / 3;
    final double gap = r.dp(8); // horizontal gap between columns
    final double vGap = r.dp(8); // vertical gap between the two rows

    final tiles = _occasionTilesToDisplay;

    // Group tiles into vertical pairs. Each pair is ONE column (top + bottom
    // card) inside the SAME horizontal list, so both rows scroll together.
    final List<List<_OccasionTile>> pairs = [];
    for (int i = 0; i < tiles.length; i += 2) {
      pairs.add(
        tiles.sublist(i, (i + 2) > tiles.length ? tiles.length : i + 2),
      );
    }

    final double sectionHeight = cardHeight * 2 + vGap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(r.dp(16), r.dp(28), r.dp(16), 0),
          child: _tiltedHeading('SHOP YOUR AESTHETICS', r, color: AppColors.primary),
        ),
        SizedBox(height: r.dp(16)),
        if (pairs.isEmpty)
          _empty()
        else
          SizedBox(
            height: sectionHeight,
            child: _AutoScrollHorizontalList(
              itemCount: pairs.length,
              itemExtent: cardWidth + gap,
              padding: EdgeInsets.zero, // flush to the screen edges
              itemBuilder: (_, i) {
                final pair = pairs[i];
                return Padding(
                  padding: EdgeInsets.only(
                    right: i == pairs.length - 1 ? 0 : gap,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _occasionCard(pair[0], cardWidth, cardHeight, r),
                      if (pair.length > 1) ...[
                        SizedBox(height: vGap),
                        _occasionCard(pair[1], cardWidth, cardHeight, r),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        SizedBox(height: r.dp(20)),
      ],
    );
  }

  Widget _occasionCard(_OccasionTile tile, double width, double height, R r) {
    return GestureDetector(
      onTap: () => _openCollectionByHandle(tile.handle, label: tile.label),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            tile.imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: tile.imageUrl!,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    placeholder: (_, _) =>
                        Container(color: const Color(0xFFE0E0E0)),
                    errorWidget: (_, _, _) =>
                        Container(color: const Color(0xFFE0E0E0)),
                  )
                : Image.asset(
                    tile.imageAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (_, _, _) =>
                        Container(color: const Color(0xFFE0E0E0)),
                  ),
            if (tile.label != null && tile.label!.trim().isNotEmpty)
              Positioned(
                left: r.dp(12),
                right: r.dp(12),
                bottom: r.dp(12),
                // Bebas Neue has no italic face, so skew it for the tilt.
                child: Transform(
                  transform: Matrix4.skewX(-0.2),
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    tile.label!.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.subheading,
                      fontSize: r.sp(18),
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                      // No dark overlay on the photo, so keep the label legible.
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _exploreCollectionsSection() {
    final r = R.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: r.dp(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sliverHeadAsBox('EXPLORE COLLECTIONS'),
          _exploreTabsRow(r),
          SizedBox(height: r.dp(6)),
          _exploreCategoryChipsRow(r),
          if (_visibleExploreFitValues.isNotEmpty) ...[
            SizedBox(height: r.dp(6)),
            _exploreFitChipsRow(r),
          ],
          SizedBox(height: r.dp(18)),
          _exploreProductGrid(r),
        ],
      ),
    );
  }

  Widget _exploreTabsRow(R r) {
    return StickerChipRow(
      height: 34,
      children: [
        for (int i = 0; i < _exploreTabDefs.length; i++)
          StickerChip(
            label: _exploreTabDefs[i].label,
            selected: i == _exploreTabIndex,
            style: StickerChipStyle.mini,
            onTap: () => _selectExploreTab(i),
          ),
      ],
    );
  }

  Widget _exploreCategoryChipsRow(R r) {
    final values = _exploreCategoryFilter?.values ?? const [];
    if (values.isEmpty) return const SizedBox.shrink();

    return StickerChipRow(
      height: 36,
      children: [
        StickerChip(
          label: 'ALL',
          selected: _selectedExploreCategoryInput == null,
          style: StickerChipStyle.largeCompact,
          onTap: () => _selectExploreCategory(null),
        ),
        for (final value in values)
          StickerChip(
            label: value.label.toUpperCase(),
            selected: _selectedExploreCategoryInput == value.input,
            style: StickerChipStyle.largeCompact,
            onTap: () => _selectExploreCategory(value),
          ),
      ],
    );
  }

  /// Fit values that have products under the current category. The list is
  /// captured before any fit is picked, so selecting one never hides the
  /// others.
  List<ShopifyFilterValue> get _visibleExploreFitValues => _exploreFitOptions;

  Widget _exploreFitChipsRow(R r) {
    final values = _visibleExploreFitValues;
    return GlassFilterPill(
      caption: 'FIT & FABRIC',
      options: [
        GlassFilterOption(
          label: 'ALL',
          selected: _selectedExploreFitInput == null,
          onTap: () => _selectExploreFit(null),
        ),
        for (final value in values)
          GlassFilterOption(
            label: value.label.toUpperCase(),
            selected: _selectedExploreFitInput == value.input,
            onTap: () => _selectExploreFit(value),
          ),
      ],
    );
  }

  Widget _exploreProductGrid(R r) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.dp(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_exploreLoadingFirst && _exploreProducts.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: r.dp(32)),
              child: Center(
                child: SizedBox(
                  width: r.dp(24),
                  height: r.dp(24),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            )
          else if (_exploreProducts.isEmpty)
            _empty()
          else
            // While a new filter loads, the old products stay (dimmed) so
            // the grid keeps its height instead of collapsing to a spinner.
            IgnorePointer(
              ignoring: _exploreLoadingFirst,
              child: AnimatedOpacity(
                opacity: _exploreLoadingFirst ? 0.4 : 1,
                duration: const Duration(milliseconds: 150),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _exploreProducts.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: r.dp(16),
                    crossAxisSpacing: r.dp(12),
                    childAspectRatio: 0.62,
                  ),
                  itemBuilder: (_, i) => _collectionProductCard(
                    _mapShopifyProduct(_exploreProducts[i]),
                    r,
                  ),
                ),
              ),
            ),
          if (_exploreLoadingMore)
            Padding(
              padding: EdgeInsets.symmetric(vertical: r.dp(20)),
              child: Center(
                child: SizedBox(
                  width: r.dp(20),
                  height: r.dp(20),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _shimmer() {
    final r = R.of(context);
    return Container(
      color: AppColors.bg,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _ShimmerBox(height: r.dp(420)),
          SizedBox(height: r.dp(2)),
          _ShimmerBox(height: r.dp(240)),
          SizedBox(height: r.dp(2)),
          _ShimmerBox(height: r.dp(240)),
          Padding(
            padding: EdgeInsets.all(r.dp(16)),
            child: _ShimmerBox(height: r.dp(14), width: r.dp(180)),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: r.dp(16)),
            child: _ShimmerBox(height: r.dp(260)),
          ),
          SizedBox(height: r.dp(16)),
          _ShimmerBox(height: r.dp(240)),
          SizedBox(height: r.dp(2)),
          _ShimmerBox(height: r.dp(240)),
          SizedBox(height: r.dp(16)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: r.dp(16)),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: r.dp(12),
              mainAxisSpacing: r.dp(16),
              childAspectRatio: 0.62,
              children: List.generate(
                4,
                (_) => _ShimmerBox(height: double.infinity),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    final r = R.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: r.dp(24), horizontal: r.dp(16)),
      child: Center(
        child: Text(
          'Nothing here yet.',
          style: TextStyle(
            fontFamily: AppFonts.body,
            color: AppColors.secondaryText,
            fontSize: r.sp(14),
          ),
        ),
      ),
    );
  }
}

/// Hero banner showing every uploaded image. Slides to the next one every
/// [interval] (looping endlessly) and can be swiped; a small horizontal page
/// indicator ([BannerPageDots]) sits bottom-right of the image (hidden when there's
/// only one image).
class _HeroBannerPager extends StatefulWidget {
  final List<String> imageUrls;
  final Duration interval;

  /// Painted over the images but beneath the page dots.
  final List<Widget> overlays;

  /// Called with the index (into [imageUrls]) of the banner that was tapped.
  final ValueChanged<int>? onTap;
  const _HeroBannerPager({
    required this.imageUrls,
    this.overlays = const [],
    this.onTap,
  }) : interval = const Duration(seconds: 5);

  @override
  State<_HeroBannerPager> createState() => _HeroBannerPagerState();
}

class _HeroBannerPagerState extends State<_HeroBannerPager> {
  // Start far into an unbounded PageView so it can loop in both directions.
  static const int _loopStart = 10000;

  final PageController _controller = PageController(initialPage: _loopStart);
  Timer? _timer;
  int _page = 0;

  int get _count => widget.imageUrls.length;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant _HeroBannerPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrls.length != _count) {
      if (_page >= _count) _page = 0;
      _restartTimer();
    }
  }

  // Restarted on every page change too, so a manual swipe gets a full
  // interval before the next automatic slide.
  void _restartTimer() {
    _timer?.cancel();
    if (_count < 2) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: count > 1 ? null : count,
          onPageChanged: (i) {
            setState(() => _page = (i - _loopStart) % count);
            _restartTimer();
          },
          itemBuilder: (_, i) {
            final index = (i - _loopStart) % count;
            return GestureDetector(
              onTap: widget.onTap == null ? null : () => widget.onTap!(index),
              child: CachedNetworkImage(
                imageUrl: widget.imageUrls[index],
                httpHeaders: ShopifyConstants.imageHeaders,
                fadeInDuration: const Duration(milliseconds: 150),
                fit: BoxFit.cover,
                placeholder: (_, _) => const ColoredBox(color: Colors.black),
                errorWidget: (_, _, _) =>
                    const ColoredBox(color: Colors.black),
              ),
            );
          },
        ),
        ...widget.overlays,
        if (count > 1)
          Positioned(
            right: BannerPageDots.right,
            bottom: BannerPageDots.bottom,
            child: BannerPageDots(count: count, index: _page),
          ),
      ],
    );
  }
}

/// Promo image that cross-fades to the next image every [interval] when
/// there's more than one; a single image is shown as-is.
class _RotatingPromoImage extends StatefulWidget {
  final List<String> imageUrls;
  final Duration interval;
  const _RotatingPromoImage({
    required this.imageUrls,
  }) : interval = const Duration(seconds: 5);

  @override
  State<_RotatingPromoImage> createState() => _RotatingPromoImageState();
}

class _RotatingPromoImageState extends State<_RotatingPromoImage> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant _RotatingPromoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrls.length != widget.imageUrls.length) {
      _index = 0;
      _restartTimer();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.imageUrls.length < 2) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.imageUrls.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrls[_index];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 1.04, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: CachedNetworkImage(
        key: ValueKey(url),
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(color: const Color(0xFF555555)),
        errorWidget: (_, _, _) => Container(color: const Color(0xFF555555)),
      ),
    );
  }
}

class _PromoBlockCard extends StatefulWidget {
  final String? assetPath;
  final List<String> imageUrls;
  final String label;
  final String buttonLabel;
  final double height;
  final VoidCallback onTap;
  const _PromoBlockCard({
    this.assetPath,
    this.imageUrls = const [],
    required this.label,
    required this.buttonLabel,
    required this.height,
    required this.onTap,
  });

  @override
  State<_PromoBlockCard> createState() => _PromoBlockCardState();
}

class _PromoBlockCardState extends State<_PromoBlockCard> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _scale = 0.98),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.imageUrls.isNotEmpty
                  ? _RotatingPromoImage(imageUrls: widget.imageUrls)
                  : Image.asset(
                      widget.assetPath ?? 'assets/denim.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Container(color: const Color(0xFF555555)),
                    ),
              // Scrim only for the app's own label/button; artwork that
              // carries its own text is left undimmed.
              if (widget.label.isNotEmpty || widget.buttonLabel.isNotEmpty)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.45),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              Positioned(
                left: r.dp(18),
                top: r.dp(20),
                child: _tiltedHeading(
                  _twoLineLabel(widget.label.toUpperCase()),
                  r,
                  color: Colors.white,
                ),
              ),
              if (widget.buttonLabel.isNotEmpty)
                Positioned(
                  right: r.dp(18),
                  bottom: r.dp(20),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: r.dp(18),
                      vertical: r.dp(11),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(r.dp(3)),
                    ),
                    child: Text(
                      widget.buttonLabel.toUpperCase(),
                      style: TextStyle(
                        fontFamily: AppFonts.accent,
                        color: const Color(0xFF111111),
                        fontSize: r.sp(12),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopifyProductItem {
  final String id;
  final String handle;
  final String title;
  final String price;
  final String? compareAtPrice;
  final String? discountLabel;
  final String? imageUrl;
  final String imageAssetFallback;

  /// Source product, when this item came from Shopify (needed for wishlist).
  final ShopifyProduct? product;
  const _ShopifyProductItem({
    this.product,
    required this.id,
    required this.handle,
    required this.title,
    required this.price,
    this.compareAtPrice,
    this.discountLabel,
    this.imageUrl,
  }) : imageAssetFallback = 'assets/collection_cargo_olive.jpg';
}

class _ShopTheLookOutfit {
  final String imageAsset;
  final String? imageUrl;
  final List<_ShopTheLookProduct> products;
  const _ShopTheLookOutfit({
    required this.imageAsset,
    this.imageUrl,
    required this.products,
  });
}

class _ShopTheLookAutoSlideCard extends StatefulWidget {
  final List<_ShopTheLookOutfit> outfits;
  final double heroHeight;
  final double productRowHeight;
  final Duration interval;
  const _ShopTheLookAutoSlideCard({
    super.key,
    required this.outfits,
    required this.heroHeight,
    required this.productRowHeight,
  }) : interval = const Duration(seconds: 5);

  @override
  State<_ShopTheLookAutoSlideCard> createState() =>
      _ShopTheLookAutoSlideCardState();
}

class _ShopTheLookAutoSlideCardState extends State<_ShopTheLookAutoSlideCard> {
  // Now follows the app theme instead of a fixed white/dark palette.
  // Matches the home screen background so the card blends into the page.
  Color get _cardBg => AppColors.bg;
  Color get _cardTextColor => AppColors.primary;
  Color get _cardBorder => AppColors.border;

  late final PageController _controller;
  Timer? _timer;

  /// How many full cycles of looks sit before the starting page, i.e. how far
  /// back the user can swipe. Large enough that nobody reaches the start.
  static const int _kLoopStartCycles = 1000;

  @override
  void initState() {
    super.initState();
    // Start deep into the endless page list so the user can swipe backwards
    // from the first look straight to the last one.
    _controller = PageController(
      initialPage: widget.outfits.length > 1
          ? widget.outfits.length * _kLoopStartCycles
          : 0,
    );
    if (widget.outfits.length > 1) {
      _startAutoSlide();
    }
  }

  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load every look's photo up front so sliding to the next one shows the
    // image immediately instead of an empty box that pops in.
    if (_precached) return;
    _precached = true;
    for (final outfit in widget.outfits) {
      final ImageProvider provider = outfit.imageUrl != null
          ? CachedNetworkImageProvider(outfit.imageUrl!)
          : AssetImage(outfit.imageAsset);
      precacheImage(provider, context, onError: (_, _) {});
    }
  }

  void _startAutoSlide() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      // Always move forward; the endless PageView wraps back to look 1.
      _controller.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  /// Pause auto-slide while the user drags, and restart the countdown when
  /// they let go, so a timer tick never yanks the page mid-swipe.
  bool _onScrollNotification(ScrollNotification n) {
    if (widget.outfits.length < 2) return false;
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _timer?.cancel();
    } else if (n is ScrollEndNotification) {
      if (_timer == null || !_timer!.isActive) _startAutoSlide();
    }
    return false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _openProductDetail(BuildContext context, ShopifyProduct product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(
          handle: product.handle,
          title: product.title,
          heroImageUrl: product.primaryImageUrl,
        ),
      ),
    );
  }

  void _showQuickAddToCart(BuildContext context, ShopifyProduct product) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, _) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(
            opacity: anim,
            child: ProductPeekDialog(
              product: product,
              primary: AppColors.primary,
              onPrimary: AppColors.onPrimary,
              cardColor: AppColors.card,
              bgColor: AppColors.bg,
              borderColor: AppColors.border,
              secondaryTxt: AppColors.secondaryText,
              numberFont: AppFonts.number,
              rupeeFont: AppFonts.rupee,
              bodyFont: AppFonts.bold,
              onAddToCart: (variantId) async {
                Navigator.of(ctx).pop();
                final success = await CartService.instance.addLine(
                  variantId: variantId,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? '${product.title} added to cart'
                            : (CartService.instance.lastError ?? 'Failed to add item to cart'),
                        style: const TextStyle(fontFamily: AppFonts.accent),
                      ),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              },
              onOpenDetail: () {
                Navigator.of(ctx).pop();
                _openProductDetail(context, product);
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);

    if (widget.outfits.isEmpty) {
      return Container(color: const Color(0xFF555555));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: _buildPages(r),
    );
  }

  Widget _buildPages(R r) {
    final int count = widget.outfits.length;
    return PageView.builder(
      controller: _controller,
      // Endless when there's more than one look: page i shows look i % count,
      // so swiping past the last look wraps to the first and vice versa.
      itemCount: count > 1 ? null : count,
      itemBuilder: (_, i) {
        final outfit = widget.outfits[i % count];
        return Container(
          decoration: BoxDecoration(color: _cardBg),
          // Same side margin for the photo and the product rows, so the rows
          // start and end exactly where the photo does.
          padding: EdgeInsets.symmetric(horizontal: r.dp(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: widget.heroHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: _cardBg,
                      child: outfit.imageUrl != null
                          // No fade and a background-coloured placeholder, so
                          // a slide never flashes a dark box while the next
                          // photo loads.
                          ? CachedNetworkImage(
                              imageUrl: outfit.imageUrl!,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              placeholder: (_, _) => const SizedBox.expand(),
                              errorWidget: (_, _, _) =>
                                  const SizedBox.expand(),
                            )
                          : Image.asset(
                              outfit.imageAsset,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.expand(),
                            ),
                    ),
                    // Positioned(
                    //   top: r.dp(12),
                    //   left: r.dp(12),
                    //   child: Container(
                    //     padding: EdgeInsets.symmetric(
                    //       horizontal: r.dp(10),
                    //       vertical: r.dp(5),
                    //     ),
                    //     color: Colors.white.withOpacity(0.92),
                    //     child: Text(
                    //       'LOOK ${i + 1}/${widget.outfits.length}',
                    //       style: TextStyle(
                    //         fontFamily: AppFonts.bold,
                    //         fontSize: r.sp(9.5),
                    //         letterSpacing: 0.6,
                    //         color: AppColors.primary,
                    //       ),
                    //     ),
                    //   ),
                    // ),
                  ],
                ),
              ),
              ...List.generate(outfit.products.length, (j) {
                final item = outfit.products[j];
                final ShopifyProduct? product = item.product;
                return SizedBox(
                  height: widget.productRowHeight,
                  child: GestureDetector(
                    onTap: product != null
                        ? () => _openProductDetail(context, product)
                        : null,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: _cardBorder, width: 1),
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      child: Row(
                        children: [
                          Container(
                            width: r.dp(72),
                            height: r.dp(72),
                            color: const Color(0xFFECECEC),
                            child: item.imageUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: item.imageUrl!,
                                    fit: BoxFit.cover,
                                    placeholder: (_, _) => const SizedBox(),
                                    errorWidget: (_, _, _) =>
                                        const SizedBox(),
                                  )
                                : Image.asset(
                                    item.imageAsset,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox(),
                                  ),
                          ),
                          SizedBox(width: r.dp(10)),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Wraps onto a second line instead of "...".
                                Text(
                                  item.title,
                                  maxLines: 2,
                                  softWrap: true,
                                  style: TextStyle(
                                    fontFamily: AppFonts.body,
                                    fontSize: r.sp(12),
                                    color: _cardTextColor,
                                    height: 1.25,
                                  ),
                                ),
                                SizedBox(height: r.dp(2)),
                                Text(
                                  item.price,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: AppFonts.number,
                                    fontSize: r.sp(11),
                                    color: _cardTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: r.dp(12)),
                          GestureDetector(
                            onTap: product != null
                                ? () => _showQuickAddToCart(context, product)
                                : null,
                            // White box / black plus in dark theme, inverted in light.
                            child: Container(
                              width: r.dp(26),
                              height: r.dp(26),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(r.dp(3)),
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                size: r.dp(15),
                                color: AppColors.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double height;
  final double? width;
  final BorderRadius? borderRadius;
  const _ShimmerBox({required this.height, this.width}) : borderRadius = null;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400), 
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final double t = _controller.value;
          return ShaderMask(
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment(-1 - t * 2, 0),
              end: Alignment(1 - t * 2, 0),
              colors: const [
                Color(0xFFE7E7E7),
                Color(0xFFF6F6F6),
                Color(0xFFE7E7E7),
              ],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(rect),
            child: Container(
              height: widget.height,
              width: widget.width,
              color: const Color(0xFFE7E7E7),
            ),
          );
        },
      ),
    );
  }
}

class _OccasionTile {
  final String imageAsset;
  final String? imageUrl;
  final String handle;
  final String? label;
  const _OccasionTile({
    required this.imageAsset,
    this.imageUrl,
    required this.handle,
    this.label,
  });
}

class _ShopTheLookProduct {
  final String title;
  final String price;
  final String imageAsset;
  final String? imageUrl;
  final ShopifyProduct? product;
  const _ShopTheLookProduct({
    required this.title,
    required this.price,
    required this.imageAsset,
    this.imageUrl,
    this.product,
  });
}

class _ExploreTabDef {
  final String label;
  final String handle;
  const _ExploreTabDef(this.label, this.handle);
}

class _PromoBlockData {
  final String? assetPath;
  final List<String> imageUrls;
  final String label;
  final String buttonLabel;
  final String collectionHandle;
  const _PromoBlockData({
    this.assetPath,
    this.imageUrls = const [],
    required this.label,
    required this.buttonLabel,
    required this.collectionHandle,
  });
}

class _AutoScrollHorizontalList extends StatefulWidget {
  final int itemCount;
  final double itemExtent; // width of one item including its trailing gap
  final EdgeInsetsGeometry padding;
  final IndexedWidgetBuilder itemBuilder;
  final Duration interval;
  final Duration animationDuration;

  const _AutoScrollHorizontalList({
    required this.itemCount,
    required this.itemExtent,
    required this.itemBuilder,
    this.padding = EdgeInsets.zero,
  })  : interval = const Duration(seconds: 5),
        animationDuration = const Duration(milliseconds: 600);

  @override
  State<_AutoScrollHorizontalList> createState() =>
      _AutoScrollHorizontalListState();
}

class _AutoScrollHorizontalListState extends State<_AutoScrollHorizontalList> {
  final ScrollController _controller = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.itemCount > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoScroll());
    }
  }

  void _startAutoScroll() {
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      final double max = _controller.position.maxScrollExtent;
      if (max <= 0) return;

      final double next = _controller.offset + widget.itemExtent;
      if (next >= max) {
        _controller
            .animateTo(
              max,
              duration: widget.animationDuration,
              curve: Curves.easeInOut,
            )
            .then((_) {
              if (!mounted) return;
              Future.delayed(const Duration(milliseconds: 400), () {
                if (mounted && _controller.hasClients) {
                  _controller.animateTo(
                    0,
                    duration: widget.animationDuration,
                    curve: Curves.easeInOut,
                  );
                }
              });
            });
      } else {
        _controller.animateTo(
          next,
          duration: widget.animationDuration,
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      padding: widget.padding,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      itemCount: widget.itemCount,
      itemBuilder: widget.itemBuilder,
    );
  }
}

/// Section/banner heading style shared across the home screen: Anton at the
/// Denim / Cargos size, skewed for an italic tilt (Anton has no italic face).
Widget _tiltedHeading(String text, R r, {required Color color}) {
  return Transform(
    transform: Matrix4.skewX(-0.2),
    alignment: Alignment.bottomLeft,
    child: Text(
      text,
      style: TextStyle(
        fontFamily: AppFonts.heading,
        color: color,
        fontSize: r.sp(26),
        // Anton has a single (regular) weight; asking for w600 made Flutter
        // fake a bold by thickening the strokes.
        fontWeight: FontWeight.w400,
        height: 1.05,
      ),
    ),
  );
}

/// Puts the last word of a promo label on its own line:
/// "SIGNATURE DENIM" -> "SIGNATURE\nDENIM", "CARGOS & UTILITY" -> "CARGOS &\nUTILITY".
String _twoLineLabel(String label) {
  final String text = label.trim();
  final int split = text.lastIndexOf(' ');
  if (split <= 0) return text;
  return '${text.substring(0, split)}\n${text.substring(split + 1)}';
}
