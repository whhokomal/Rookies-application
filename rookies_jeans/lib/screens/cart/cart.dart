import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/models/cart_model.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/screens/cart/checkout_flow.dart';
import 'package:rookies_jeans/screens/products/product_detail_page.dart';
import 'package:rookies_jeans/services/cart_service.dart';
import 'package:rookies_jeans/services/product_pairings.dart';
import 'package:rookies_jeans/services/recently_viewed_service.dart';
import 'package:rookies_jeans/services/shopify_storefront_service.dart';
import 'package:rookies_jeans/widgets/price_text.dart';
import 'package:rookies_jeans/widgets/product_row_section.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  double _s(double base) =>
      Responsive.of(context, baseW: 400, maxScale: 1.3).s(base);

  static const double _maxContentWidth = AppLayout.maxContentMedium;

  /// 48px back button + 8px vertical padding on each side.
  static const double _topBarHeight = 64;

  Widget _centered(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxContentWidth),
      child: child,
    ),
  );

  final Set<String> _pendingLineIds = {};
  bool _isCheckingOut = false;

  // Kept across visits so reopening the cart shows the same suggestions
  // instead of fetching and reshuffling them again.
  static String? _cachedFor;
  static List<ShopifyProduct> _cachedGoesWellWith = [];
  static List<ShopifyProduct> _cachedYouMayAlsoLike = [];

  List<ShopifyProduct> _goesWellWith = _cachedGoesWellWith;
  List<ShopifyProduct> _youMayAlsoLike = _cachedYouMayAlsoLike;
  bool _loadingSuggestions = false;

  /// Handle the current suggestions were picked for; they're reloaded only
  /// when the product they're based on changes.
  String? _suggestionsFor = _cachedFor;

  @override
  void initState() {
    super.initState();
    CartService.instance.addListener(_loadSuggestionsIfNeeded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CartService.instance.refresh();
      _loadSuggestionsIfNeeded();
    });
  }

  @override
  void dispose() {
    CartService.instance.removeListener(_loadSuggestionsIfNeeded);
    super.dispose();
  }

  /// Suggestions follow the first cart item, or the last viewed product
  /// when the cart is empty.
  Future<void> _loadSuggestionsIfNeeded() async {
    // The saved recently-viewed list may still be loading after app start.
    await RecentlyViewedService.instance.initialize();
    if (!mounted) return;
    String handle = '';
    String title = '';
    final lines = CartService.instance.cart.lines;
    final seedLine = lines.where((l) => l.productHandle != null).firstOrNull;
    if (seedLine != null) {
      handle = seedLine.productHandle!;
      title = seedLine.productTitle;
    } else if (RecentlyViewedService.instance.items.isNotEmpty) {
      final recent = RecentlyViewedService.instance.items.first;
      handle = recent.handle;
      title = recent.title;
    }
    if (handle == _suggestionsFor) return;
    _suggestionsFor = handle;

    final category = ProductPairings.detectCategory(handle, title);
    final pairings = ProductPairings.goesWellWithCollections(category);
    setState(() => _loadingSuggestions = true);
    try {
      final results = await Future.wait([
        pairings.isNotEmpty
            ? ShopifyStorefrontService.instance.getProductsByCollection(
                pairings.first,
                first: 8,
              )
            : Future.value(<ShopifyProduct>[]),
        ShopifyStorefrontService.instance.getProductsByCollection(
          ProductPairings.sameCollectionHandle(category, handle),
          first: 10,
        ),
      ]);
      if (!mounted || _suggestionsFor != handle) return;
      _cachedFor = handle;
      _cachedGoesWellWith = results[0].take(6).toList();
      _cachedYouMayAlsoLike = (results[1].toList()..shuffle()).take(8).toList();
      setState(() {
        _goesWellWith = _cachedGoesWellWith;
        _youMayAlsoLike = _cachedYouMayAlsoLike;
      });
    } catch (e) {
      debugPrint('Cart suggestions fetch error: $e');
    } finally {
      if (mounted && _suggestionsFor == handle) {
        setState(() => _loadingSuggestions = false);
      }
    }
  }

  void _showToast(String message, {bool isError = false}) =>
      AppToast.show(context, message, isError: isError);

  Future<void> _changeQuantity(ShopifyCartLine line, int newQuantity) async {
    setState(() => _pendingLineIds.add(line.lineId));
    final ok = await CartService.instance.updateLineQuantity(
      lineId: line.lineId,
      quantity: newQuantity,
    );
    if (!mounted) return;
    setState(() => _pendingLineIds.remove(line.lineId));
    if (!ok) {
      _showToast(CartService.instance.lastError ?? 'Could not update quantity. Try again.', isError: true);
    }
  }

  Future<void> _removeLine(ShopifyCartLine line) async {
    setState(() => _pendingLineIds.add(line.lineId));
    final ok = await CartService.instance.removeLine(lineId: line.lineId);
    if (!mounted) return;
    setState(() => _pendingLineIds.remove(line.lineId));
    if (ok) {
      _showToast('${line.productTitle} removed from cart');
    } else {
      _showToast('Could not remove item. Try again.', isError: true);
    }
  }

  Future<void> _checkout() async {
    if (_isCheckingOut) return;
    setState(() => _isCheckingOut = true);

    try {
      final lines = CartService.instance.cart.lines;
      if (lines.isEmpty) {
        _showToast('Your cart is empty.', isError: true);
        return;
      }

      final placed = await runCheckoutFlow(context, lines: lines);
      if (!mounted) return;

      if (placed) {
        // GoKwik places the order from the website's cart, so the app's
        // Storefront cart is never converted; start a fresh one.
        await CartService.instance.reset();
        if (!mounted) return;
        _showToast('Order placed successfully!');
      }
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: AnimatedBuilder(
            animation: CartService.instance,
            builder: (context, _) {
              final cart = CartService.instance.cart;
              final isLoading = CartService.instance.isLoading;

              return Column(
                children: [
                  _topBar(cart),
                  // Cart items get the top half (a quarter when empty, so the
                  // suggestions get more room); each part scrolls on its own.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // With items, the cart reaches the middle of the
                        // whole screen (not just the space left between the
                        // top bar and the checkout bar).
                        final mq = MediaQuery.of(context);
                        final topHeight = cart.lines.isEmpty
                            ? constraints.maxHeight * 0.25
                            : (mq.size.height / 2 -
                                      mq.padding.top -
                                      _topBarHeight)
                                  .clamp(
                                    constraints.maxHeight * 0.4,
                                    constraints.maxHeight * 0.75,
                                  );
                        return Column(
                          children: [
                            SizedBox(
                              height: topHeight,
                              child: RefreshIndicator(
                                color: AppColors.primary,
                                onRefresh: () => CartService.instance.refresh(),
                                child: isLoading && cart.lines.isEmpty
                                    ? _loadingState()
                                    : cart.lines.isEmpty
                                    ? _emptyState()
                                    : _cartGrid(cart, topHeight),
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: AppColors.border,
                            ),
                            // Fixed gap so scrolled suggestions never run
                            // right up against the divider.
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _suggestions(cart),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (cart.lines.isNotEmpty) _checkoutBar(cart),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _topBar(ShopifyCart cart) {
    final titleSize = (MediaQuery.of(context).size.width * 0.09).clamp(
      22.0,
      40.0,
    );
    return Container(
      color: AppColors.card,
      height: _topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: _centered(
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              color: AppColors.primary,
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
                cart.totalQuantity > 0
                    ? 'MY CART (${cart.totalQuantity})'
                    : 'MY CART',
                style: TextStyle(
                  fontSize: titleSize,
                  height: 1,
                  fontFamily: AppFonts.heading,
                  fontStyle: FontStyle.italic,
                  color: AppColors.primary,
                  // letterSpacing: 1.8,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _loadingState() =>
      Center(child: CircularProgressIndicator(color: AppColors.primary));

  Widget _emptyState() => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shopping_bag_outlined,
                  size: _s(40),
                  color: AppColors.hint,
                ),
                SizedBox(height: _s(8)),
                Text(
                  'No items in your cart',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: _s(20),
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(height: _s(6)),
                Text(
                  'Items you add will show up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: _s(12),
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  double _maxTileExtent(double width) {
    if (width >= 1024) return 200;
    if (width >= 600) return 180;
    return 160;
  }

  /// Grid of cart cards, styled like the Goes Well With cards: product
  /// photo with the details underneath. Cards fill their column; the photo
  /// box is shortened so a full row fits the top half with the next row
  /// peeking in below (hinting that the area scrolls); the photo fills
  /// the box, trimmed at the bottom if needed.
  Widget _cartGrid(ShopifyCart cart, double areaHeight) => _centered(
    LayoutBuilder(
      builder: (context, constraints) {
        const double pad = 12, gap = 10, runGap = 16, peek = 80;
        final double inner = constraints.maxWidth - pad * 2;
        final double maxExtent =
            _maxTileExtent(MediaQuery.of(context).size.width);
        final int columns =
            ((inner + gap) / (maxExtent + gap)).ceil().clamp(3, 6);
        final double slotWidth = (inner - gap * (columns - 1)) / columns;
        // Title, variant, price and the stepper row under the photo.
        final double infoHeight = 20 + _s(66);
        final double imageHeight =
            (areaHeight - pad - runGap - peek - infoHeight)
                .clamp(min(120.0, slotWidth * 1.5), slotWidth * 1.5);
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(pad),
          // Full width so a lone card sits on the left, not centred.
          child: SizedBox(
            width: inner,
            child: Wrap(
              spacing: gap,
              runSpacing: runGap,
              children: [
                for (final line in cart.lines)
                  SizedBox(
                    width: slotWidth,
                    child: _cartLineCard(line, imageHeight),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _cartLineCard(ShopifyCartLine line, double imageHeight) {
    final isPending = _pendingLineIds.contains(line.lineId);

    // Tapping anywhere on the card opens the product; the quantity stepper
    // and remove button have their own tap handlers, which win over this one.
    return GestureDetector(
      onTap: line.productHandle != null ? () => _openProduct(line) : null,
      behavior: HitTestBehavior.opaque,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              height: imageHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: line.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: line.imageUrl!,
                            // Fills the box; trims the bottom of the photo
                            // when the box is shorter, keeping the face.
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            placeholder: (_, _) => Container(color: AppColors.fieldFill),
                            errorWidget: (_, _, _) => Container(
                              color: AppColors.fieldFill,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 32,
                                color: AppColors.hint,
                              ),
                            ),
                          )
                        : Container(color: AppColors.fieldFill),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.productTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: _s(11),
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      height: 1.3,
                    ),
                  ),
                  if (line.variantTitle != null &&
                      line.variantTitle != 'Default Title') ...[
                    const SizedBox(height: 2),
                    Text(
                      line.variantTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.body,
                        fontSize: _s(9),
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: PriceText(
                          line.currencyCode == 'INR'
                              ? line.price.toStringAsFixed(0)
                              : '${line.currencyCode} ${line.price.toStringAsFixed(2)}',
                          currencyCode: line.currencyCode,
                          fontSize: _s(12),
                          fontWeight: FontWeight.w800,
                          amountFontFamily: AppFonts.body,
                          color: AppColors.primary,
                        ),
                      ),
                      if (!line.availableForSale) ...[
                        const SizedBox(width: 6),
                        Text(
                          'Out of stock',
                          style: TextStyle(
                            fontFamily: AppFonts.bold,
                            fontSize: _s(9),
                            fontWeight: FontWeight.w700,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _qtyStepper(line, isPending),
                      const Spacer(),
                      isPending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : GestureDetector(
                              onTap: () => _removeLine(line),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                size: _s(17),
                                color: AppColors.secondaryText,
                              ),
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }

  /// Bottom half: Goes Well With, You May Also Like, Recently Viewed.
  Widget _suggestions(ShopifyCart cart) {
    final inCart = {
      for (final line in cart.lines)
        if (line.productHandle != null) line.productHandle!,
    };
    List<ShopifyProduct> notInCart(List<ShopifyProduct> items) =>
        items.where((p) => !inCart.contains(p.handle)).toList();

    return ListenableBuilder(
      listenable: RecentlyViewedService.instance,
      builder: (context, _) {
        final goesWell = notInCart(_goesWellWith);
        final mayLike = notInCart(_youMayAlsoLike);
        final recent = notInCart(RecentlyViewedService.instance.items);

        final sections = <Widget>[
          if (goesWell.isNotEmpty)
            ProductRowSection(
              key: const ValueKey('GOES WELL WITH'),
              title: 'GOES WELL WITH',
              products: goesWell,
            ),
          if (mayLike.isNotEmpty)
            ProductRowSection(
              key: const ValueKey('YOU MAY ALSO LIKE'),
              title: 'YOU MAY ALSO LIKE',
              products: mayLike,
            ),
          if (recent.isNotEmpty)
            ProductRowSection(
              key: const ValueKey('RECENTLY VIEWED'),
              title: 'RECENTLY VIEWED',
              products: recent,
            ),
        ];

        // Wait for the first load instead of showing Recently Viewed alone
        // and then pushing it down when the other rows arrive.
        if (_loadingSuggestions &&
            _goesWellWith.isEmpty &&
            _youMayAlsoLike.isEmpty) {
          return _loadingState();
        }
        if (sections.isEmpty) {
          return _loadingSuggestions
              ? _loadingState()
              : const SizedBox.shrink();
        }

        return _centered(
          ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: sections,
          ),
        );
      },
    );
  }

  void _openProduct(ShopifyCartLine line) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(
          handle: line.productHandle!,
          title: line.productTitle,
          heroImageUrl: line.imageUrl,
        ),
      ),
    );
  }

  Widget _qtyStepper(ShopifyCartLine line, bool isPending) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      // borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepperButton(
          icon: Icons.remove_rounded,
          onTap: isPending
              ? null
              : () => _changeQuantity(line, line.quantity - 1),
        ),
        SizedBox(
          width: _s(22),
          child: Text(
            '${line.quantity}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.bold,
              fontSize: _s(11),
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        _stepperButton(
          icon: Icons.add_rounded,
          onTap: isPending
              ? null
              : () => _changeQuantity(line, line.quantity + 1),
        ),
      ],
    ),
  );

  Widget _stepperButton({required IconData icon, VoidCallback? onTap}) =>
      InkWell(
        onTap: onTap,
        child: SizedBox(
          width: _s(22).clamp(22.0, 32.0),
          height: _s(22).clamp(22.0, 32.0),
          child: Icon(icon, size: _s(12), color: AppColors.primary),
        ),
      );

  Widget _checkoutBar(ShopifyCart cart) => Container(
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: SafeArea(
      top: false,
      child: _centered(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SUBTOTAL',
                      style: TextStyle(
                        fontFamily: AppFonts.bold,
                        fontSize: _s(10),
                        fontWeight: FontWeight.w700,
                        color: AppColors.secondaryText,
                        // letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        cart.formattedSubtotal,
                        style: TextStyle(
                          fontFamily: AppFonts.bold,
                          fontSize: _s(17),
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: (cart.checkoutUrl == null || _isCheckingOut)
                    ? null
                    : _checkout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  shape: AppShapes.button,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(
                    horizontal: _s(28).clamp(20.0, 40.0),
                    vertical: _s(16).clamp(14.0, 20.0),
                  ),
                ),
                child: _isCheckingOut
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : Text(
                        'CHECKOUT',
                        style: TextStyle(
                          fontFamily: AppFonts.bold,
                          fontSize: _s(13),
                          fontWeight: FontWeight.w800,
                          color: AppColors.onPrimary,
                          // letterSpacing: 1.5,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
