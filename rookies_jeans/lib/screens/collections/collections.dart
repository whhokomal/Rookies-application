import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/models/banner_model.dart';
import 'package:rookies_jeans/models/collection_model.dart';
import 'package:rookies_jeans/models/home_content_models.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/models/shop_menu_model.dart';
import 'package:rookies_jeans/screens/products/product_detail_page.dart';
import 'package:rookies_jeans/screens/products/product_peek_dialog.dart';
import 'package:rookies_jeans/screens/products/products.dart';
import 'package:rookies_jeans/services/cart_service.dart';
import 'package:rookies_jeans/services/shopify_storefront_service.dart';
import 'package:rookies_jeans/widgets/banner_page_dots.dart';
import 'package:rookies_jeans/widgets/price_text.dart';
import 'package:rookies_jeans/widgets/sticker_chip.dart';
import 'package:url_launcher/url_launcher.dart';

/// Backdrop for product cutouts, which are shot on a light grey. Fixed in
/// both themes so the photos never sit on a mismatched box.
const Color _kCutoutBg = Color(0xFFEDEDED);

/// Everything the Collections tab shows, loaded together.
class _CollectionsPageData {
  const _CollectionsPageData({
    required this.sections,
    required this.banners,
    required this.looks,
    required this.aesthetics,
  });

  final List<ShopMenuSection> sections;
  final List<HomeBanner> banners;
  final List<ShopTheLookEntry> looks;
  final List<OccasionTileContent> aesthetics;
}

/// Which inline accordion panel is currently open. `null` means both are
/// collapsed. Only one panel can be open at a time — opening one closes the
/// other.
enum _MenuPanel { topWear, bottomWear }

/// The Collections tab (menu icon in the bottom nav): a "Collections" row
/// that opens [CollectionsShowcasePage], plus Top Wear / Bottom Wear
/// accordions listing each category and its fits.
class ExploreCategoriesPage extends StatefulWidget {
  const ExploreCategoriesPage({super.key});
  @override
  State<ExploreCategoriesPage> createState() => _ExploreCategoriesPageState();
}

class _ExploreCategoriesPageState extends State<ExploreCategoriesPage> {
  late Future<List<ShopMenuSection>> _future;

  _MenuPanel? _expandedPanel;

  @override
  void initState() {
    super.initState();
    _future = ShopifyStorefrontService.instance.getExploreMenuSections();
  }

  Future<void> _refresh() async {
    setState(() {
      ShopifyStorefrontService.instance.clearCache();
      _future = ShopifyStorefrontService.instance.getExploreMenuSections();
      _expandedPanel = null;
    });
    await _future;
  }

  void _togglePanel(_MenuPanel panel) {
    setState(() {
      _expandedPanel = _expandedPanel == panel ? null : panel;
    });
  }

  void _openCollections() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CollectionsShowcasePage()),
    );
  }

  void _openCategory(
    String title,
    String collectionHandle, {
    String? fitTitle,
  }) {
    if (collectionHandle.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductsPage(
          collection: ShopifyCollection(
            id: collectionHandle,
            title: title,
            handle: collectionHandle,
            label: title.toUpperCase(),
          ),
          initialFitFilter: fitTitle,
        ),
      ),
    );
  }

  void _openFit(String categoryTitle, String categoryHandle, ShopMenuFit fit) {
    // Fits that link to their own collection open it directly; older ones
    // fall back to filtering the parent category by fit name.
    final String? handle = fit.collectionHandle;
    if (handle != null && handle.isNotEmpty) {
      _openCategory(fit.title, handle);
    } else {
      _openCategory(categoryTitle, categoryHandle, fitTitle: fit.title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final titleSize = (width * 0.09).clamp(20.0, 40.0);

    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.card,
          elevation: 0,
          centerTitle: false,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
              ),
              Expanded(
                child: Text(
                  'EXPLORE CATEGORIES',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: titleSize,
                    height: 1,
                    fontFamily: AppFonts.heading,
                    fontStyle: FontStyle.italic,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<ShopMenuSection>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorState(onRetry: _refresh);
                }

                final sections = snapshot.data ?? [];
                final ShopMenuSection? topWear =
                    _sectionByHandle(sections, 'top-wear');
                final ShopMenuSection? bottomWear =
                    _sectionByHandle(sections, 'bottom-wear');

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _MenuRow(
                      title: 'COLLECTIONS',
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.primary,
                      ),
                      onTap: _openCollections,
                      fontFamily: AppFonts.body,
                      fontWeight: FontWeight.w900,
                    ),
                    _divider(),
                    _MenuRow(
                      title: (topWear?.title ?? 'TOP WEAR').toUpperCase(),
                      trailing: _panelIcon(_expandedPanel == _MenuPanel.topWear),
                      onTap: () => _togglePanel(_MenuPanel.topWear),
                      fontFamily: AppFonts.body,
                      fontWeight: FontWeight.w900,
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState: _expandedPanel == _MenuPanel.topWear
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: _CategoriesGrid(
                        categories: topWear?.categories ?? const [],
                        headFont: AppFonts.body,
                        bodyFont: AppFonts.accent,
                        onCategoryTap: _openCategory,
                        onFitTap: _openFit,
                      ),
                      secondChild: const SizedBox(width: double.infinity),
                    ),
                    _divider(),
                    _MenuRow(
                      title: (bottomWear?.title ?? 'BOTTOM WEAR').toUpperCase(),
                      trailing:
                          _panelIcon(_expandedPanel == _MenuPanel.bottomWear),
                      onTap: () => _togglePanel(_MenuPanel.bottomWear),
                      fontFamily: AppFonts.body,
                      fontWeight: FontWeight.w900,
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState: _expandedPanel == _MenuPanel.bottomWear
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: _CategoriesGrid(
                        categories: bottomWear?.categories ?? const [],
                        headFont: AppFonts.body,
                        bodyFont: AppFonts.accent,
                        onCategoryTap: _openCategory,
                        onFitTap: _openFit,
                      ),
                      secondChild: const SizedBox(width: double.infinity),
                    ),
                    _divider(),
                    // Clearance for the floating bottom nav bar.
                    const SizedBox(height: 110),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelIcon(bool expanded) => Icon(
        expanded ? Icons.remove_rounded : Icons.add_rounded,
        color: AppColors.primary,
        size: 22,
      );

  Widget _divider() => Divider(height: 1, thickness: 1, color: AppColors.border);

  ShopMenuSection? _sectionByHandle(
      List<ShopMenuSection> sections, String handle) {
    for (final s in sections) {
      if (s.handle == handle) return s;
    }
    return null;
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.title,
    required this.trailing,
    required this.onTap,
    required this.fontFamily,
    this.fontWeight = FontWeight.w600,
  });

  final String title;
  final Widget trailing;
  final VoidCallback onTap;
  final String fontFamily;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: 15,
                  fontWeight: fontWeight,
                  letterSpacing: 0.5,
                  color: AppColors.primary,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// The two-column "category name (bold) + list of fits" grid shown under an
/// expanded Top Wear / Bottom Wear panel — matches the merchant's menu
/// design: categories alternate left/right column in the order Shopify
/// returns them.
class _CategoriesGrid extends StatelessWidget {
  const _CategoriesGrid({
    required this.categories,
    required this.headFont,
    required this.bodyFont,
    required this.onCategoryTap,
    required this.onFitTap,
  });

  final List<ShopMenuCategory> categories;
  final String headFont;
  final String bodyFont;
  final void Function(String title, String collectionHandle) onCategoryTap;
  final void Function(
    String categoryTitle,
    String collectionHandle,
    ShopMenuFit fit,
  ) onFitTap;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Text(
          'No categories found',
          style: TextStyle(fontFamily: bodyFont, color: AppColors.secondaryText),
        ),
      );
    }

    final List<ShopMenuCategory> left = [];
    final List<ShopMenuCategory> right = [];
    for (int i = 0; i < categories.length; i++) {
      (i.isEven ? left : right).add(categories[i]);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: left.map(_block).toList(),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: right.map(_block).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _block(ShopMenuCategory category) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => onCategoryTap(category.title, category.collectionHandle),
            child: Text(
              category.title,
              style: TextStyle(
                fontFamily: headFont,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final fit in category.fits)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () =>
                    onFitTap(category.title, category.collectionHandle, fit),
                child: Text(
                  fit.title,
                  style: TextStyle(
                    fontFamily: bodyFont,
                    fontSize: 13,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// App bar with a back arrow and a big heading-font title, used by pages
/// pushed from the Collections tab.
class _BackTitleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _BackTitleAppBar({required this.title});
  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final titleSize =
        (MediaQuery.of(context).size.width * 0.09).clamp(20.0, 40.0);
    return AppBar(
      backgroundColor: AppColors.card,
      elevation: 0,
      centerTitle: false,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: AppColors.primary,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: titleSize,
                height: 1,
                fontFamily: AppFonts.heading,
                fontStyle: FontStyle.italic,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The full collections showcase opened from the "Collections" row on
/// [ExploreCategoriesPage]: hero banner, "Shop by category", "Shop the
/// look" and "Find your aesthetic".
class CollectionsShowcasePage extends StatefulWidget {
  const CollectionsShowcasePage({super.key, this.scrollToLooks = false});

  /// Open scrolled to the "Shop the look" section (home's "View all").
  final bool scrollToLooks;

  @override
  State<CollectionsShowcasePage> createState() => _CollectionsShowcasePageState();
}

class _CollectionsShowcasePageState extends State<CollectionsShowcasePage> {
  /// Looks shown at first, then how many more each "Show more" tap adds.
  static const int _kLooksInitial = 6;
  static const int _kLooksStep = 6;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _looksKey = GlobalKey();
  bool _scrolledToLooks = false;

  late Future<_CollectionsPageData> _future;

  /// Selected section tab (TOP WEAR / BOTTOM WEAR / ...).
  int _sectionIndex = 0;

  /// Tab drawn as selected. Moves on tap so the chip's fade animation plays
  /// first; [_sectionIndex] (and the heavy category list below it) follows
  /// once the fade is done, so building the new cards doesn't eat the
  /// animation's frames.
  int _highlightedSection = 0;
  Timer? _sectionSwitch;
  int _looksShown = _kLooksInitial;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _sectionSwitch?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Brings the Shop the look heading to the top. Slivers below the fold
  /// aren't built yet, so step down a screen at a time until it exists.
  void _scrollToLooks([int attempts = 0]) {
    if (!mounted || !_scrollController.hasClients) return;
    final ctx = _looksKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
      return;
    }
    final position = _scrollController.position;
    if (attempts > 30 || position.pixels >= position.maxScrollExtent) return;
    _scrollController.jumpTo(
      (position.pixels + position.viewportDimension)
          .clamp(0.0, position.maxScrollExtent),
    );
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToLooks(attempts + 1));
  }

  Future<_CollectionsPageData> _load() async {
    final service = ShopifyStorefrontService.instance;
    final results = await Future.wait([
      service.getExploreMenuSections(),
      service.getCollectionsBanners(),
      service.getShopTheLookEntries(),
      service.getOccasionTilesContent(),
    ]);
    final looks = [...results[2] as List<ShopTheLookEntry>]
      ..retainWhere((l) => l.products.isNotEmpty)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final aesthetics = [...results[3] as List<OccasionTileContent>]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return _CollectionsPageData(
      sections: results[0] as List<ShopMenuSection>,
      banners: (results[1] as List<HomeBanner>)
          .where((b) => b.imageUrl != null)
          .toList(),
      looks: looks,
      aesthetics: aesthetics,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      ShopifyStorefrontService.instance.clearCache();
      _future = _load();
      _looksShown = _kLooksInitial;
    });
    await _future;
  }

  // ---------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------

  void _openCollection(String handle, String title, {String? fitTitle}) {
    if (handle.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductsPage(
          collection: ShopifyCollection(
            id: handle,
            title: title,
            handle: handle,
            label: title.toUpperCase(),
          ),
          initialFitFilter: fitTitle,
        ),
      ),
    );
  }

  void _openFit(ShopMenuCategory category, ShopMenuFit fit) {
    // Menu items link to their own collection; older ones without a
    // resource fall back to filtering the parent category by fit name.
    if (fit.collectionHandle != null && fit.collectionHandle!.isNotEmpty) {
      _openCollection(fit.collectionHandle!, fit.title);
    } else {
      _openCollection(
        category.collectionHandle,
        category.title,
        fitTitle: fit.title,
      );
    }
  }

  /// Page heading for a collection opened from a banner: the banner's
  /// title, else the handle ("aw26" -> "AW26").
  String _bannerTitle(HomeBanner banner, String handle) =>
      banner.title.trim().isNotEmpty
          ? banner.title
          : handle.replaceAll('-', ' ').toUpperCase();

  void _openBanner(HomeBanner banner) {
    final String? url = banner.link;
    if (url == null) return;
    final product = RegExp(r'/products/([^/?#]+)').firstMatch(url);
    if (product != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ProductDetailPage(handle: product.group(1)!, title: banner.title),
        ),
      );
      return;
    }
    final match = RegExp(r'/collections/([^/?#]+)').firstMatch(url);
    if (match != null) {
      final handle = match.group(1)!;
      _openCollection(handle, _bannerTitle(banner, handle));
    } else if (url.startsWith('http://') || url.startsWith('https://')) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      // A bare collection handle; Shopify handles are lower case.
      final handle = url.toLowerCase();
      _openCollection(handle, _bannerTitle(banner, handle));
    }
  }

  void _openProduct(ShopifyProduct product) {
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

  void _showQuickAdd(ShopifyProduct product) {
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
                final success =
                    await CartService.instance.addLine(variantId: variantId);
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    content: Text(
                      success
                          ? '${product.title} added to cart'
                          : (CartService.instance.lastError ?? 'Failed to add item to cart'),
                      style: const TextStyle(fontFamily: AppFonts.accent),
                    ),
                    duration: const Duration(seconds: 2),
                  ));
              },
              onOpenDetail: () {
                Navigator.of(ctx).pop();
                _openProduct(product);
              },
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: _BackTitleAppBar(title: 'COLLECTIONS'),
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refresh,
            child: FutureBuilder<_CollectionsPageData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return _ErrorState(onRetry: _refresh);
                }
                return _buildContent(snapshot.data!);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(_CollectionsPageData data) {
    final sections =
        data.sections.where((s) => s.categories.isNotEmpty).toList();
    final int sectionIndex =
        _sectionIndex < sections.length ? _sectionIndex : 0;
    final categories =
        sections.isEmpty ? const <ShopMenuCategory>[] : sections[sectionIndex].categories;

    if (widget.scrollToLooks && !_scrolledToLooks && data.looks.isNotEmpty) {
      _scrolledToLooks = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLooks());
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _BannerCarousel(
            banners: data.banners,
            onTap: _openBanner,
          ),
        ),
        if (categories.isNotEmpty) ...[
          SliverToBoxAdapter(child: _heading('SHOP BY CATEGORY')),
          SliverToBoxAdapter(
            child: _sectionTabs(
              sections,
              _highlightedSection < sections.length ? _highlightedSection : 0,
            ),
          ),
          for (final c in categories)
            SliverToBoxAdapter(child: _categoryGroup(c)),
        ],
        if (data.looks.isNotEmpty) ...[
          SliverToBoxAdapter(
            key: _looksKey,
            child: _heading(
              'SHOP THE LOOK',
              trailing: '${data.looks.length} '
                  '${data.looks.length == 1 ? 'LOOK' : 'LOOKS'}',
            ),
          ),
          SliverToBoxAdapter(child: _looksGrid(data.looks)),
        ],
        if (data.aesthetics.isNotEmpty) ...[
          SliverToBoxAdapter(child: _heading('FIND YOUR AESTHETIC')),
          SliverToBoxAdapter(child: _aestheticsGrid(data.aesthetics)),
        ],
        // Clearance for the floating bottom nav bar.
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Shared pieces
  // ---------------------------------------------------------------------

  double _headingSize(double factor, double min, double max) =>
      (MediaQuery.of(context).size.width * factor).clamp(min, max);

  TextStyle _headStyle(double size, {Color? color}) => TextStyle(
        fontFamily: AppFonts.heading,
        fontSize: size,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w700,
        height: 1.05,
        color: color ?? AppColors.primary,
      );

  /// Big italic section title with an optional small caption on the right
  /// ("8 LOOKS", "11 CATEGORIES").
  Widget _heading(String title, {String? trailing, bool divider = false}) {
    final double size = divider
        ? _headingSize(0.075, 24, 34)
        : _headingSize(0.095, 30, 44);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, divider ? 28 : 32, 16, divider ? 0 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _headStyle(size),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing,
                  style: TextStyle(
                    fontFamily: AppFonts.number,
                    fontSize: 10,
                    letterSpacing: 1.6,
                    color: AppColors.secondaryText,
                  ),
                ),
            ],
          ),
          if (divider) ...[
            const SizedBox(height: 8),
            Container(height: 1.2, color: AppColors.primary),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _imageOrPlaceholder(String? url, {BoxFit fit = BoxFit.cover}) {
    final placeholder = Center(
      child: Icon(Icons.image_outlined, color: Colors.black26, size: 28),
    );
    if (url == null) return placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      alignment: Alignment.topCenter,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, _) => const SizedBox.shrink(),
      errorWidget: (_, _, _) => placeholder,
    );
  }

  // ---------------------------------------------------------------------
  // Shop by category
  // ---------------------------------------------------------------------

  /// One row of section tabs (TOP WEAR / BOTTOM WEAR / ...), sharing the
  /// screen width equally; the selected section's categories are listed
  /// below it.
  Widget _sectionTabs(List<ShopMenuSection> sections, int selected) {
    if (sections.length < 2) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            for (int i = 0; i < sections.length; i++)
              Expanded(
                child: StickerChip(
                  label: sections[i].title.toUpperCase(),
                  selected: i == selected,
                  style: StickerChipStyle.small,
                  fadeAnimation: true,
                  onTap: () => _selectSection(i),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _selectSection(int i) {
    if (i == _highlightedSection) return;
    setState(() => _highlightedSection = i);
    _sectionSwitch?.cancel();
    _sectionSwitch = Timer(StickerChip.fadeDuration, () {
      if (mounted) setState(() => _sectionIndex = _highlightedSection);
    });
  }

  bool get _wideLayout => MediaQuery.of(context).size.width >= 700;

  /// A category heading plus its cards; [fits] narrows the cards shown
  /// (e.g. to one fabric), defaulting to all of the category's fits.
  Widget _categoryGroup(ShopMenuCategory category, {List<ShopMenuFit>? fits}) {
    final List<ShopMenuFit> shownFits = fits ?? category.fits;
    final double screenW = MediaQuery.of(context).size.width;
    // Wide: six cards per row (as in the design); phone: a swipeable row
    // with the next card peeking in.
    final double cardWidth = _wideLayout
        ? (screenW - 32 - 10 * 5) / 6
        : (screenW * 0.38).clamp(120.0, 200.0);
    final double imageHeight = cardWidth * 1.2;
    final int count = shownFits.isEmpty ? 1 : shownFits.length;

    final List<Widget> cards = shownFits.isEmpty
        ? [
            _categoryCard(
              label: category.title,
              imageUrl: category.imageUrl,
              width: cardWidth,
              imageHeight: imageHeight,
              onTap: () => _openCollection(
                category.collectionHandle,
                category.title,
              ),
            ),
          ]
        : shownFits
            .map((fit) => _categoryCard(
                  label: fit.title,
                  imageUrl: fit.imageUrl ?? category.imageUrl,
                  width: cardWidth,
                  imageHeight: imageHeight,
                  onTap: () => _openFit(category, fit),
                ))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              _openCollection(category.collectionHandle, category.title),
          child: _heading(
            category.title,
            trailing: '$count ${count == 1 ? 'CATEGORY' : 'CATEGORIES'}',
            divider: true,
          ),
        ),
        if (_wideLayout)
          // Tablet / wide: every card visible, wrapping onto new rows.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 10, runSpacing: 18, children: cards),
          )
        else
          SizedBox(
            // Image + gap + up to two lines of label.
            height: imageHeight + 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => cards[i],
            ),
          ),
      ],
    );
  }

  Widget _categoryCard({
    required String label,
    required String? imageUrl,
    required double width,
    required double imageHeight,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            Container(
              width: width,
              height: imageHeight,
              color: _kCutoutBg,
              child: _imageOrPlaceholder(imageUrl),
            ),
            const SizedBox(height: 10),
            Text(
              label.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.number,
                fontSize: 11,
                letterSpacing: 1,
                height: 1.3,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Shop the look
  // ---------------------------------------------------------------------

  Widget _looksGrid(List<ShopTheLookEntry> looks) {
    final visible = looks.take(_looksShown).toList();
    final int perRow = _wideLayout ? 4 : 2;
    final rows = <Widget>[];
    for (int i = 0; i < visible.length; i += perRow) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int j = 0; j < perRow; j++) ...[
              if (j > 0) const SizedBox(width: 12),
              Expanded(
                child: i + j < visible.length
                    ? _lookCard(visible[i + j])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows,
          if (looks.length > _looksShown)
            GestureDetector(
              onTap: () => setState(() => _looksShown += _kLooksStep),
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'SHOW MORE',
                  style: TextStyle(
                    fontFamily: AppFonts.number,
                    fontSize: 13,
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lookCard(ShopTheLookEntry look) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => _openProduct(look.products.first),
          child: AspectRatio(
            aspectRatio: 0.72,
            child: ColoredBox(
              color: AppColors.bg,
              child: _imageOrPlaceholder(
                look.imageUrl ?? look.products.first.primaryImageUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (int j = 0; j < look.products.length; j++) ...[
          if (j > 0) Divider(height: 1, color: AppColors.border),
          _lookProductRow(look.products[j]),
        ],
        Divider(height: 1, color: AppColors.border),
      ],
    );
  }

  Widget _lookProductRow(ShopifyProduct product) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openProduct(product),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  PriceText(
                    product.formattedPrice,
                    currencyCode: product.currencyCode,
                    fontSize: 12,
                    color: AppColors.primary,
                    amountFontFamily: AppFonts.body,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _showQuickAdd(product),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 18,
                color: AppColors.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Find your aesthetic
  // ---------------------------------------------------------------------

  Widget _aestheticsGrid(List<OccasionTileContent> tiles) {
    const double gap = 8;
    final rest = tiles.skip(1).toList();
    final rows = <Widget>[];
    for (int i = 0; i < rest.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: gap),
        child: Row(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 0.78,
                child: _aestheticTile(rest[i], large: false),
              ),
            ),
            const SizedBox(width: gap), 
            Expanded(
              child: i + 1 < rest.length
                  ? AspectRatio(
                      aspectRatio: 0.78,
                      child: _aestheticTile(rest[i + 1], large: false),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.2,
            child: _aestheticTile(tiles.first, large: true),
          ),
          ...rows,
        ],
      ),
    );
  }

  Widget _aestheticTile(OccasionTileContent tile, {required bool large}) {
    final String label = (tile.label ?? '').trim();
    return GestureDetector(
      onTap: () => _openCollection(
        tile.collectionHandle,
        label.isNotEmpty ? label : tile.collectionHandle,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: const Color(0xFF333333),
              child: _imageOrPlaceholder(tile.imageUrl),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                  stops: [0.55, 1.0],
                ),
              ),
            ),
            if (label.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.subheading,
                    fontSize: large
                        ? _headingSize(0.11, 34, 54)
                        : _headingSize(0.075, 24, 36),
                    fontStyle: FontStyle.italic,
                    letterSpacing: 0.5,
                    height: 1.05,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Full-width auto-advancing banner with bar-style page dots.
class _BannerCarousel extends StatefulWidget {
  const _BannerCarousel({required this.banners, required this.onTap});

  final List<HomeBanner> banners;
  final ValueChanged<HomeBanner> onTap;

  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.banners.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        (_index + 1) % widget.banners.length,
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
    final size = MediaQuery.of(context).size;
    // Follow the first banner's own shape so the whole picture shows
    // (nothing cut off top or bottom); other slides fill the same box.
    final double? ratio =
        widget.banners.isNotEmpty ? widget.banners.first.aspectRatio : null;
    final double height = ratio != null
        ? (size.width / ratio).clamp(200.0, size.height * 0.8)
        : (size.height * 0.62).clamp(320.0, 620.0);

    if (widget.banners.isEmpty) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: Image.asset('assets/banner.jpeg', fit: BoxFit.cover),
      );
    }

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) {
                _timer?.cancel();
              } else if (n is ScrollEndNotification) {
                _restartTimer();
              }
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.banners.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                final banner = widget.banners[i];
                return GestureDetector(
                  onTap: () => widget.onTap(banner),
                  child: CachedNetworkImage(
                    imageUrl: banner.imageUrl!,
                    fit: BoxFit.cover,
                    // If a slide is a different shape, keep its top (the
                    // headline) and trim the bottom instead.
                    alignment: Alignment.topCenter,
                    placeholder: (_, _) =>
                        const ColoredBox(color: Color(0xFF2A2A2A)),
                    errorWidget: (_, _, _) =>
                        const ColoredBox(color: Color(0xFF2A2A2A)),
                  ),
                );
              },
            ),
          ),
          if (widget.banners.length > 1)
            Positioned(
              right: BannerPageDots.right,
              bottom: BannerPageDots.bottom,
              child: BannerPageDots(
                count: widget.banners.length,
                index: _index,
              ),
            ),
        ],
      ),
    );
  }
}

/// Full list of every collection in the store — opened from the
/// full collections catalog (not currently linked from the Collections tab).
class AllCollectionsPage extends StatefulWidget {
  const AllCollectionsPage({super.key});
  @override
  State<AllCollectionsPage> createState() => _AllCollectionsPageState();
}

class _AllCollectionsPageState extends State<AllCollectionsPage> {
  late Future<List<ShopifyCollection>> _future;

  @override
  void initState() {
    super.initState();
    _future = ShopifyStorefrontService.instance.getAllCollections();
  }

  Future<void> _refresh() async {
    setState(() {
      ShopifyStorefrontService.instance.clearCache();
      _future = ShopifyStorefrontService.instance.getAllCollections();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final titleSize = (width * 0.09).clamp(20.0, 40.0);
    final maxTileExtent = width >= 1024
        ? 260.0
        : width >= 600
            ? 240.0
            : 220.0;

    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.card,
          elevation: 0,
          centerTitle: false,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  'COLLECTIONS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: titleSize,
                    height: 1,
                    fontFamily: AppFonts.heading,
                    fontStyle: FontStyle.italic,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<ShopifyCollection>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorState(onRetry: _refresh);
                }
                final collections = snapshot.data ?? [];
                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (collections.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: Text('No collections found')),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: maxTileExtent,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.78,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) =>
                                _CategoryTile(category: collections[index]),
                            childCount: collections.length,
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});
  final ShopifyCollection category;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth;
        final labelSize = (tileWidth * 0.09).clamp(14.0, 22.0);
        final gradientHeight = (tileWidth * 0.42).clamp(56.0, 90.0);
        final inset = (tileWidth * 0.08).clamp(10.0, 18.0);

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductsPage(collection: category),
              ),
            );
          },
          child: ClipRRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: const Color(0xFFD9D9D9),
                  child: category.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: category.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        )
                      : null,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: gradientHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.45),
                          Colors.black.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: inset,
                  right: inset,
                  bottom: inset,
                  child: Text(
                    category.label.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: labelSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: AppColors.secondaryText),
            const SizedBox(height: 12),
            const Text(
              'Something went wrong loading categories.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
