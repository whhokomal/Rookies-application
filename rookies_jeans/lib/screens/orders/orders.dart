import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/screens/products/product_detail_page.dart';
import 'package:rookies_jeans/widgets/web_view_screen.dart';
import 'package:rookies_jeans/services/order_service.dart';

class _R {
  _R(BuildContext context)
      : _r = Responsive.of(context, baseW: 400, maxScale: 1.3);
  final Responsive _r;

  double s(double base) => _r.s(base);

  static const double maxContentWidth = 720;

  // Top-aligned (not Center) so short pages don't float mid-screen with a
  // big gap above them.
  Widget center(Widget child) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: child,
        ),
      );
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _svc = ShopifyOrderService.instance;

  List<Map<String, dynamic>> _orders = [];
  bool    _isLoading    = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final orders = await _svc.fetchOrders();
      setState(() { _orders = orders; _isLoading = false; });
    } on ShopifyOrderException catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.userMessage; });
    } catch (_) {
      setState(() { _isLoading = false; _errorMessage = 'Something went wrong. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _R(context);
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0.5,
        shadowColor: AppColors.border,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.primary),
          // maybePop goes through the route's PopScope, so when this is the
          // only page (iOS has no system back) it falls back to Home.
          onPressed: () => Navigator.maybePop(context),
        ),
        leadingWidth: 44,
        titleSpacing: 0,
        title: Text(
          'ORDER HISTORY',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: ShopifyConstants.fontHeading,
            fontSize: (MediaQuery.of(context).size.width * 0.09)
                .clamp(20.0, 40.0),
            fontStyle: FontStyle.italic,
            height: 1,
            color: AppColors.primary,
          ),
        ),
        centerTitle: false,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
          : _errorMessage != null
              ? _ErrorState(message: _errorMessage!, onRetry: _load)
              : _orders.isEmpty
                  ? const _EmptyState()
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _load,
                      child: r.center(
                        ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _orders.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, i) => _OrderTile(
                            order: _orders[i],
                            svc: _svc,
                            onTap: () async {
                              final changed = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => OrderDetailScreen(order: _orders[i]),
                                ),
                              );
                              // e.g. the order was cancelled on the detail screen.
                              if (changed == true && mounted) _load();
                            },
                          ),
                        ),
                      ),
                    ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.svc, required this.onTap});

  final Map<String, dynamic> order;
  final ShopifyOrderService  svc;
  final VoidCallback         onTap;

  @override
  Widget build(BuildContext context) {
    final r = _R(context);
    final lineItems  = (order['lineItems']?['edges'] as List?) ?? [];
    final firstItem  = lineItems.isNotEmpty ? lineItems.first['node'] : null;
    final imageUrl   = firstItem?['variant']?['image']?['url'] as String?;
    final itemCount  = lineItems.fold<int>(0, (s, e) => s + ((e['node']['quantity'] as int?) ?? 1));
    final totalPrice = order['currentTotalPrice'] ?? {'amount': '0', 'currencyCode': 'INR'};
    final state      = svc.resolveOrderState(order);
    final isCod      = svc.isCod(order);

    final imgW = r.s(100).clamp(84.0, 140.0);
    final imgH = r.s(120).clamp(100.0, 168.0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              // borderRadius: BorderRadius.circular(8),
              child: imageUrl != null
                  ? CachedNetworkImage(imageUrl: imageUrl, width: imgW, height: imgH, fit: BoxFit.fill,
                      errorWidget: (_, _, _) => _imgPlaceholder(imgW))
                  : _imgPlaceholder(imgW),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #${order['orderNumber']}',
                    style: TextStyle(
                      fontFamily: ShopifyConstants.fontBodyBold,
                      fontSize: r.s(14),
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    svc.formatDate(order['processedAt'] ?? ''),
                    style: TextStyle(
                      fontFamily: ShopifyConstants.fontBody,
                      fontSize: r.s(12),
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$itemCount item${itemCount != 1 ? 's' : ''}  •  ${svc.formatPrice(totalPrice)}',
                    style: TextStyle(
                      fontFamily: ShopifyConstants.fontBody,
                      fontSize: r.s(13),
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _OrderStateBadge(state: state, isCod: isCod),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.hint, size: 20),
          ],
        ),
      ),
    );
  }
}

Widget _imgPlaceholder(double size) => Container(
  width: size, height: size,
  color: AppColors.fieldFill,
  child: Icon(Icons.image_outlined, size: 24, color: AppColors.hint),
);

class _OrderStateBadge extends StatelessWidget {
  const _OrderStateBadge({required this.state, required this.isCod});

  final OrderState state;
  final bool       isCod;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case OrderState.cancelled:
        return const _Badge(label: 'Cancelled', color: Color(0xFFD32F2F));
      case OrderState.delivered:
        return const _Badge(label: 'Delivered', color: Color(0xFF2E7D32));
      case OrderState.active:
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            const _Badge(label: 'Processing', color: Color(0xFFE65100)),
            _Badge(
              label: isCod ? 'Cash on Delivery' : 'Paid',
              color: isCod ? const Color(0xFF1565C0) : const Color(0xFF2E7D32),
            ),
          ],
        );
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    final r = _R(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: ShopifyConstants.fontBody,
          fontSize: r.s(11),
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String       message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AppColors.hint),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: ShopifyConstants.fontBody,
                fontSize: 14,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
              ),
              child: const Text('Retry', style: TextStyle(fontFamily: ShopifyConstants.fontBodyBold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.hint),
          const SizedBox(height: 12),
          Text(
            'No orders yet',
            style: TextStyle(fontFamily: ShopifyConstants.fontSubheading, fontSize: 16, color: AppColors.secondaryText),
          ),
          const SizedBox(height: 6),
          Text(
            'Your order history will appear here.',
            style: TextStyle(fontFamily: ShopifyConstants.fontBody, fontSize: 13, color: AppColors.hint),
          ),
        ],
      ),
    );
  }
}

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.order});
  final Map<String, dynamic> order;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _svc = ShopifyOrderService.instance;

  late Map<String, dynamic> _order = widget.order;

  /// Whether the order changed here (e.g. cancelled), so the list reloads.
  bool _changed = false;

  Future<void> _openCancelSheet() async {
    final cancelled = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(),
      builder: (_) => _CancelOrderSheet(order: _order, svc: _svc),
    );
    if (cancelled != true || !mounted) return;

    // Show it as cancelled straight away; Shopify processes the
    // cancellation in the background, so refresh once it's reflected.
    setState(() {
      _changed = true;
      _order = {..._order, 'canceledAt': DateTime.now().toIso8601String()};
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
        shape: const RoundedRectangleBorder(),
        content: Text(
          'Order #${_order['orderNumber']} has been cancelled.',
          style: TextStyle(fontFamily: ShopifyConstants.fontBody, color: AppColors.onPrimary),
        ),
      ),
    );

    final updated = await _svc.waitForCancellation(_order['id'] as String);
    if (updated != null && mounted) setState(() => _order = updated);
  }

  void _openTrackOrder() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WebViewScreen(title: 'Track Your Order', url: _svc.orderTrackUrl()),
    ));
  }

  /// 0 = placed, 1 = shipped, 2 = delivered.
  int _progressStep(Map<String, dynamic> order) {
    final f = (order['fulfillmentStatus'] ?? '').toString().toUpperCase();
    if (f == 'FULFILLED') return 2;
    if (f == 'PARTIALLY_FULFILLED' || f == 'IN_PROGRESS') return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final r          = _R(context);
    final order      = _order;
    final lineItems  = (order['lineItems']?['edges'] as List?) ?? [];
    final itemCount  = lineItems.fold<int>(0, (s, e) => s + ((e['node']['quantity'] as int?) ?? 1));
    final totalPrice = (order['currentTotalPrice'] as Map<String, dynamic>?) ??
        {'amount': '0', 'currencyCode': 'INR'};
    final state      = _svc.resolveOrderState(order);
    final isCod      = _svc.isCod(order);
    final canCancel  = _svc.canCancelOrder(order);
    final step       = _progressStep(order);
    final address    = order['shippingAddress'] as Map<String, dynamic>?;

    final (statusLabel, statusColor) = switch (state) {
      OrderState.cancelled => ('Cancelled', AppColors.danger),
      OrderState.delivered => ('Delivered', AppColors.success),
      OrderState.active    => (step == 1 ? 'Shipped' : 'Confirmed', const Color(0xFFE65100)),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.primary),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
          leadingWidth: 44,
          titleSpacing: 0,
          title: Text(
            'ORDER DETAILS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: ShopifyConstants.fontHeading,
              fontSize: (MediaQuery.of(context).size.width * 0.09)
                  .clamp(20.0, 40.0),
              fontStyle: FontStyle.italic,
              height: 1,
              color: AppColors.primary,
            ),
          ),
          centerTitle: false,
        ),
        body: r.center(
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              // ── Summary ────────────────────────────────────────────
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusPill(label: statusLabel, color: statusColor),
                    const SizedBox(height: 12),
                    Text(
                      'Order #${order['orderNumber']}',
                      style: TextStyle(
                        fontFamily: ShopifyConstants.fontHeading,
                        fontSize: r.s(30),
                        height: 1,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Placed on ${_svc.formatDate(order['processedAt'] ?? '')}',
                      style: TextStyle(
                        fontFamily: ShopifyConstants.fontBody,
                        fontSize: r.s(12.5),
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Divider(height: 1, thickness: 1, color: AppColors.border),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _Stat(
                            label: 'ITEMS',
                            value: '$itemCount',
                          ),
                        ),
                        Expanded(
                          child: _Stat(
                            label: 'PAYMENT',
                            value: isCod
                                ? 'COD'
                                : _svc.formatStatus(order['financialStatus']?.toString() ?? '—'),
                          ),
                        ),
                        Expanded(
                          child: _Stat(
                            label: 'TOTAL',
                            value: _svc.formatPrice(totalPrice),
                            alignEnd: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Progress ───────────────────────────────────────────
              if (state != OrderState.cancelled) ...[
                const _SectionLabel('STATUS'),
                _Panel(child: _ProgressTracker(step: step)),
              ],

              // ── Items ──────────────────────────────────────────────
              _SectionLabel('ITEMS ($itemCount)'),
              _Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < lineItems.length; i++) ...[
                      if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.border),
                      _LineItemRow(item: lineItems[i]['node'] as Map<String, dynamic>, svc: _svc),
                    ],
                  ],
                ),
              ),

              // ── Payment summary ────────────────────────────────────
              const _SectionLabel('PAYMENT SUMMARY'),
              _Panel(child: _PaymentSummary(order: order, total: totalPrice, isCod: isCod, svc: _svc)),

              // ── Address ────────────────────────────────────────────
              if (address != null) ...[
                const _SectionLabel('DELIVERY ADDRESS'),
                _Panel(child: _AddressBlock(address: address)),
              ],
            ],
          ),
        ),
        bottomNavigationBar: state == OrderState.active
            ? Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: SafeArea(
                  top: false,
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: _R.maxContentWidth),
                      child: Row(
                        children: [
                          if (canCancel) ...[
                            Expanded(
                              child: _ActionButton(
                                label: 'CANCEL',
                                onTap: _openCancelSheet,
                                filled: false,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            flex: canCancel ? 2 : 1,
                            child: _ActionButton(
                              label: 'TRACK ORDER',
                              onTap: _openTrackOrder,
                              filled: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        padding: padding,
        child: child,
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final r = _R(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 24, 2, 10),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: ShopifyConstants.fontBodyBold,
          fontSize: r.s(11),
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: AppColors.secondaryText,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    final r = _R(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: ShopifyConstants.fontBodyBold,
              fontSize: r.s(10.5),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.alignEnd = false});
  final String label;
  final String value;
  final bool   alignEnd;

  @override
  Widget build(BuildContext context) {
    final r = _R(context);
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: ShopifyConstants.fontBody,
            fontSize: r.s(10.5),
            letterSpacing: 1.1,
            color: AppColors.hint,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: ShopifyConstants.fontBodyBold,
            fontSize: r.s(13.5),
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _ProgressTracker extends StatelessWidget {
  const _ProgressTracker({required this.step});
  final int step;

  static const _labels = ['Placed', 'Shipped', 'Delivered'];

  @override
  Widget build(BuildContext context) {
    final r = _R(context);
    final active   = AppColors.primary;
    final inactive = AppColors.border;

    Widget line(bool on) => Container(height: 2, color: on ? active : inactive);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_labels.length, (i) {
        final reached = i <= step;
        final current = i == step;
        return Expanded(
          child: Column(
            children: [
              SizedBox(
                height: 14,
                child: Row(
                  children: [
                    Expanded(child: i == 0 ? const SizedBox() : line(i <= step)),
                    Container(
                      width: current ? 14 : 10,
                      height: current ? 14 : 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: reached ? active : AppColors.card,
                        border: Border.all(
                          color: reached ? active : inactive,
                          width: 2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: i == _labels.length - 1 ? const SizedBox() : line(i + 1 <= step),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _labels[i],
                style: TextStyle(
                  fontFamily: reached ? ShopifyConstants.fontBodyBold : ShopifyConstants.fontBody,
                  fontSize: r.s(11.5),
                  fontWeight: reached ? FontWeight.w700 : FontWeight.w400,
                  color: reached ? AppColors.primary : AppColors.hint,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _LineItemRow extends StatelessWidget {
  const _LineItemRow({required this.item, required this.svc});
  final Map<String, dynamic> item;
  final ShopifyOrderService  svc;

  @override
  Widget build(BuildContext context) {
    final r        = _R(context);
    final variant  = item['variant'];
    final imageUrl = variant?['image']?['url'] as String?;
    final options  = ((variant?['selectedOptions'] as List?) ?? [])
        .map((o) => o['value']?.toString() ?? '')
        .where((v) => v.isNotEmpty && v != 'Default Title')
        .join(' / ');
    final qty      = (item['quantity'] as int?) ?? 1;
    final price    = variant?['price'] as Map<String, dynamic>?;
    final lineTotal = price == null
        ? null
        : svc.formatPrice({
            'amount': ((double.tryParse(price['amount']?.toString() ?? '') ?? 0) * qty).toString(),
            'currencyCode': price['currencyCode'],
          });

    final imgW = r.s(68).clamp(60.0, 92.0);
    final imgH = imgW * 1.25;

    // Null when the product has since been deleted — the row just isn't tappable.
    final handle = variant?['product']?['handle'] as String?;
    final onTap = handle == null || handle.isEmpty
        ? null
        : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ProductDetailPage(
                handle: handle,
                title: (variant?['product']?['title'] ?? item['title'] ?? '').toString(),
                heroImageUrl: imageUrl,
              ),
            ));

    return InkWell(
      onTap: onTap,
      child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          imageUrl != null
              ? CachedNetworkImage(imageUrl: imageUrl, width: imgW, height: imgH, fit: BoxFit.cover,
                  errorWidget: (_, _, _) => _imgPlaceholder(imgW))
              : _imgPlaceholder(imgW),
          const SizedBox(width: 14),
          Expanded(
            child: SizedBox(
              height: imgH,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: ShopifyConstants.fontBody,
                      fontSize: r.s(13),
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: AppColors.primary,
                    ),
                  ),
                  if (options.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      options,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: ShopifyConstants.fontBody,
                        fontSize: r.s(12),
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    children: [
                      Text(
                        'Qty $qty',
                        style: TextStyle(
                          fontFamily: ShopifyConstants.fontBody,
                          fontSize: r.s(12),
                          color: AppColors.secondaryText,
                        ),
                      ),
                      const Spacer(),
                      if (lineTotal != null)
                        Text(
                          lineTotal,
                          style: TextStyle(
                            fontFamily: ShopifyConstants.fontBody,
                            fontSize: r.s(13),
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Padding(
              padding: EdgeInsets.only(top: imgH / 2 - 10),
              child: Icon(Icons.chevron_right_rounded, color: AppColors.hint, size: 20),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

class _PaymentSummary extends StatelessWidget {
  const _PaymentSummary({
    required this.order,
    required this.total,
    required this.isCod,
    required this.svc,
  });

  final Map<String, dynamic> order;
  final Map<String, dynamic> total;
  final bool                 isCod;
  final ShopifyOrderService  svc;

  double _amount(dynamic money) =>
      double.tryParse((money as Map?)?['amount']?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final r        = _R(context);
    final subtotal = order['subtotalPrice'] as Map<String, dynamic>?;
    final shipping = order['totalShippingPrice'] as Map<String, dynamic>?;
    final tax      = order['totalTax'] as Map<String, dynamic>?;

    Widget row(String label, String value, {Color? valueColor}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: ShopifyConstants.fontBody,
                  fontSize: r.s(13),
                  color: AppColors.secondaryText,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontFamily: ShopifyConstants.fontBody,
                  fontSize: r.s(13),
                  color: valueColor ?? AppColors.primary,
                ),
              ),
            ],
          ),
        );

    return Column(
      children: [
        if (subtotal != null) row('Subtotal', svc.formatPrice(subtotal)),
        if (shipping != null)
          _amount(shipping) == 0
              ? row('Shipping', 'Free', valueColor: AppColors.success)
              : row('Shipping', svc.formatPrice(shipping)),
        if (tax != null && _amount(tax) > 0) row('Tax', svc.formatPrice(tax)),
        if (subtotal != null || shipping != null) ...[
          const SizedBox(height: 2),
          Divider(height: 1, thickness: 1, color: AppColors.border),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Text(
              'Total',
              style: TextStyle(
                fontFamily: ShopifyConstants.fontBodyBold,
                fontSize: r.s(14),
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const Spacer(),
            Text(
              svc.formatPrice(total),
              style: TextStyle(
                fontFamily: ShopifyConstants.fontBodyBold,
                fontSize: r.s(15),
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: AppColors.fieldFill,
          child: Row(
            children: [
              Icon(
                isCod ? Icons.payments_outlined : Icons.credit_card_rounded,
                size: 16,
                color: AppColors.secondaryText,
              ),
              const SizedBox(width: 8),
              Text(
                isCod
                    ? 'Cash on Delivery'
                    : 'Paid online · ${svc.formatStatus(order['financialStatus']?.toString() ?? '')}',
                style: TextStyle(
                  fontFamily: ShopifyConstants.fontBody,
                  fontSize: r.s(12),
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddressBlock extends StatelessWidget {
  const _AddressBlock({required this.address});
  final Map<String, dynamic> address;

  @override
  Widget build(BuildContext context) {
    final r = _R(context);
    String part(String key) => (address[key] ?? '').toString().trim();

    final lines = [
      part('address1'),
      part('address2'),
      [part('city'), part('province'), part('zip')].where((s) => s.isNotEmpty).join(', '),
      part('country'),
    ].where((s) => s.isNotEmpty).toList();
    final phone = part('phone');

    final body = TextStyle(
      fontFamily: ShopifyConstants.fontBody,
      fontSize: r.s(12.5),
      height: 1.55,
      color: AppColors.secondaryText,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (part('name').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              part('name'),
              style: TextStyle(
                fontFamily: ShopifyConstants.fontBodyBold,
                fontSize: r.s(13),
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        Text(lines.join('\n'), style: body),
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.phone_outlined, size: 14, color: AppColors.hint),
              const SizedBox(width: 6),
              Text(phone, style: body),
            ],
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    required this.filled,
    this.loading = false,
  });
  final String        label;
  final VoidCallback? onTap;
  final bool          filled;
  final bool          loading;

  @override
  Widget build(BuildContext context) {
    final r      = _R(context);
    final height = r.s(50).clamp(46.0, 60.0);
    final Widget child = loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: filled ? AppColors.onPrimary : AppColors.primary,
            ),
          )
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontFamily: ShopifyConstants.fontBodyBold,
                fontSize: r.s(13),
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          );
    const shape = AppShapes.button;

    return SizedBox(
      height: height,
      child: filled
          ? ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                disabledBackgroundColor:
                    loading ? AppColors.primary : AppColors.primary.withValues(alpha: 0.4),
                disabledForegroundColor: AppColors.onPrimary,
                elevation: 0,
                shape: shape,
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary, width: 1),
                shape: shape,
              ),
              child: child,
            ),
    );
  }
}

/// Bottom sheet that confirms and submits an order cancellation, mirroring
/// the website's cancel dialog (same reasons; the reason is sent as the comment).
/// Pops `true` once the cancellation has been accepted.
class _CancelOrderSheet extends StatefulWidget {
  const _CancelOrderSheet({required this.order, required this.svc});
  final Map<String, dynamic> order;
  final ShopifyOrderService  svc;

  @override
  State<_CancelOrderSheet> createState() => _CancelOrderSheetState();
}

class _CancelOrderSheetState extends State<_CancelOrderSheet> {
  String? _reason;
  bool    _submitting = false;
  String? _error;

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Please select a reason for cancelling.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await widget.svc.cancelOrder(widget.order, reason: reason);
    if (!mounted) return;

    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _submitting = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r     = _R(context);
    final order = widget.order;
    final total = (order['currentTotalPrice'] as Map<String, dynamic>?) ??
        {'amount': '0', 'currencyCode': 'INR'};
    final isCod = widget.svc.isCod(order);

    final labelStyle = TextStyle(
      fontFamily: ShopifyConstants.fontBodyBold,
      fontSize: r.s(11),
      fontWeight: FontWeight.w700,
      letterSpacing: 1.4,
      color: AppColors.secondaryText,
    );

    return PopScope(
      canPop: !_submitting,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(width: 36, height: 3, color: AppColors.border),
                ),
                const SizedBox(height: 18),
                Text(
                  'CANCEL ORDER',
                  style: TextStyle(
                    fontFamily: ShopifyConstants.fontHeading,
                    fontSize: r.s(26),
                    height: 1,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Order #${order['orderNumber']}  ·  ${widget.svc.formatPrice(total)}',
                  style: TextStyle(
                    fontFamily: ShopifyConstants.fontBody,
                    fontSize: r.s(12.5),
                    color: AppColors.secondaryText,
                  ),
                ),

                const SizedBox(height: 22),
                Text('REASON', style: labelStyle),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(border: Border.all(color: AppColors.border, width: 0.8)),
                  child: Column(
                    children: [
                      for (var i = 0; i < ShopifyOrderService.cancelReasons.length; i++) ...[
                        if (i > 0) Divider(height: 1, thickness: 0.8, color: AppColors.border),
                        _reasonRow(ShopifyOrderService.cancelReasons[i], r),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  color: AppColors.fieldFill,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: AppColors.secondaryText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isCod
                              ? 'No payment has been taken for this Cash on Delivery order.'
                              : 'A full refund will be issued to your original payment method.',
                          style: TextStyle(
                            fontFamily: ShopifyConstants.fontBody,
                            fontSize: r.s(12),
                            height: 1.45,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      fontFamily: ShopifyConstants.fontBody,
                      fontSize: r.s(12.5),
                      color: AppColors.danger,
                    ),
                  ),
                ],

                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: 'KEEP ORDER',
                        onTap: _submitting ? null : () => Navigator.of(context).pop(false),
                        filled: false,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        label: 'CANCEL ORDER',
                        onTap: _submitting ? null : _submit,
                        filled: true,
                        loading: _submitting,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reasonRow(String reason, _R r) {
    final selected = _reason == reason;
    return InkWell(
      onTap: _submitting
          ? null
          : () => setState(() {
                _reason = reason;
                _error = null;
              }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                reason,
                style: TextStyle(
                  fontFamily: selected ? ShopifyConstants.fontBodyBold : ShopifyConstants.fontBody,
                  fontSize: r.s(13),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: AppColors.primary,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.hint,
                  width: selected ? 5 : 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
