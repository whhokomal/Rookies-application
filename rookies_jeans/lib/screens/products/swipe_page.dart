import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/screens/products/product_peek_dialog.dart';
import 'package:rookies_jeans/services/shopify_storefront_service.dart';
import 'package:rookies_jeans/widgets/page_app_bar.dart';
import 'package:rookies_jeans/widgets/price_text.dart';
import 'package:rookies_jeans/widgets/product_size_row.dart';

/// Card deck of a collection's products. Swipe left to pass, right to open
/// the quick-add popup (pick a size, add to cart).
// shortcut: passes aren't saved, so a reopened deck shows them again; store
// them (e.g. shared_preferences) if that should stick.
class SwipePage extends StatefulWidget {
  const SwipePage({super.key, required this.collectionHandle});

  final String collectionHandle;

  @override
  State<SwipePage> createState() => _SwipePageState();
}

class _SwipePageState extends State<SwipePage>
    with SingleTickerProviderStateMixin {
  final List<ShopifyProduct> _deck = [];
  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _failed = false;

  Offset _drag = Offset.zero;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final service = ShopifyStorefrontService.instance;
      final res = await service.getProductsByCollectionPaginated(
        widget.collectionHandle,
        first: 20,
        after: _cursor,
        sortKey: service.homeGridSort.shopifyKey,
        reverse: service.homeGridSort.reverse,
      );
      if (!mounted) return;
      setState(() {
        // Copied first — the response list is shared with the service cache.
        _deck.addAll([...res.products.where((p) => p.primaryImageUrl != null)]
          ..shuffle());
        _cursor = res.endCursor;
        _hasMore = res.hasNextPage;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Swipe deck load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// Slides the top card from where it is to [target], then runs [then].
  void _animateTo(Offset target, {VoidCallback? then}) {
    final tween = Tween(begin: _drag, end: target)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    void tick() => setState(() => _drag = tween.value);
    tween.addListener(tick);
    _anim.forward(from: 0).whenComplete(() {
      tween.removeListener(tick);
      then?.call();
    });
  }

  void _swipe({required bool right}) {
    if (_deck.isEmpty || _anim.isAnimating) return;
    final width = MediaQuery.sizeOf(context).width;
    final product = _deck.first;
    _animateTo(Offset(right ? width * 1.5 : -width * 1.5, _drag.dy), then: () {
      if (!mounted) return;
      setState(() {
        _deck.removeAt(0);
        _drag = Offset.zero;
      });
      if (_deck.length < 5) _loadMore();
      if (right) showProductQuickAdd(context, product);
    });
  }

  void _onPanEnd(DragEndDetails d) {
    final width = MediaQuery.sizeOf(context).width;
    final vx = d.velocity.pixelsPerSecond.dx;
    if (_drag.dx.abs() > width * 0.3 || vx.abs() > 800) {
      _swipe(right: _drag.dx + vx * 0.1 > 0);
    } else {
      _animateTo(Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: pageAppBar(context, 'Swipe your style'),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    if (_deck.isEmpty) {
      if (_loading) {
        return Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        );
      }
      if (_failed) return PageLoadError(onRetry: _loadMore);
      return Center(
        child: Text(
          "YOU'VE SEEN EVERYTHING",
          style: TextStyle(
            fontFamily: AppFonts.subheading,
            fontSize: 24,
            color: AppColors.secondaryText,
          ),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final progress = (_drag.dx / (width * 0.3)).clamp(-1.0, 1.0);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Stack(
              children: [
                if (_deck.length > 1)
                  // Hidden at rest: it would peek through the gap between
                  // the top card's photo and details. Fades in while dragging.
                  Positioned.fill(
                    child: Opacity(
                      opacity: progress.abs(),
                      child: Transform.scale(
                        scale: 0.95 + 0.05 * progress.abs(),
                        child: _SwipeCard(product: _deck[1]),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: GestureDetector(
                    onPanUpdate: _anim.isAnimating
                        ? null
                        : (d) => setState(() => _drag += d.delta),
                    onPanEnd: _anim.isAnimating ? null : _onPanEnd,
                    child: Transform.translate(
                      offset: _drag,
                      child: Transform.rotate(
                        angle: _drag.dx / width * 0.35,
                        child: _SwipeCard(
                          key: ValueKey(_deck.first.id),
                          product: _deck.first,
                          likeProgress: progress,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 20, top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundButton(
                icon: Icons.close_rounded,
                color: Colors.redAccent,
                tooltip: 'Pass',
                onTap: () => _swipe(right: false),
              ),
              const SizedBox(width: 40),
              _RoundButton(
                icon: Icons.favorite_rounded,
                color: Colors.green,
                tooltip: 'Like and choose size',
                onTap: () => _swipe(right: true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SwipeCard extends StatefulWidget {
  const _SwipeCard({super.key, required this.product, this.likeProgress = 0});

  final ShopifyProduct product;

  /// -1 (full pass) … 0 … 1 (full like); shows the LIKE / NOPE stamp.
  final double likeProgress;

  @override
  State<_SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<_SwipeCard> {
  /// Height kept free under the photo for the gap and the details card.
  // shortcut: a fixed estimate of the details card's height; measure it if
  // the card ever grows (e.g. more lines of text).
  static const double _detailsReserve = 140;
  static const double _gap = 10;

  int _image = 0;

  ShopifyProduct get product => widget.product;
  double get likeProgress => widget.likeProgress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (product.imageUrls.length > 1) {
      precacheImage(CachedNetworkImageProvider(product.imageUrls[1]), context);
    }
  }

  /// Tap the right half for the next photo, the left half for the previous.
  void _onTap(TapUpDetails d, double width) {
    final count = product.imageUrls.length;
    final step = d.localPosition.dx > width / 2 ? 1 : -1;
    final next = _image + step;
    if (next < 0 || next >= count) return;
    setState(() => _image = next);
    // Warm the one after, so the following tap is instant.
    final ahead = next + step;
    if (ahead >= 0 && ahead < count) {
      precacheImage(
          CachedNetworkImageProvider(product.imageUrls[ahead]), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Widest 4:5 photo that still leaves room for the details card.
        final width = constraints.maxWidth
            .clamp(0.0, (constraints.maxHeight - _detailsReserve) * 4 / 5)
            .toDouble();
        return Center(
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          onTapUp: (d) => _onTap(d, width),
                          child: CachedNetworkImage(
                            imageUrl: product.imageUrls[_image],
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            fadeInDuration: Duration.zero,
                            placeholder: (_, _) =>
                                Container(color: AppColors.fieldFill),
                            errorWidget: (_, _, _) =>
                                Container(color: AppColors.fieldFill),
                          ),
                        ),
                        if (product.imageUrls.length > 1)
                          Positioned(
                            bottom: 10,
                            left: 8,
                            right: 8,
                            child: IgnorePointer(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (int i = 0;
                                      i < product.imageUrls.length;
                                      i++)
                                    Flexible(
                                      child: Container(
                                        width: 16,
                                        height: 2,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                              alpha: i == _image ? 1 : 0.4),
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (likeProgress > 0)
                          _Stamp(
                            label: 'LIKE',
                            color: Colors.green,
                            opacity: likeProgress,
                          ),
                        if (likeProgress < 0)
                          _Stamp(
                            label: 'NOPE',
                            color: Colors.redAccent,
                            opacity: -likeProgress,
                            alignRight: true,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: _gap),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: _info(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Name, then one line: struck MRP, selling price, % off … sizes.
  Widget _info() {
    final compareAt = product.compareAtPrice;
    final percentOff = product.isOnSale
        ? ((1 - product.price / compareAt!) * 100).round()
        : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            product.title.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.heading,
              fontSize: 20,
              height: 1.1,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (product.isOnSale) ...[
                PriceText(
                  product.formattedCompareAtPrice,
                  currencyCode: product.currencyCode,
                  fontSize: 14,
                  color: AppColors.secondaryText,
                  decoration: TextDecoration.lineThrough,
                ),
                const SizedBox(width: 8),
              ],
              PriceText(
                product.formattedPrice,
                currencyCode: product.currencyCode,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
              if (percentOff > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$percentOff% OFF',
                  style: const TextStyle(
                    fontFamily: AppFonts.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2E9E4F),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ProductSizeRow(product: product, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.label,
    required this.color,
    required this.opacity,
    this.alignRight = false,
  });

  final String label;
  final Color color;
  final double opacity;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 28,
      left: alignRight ? null : 24,
      right: alignRight ? 24 : null,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: alignRight ? 0.3 : -0.3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppFonts.heading,
                fontSize: 36,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.card,
        shape: CircleBorder(side: BorderSide(color: AppColors.border)),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Icon(icon, color: color, size: 32),
          ),
        ),
      ),
    );
  }
}
