import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/models/cart_model.dart';
import 'package:rookies_jeans/services/cart_service.dart';
import 'package:rookies_jeans/services/notification_service.dart';

/// GoKwik checkout screen.
///
/// Checkout runs through GoKwik (the "Gokwik X Rookies" Shopify app), which
/// is launched by a script in the storefront theme rather than from
/// Shopify's native `checkoutUrl`. So we load the storefront, copy the app's
/// cart into the web cart and launch GoKwik the same way the website's
/// Checkout button does. There is deliberately no fallback to Shopify's
/// native checkout: if GoKwik can't be started, we show an error with Retry.
///
/// With [openCart] it opens GoKwik's side cart instead (the website's cart
/// drawer), whose own Checkout button then starts GoKwik checkout. Edits
/// made there are copied back into the app cart when the cart is closed.
class CheckoutWebView extends StatefulWidget {
  const CheckoutWebView({
    super.key,
    required this.lines,
    this.openCart = false,
  });

  /// Cart lines to check out.
  final List<ShopifyCartLine> lines;

  /// Show GoKwik's side cart rather than going straight to checkout.
  final bool openCart;

  @override
  State<CheckoutWebView> createState() => _CheckoutWebViewState();
}

class _CheckoutWebViewState extends State<CheckoutWebView> {
  static const String _bridgeName = 'RookiesCheckout';
  /// The storefront is heavy and can take a while on slower phones, so each
  /// launch step gets its own time budget instead of one overall deadline.
  static const Duration _pageLoadTimeout = Duration(seconds: 45);
  static const Duration _stepTimeout     = Duration(seconds: 30);

  double _s(double base) =>
      Responsive.of(context, baseW: 400, maxScale: 1.3).s(base);

  late final WebViewController _controller;
  bool _isLoading      = true;
  bool _orderCompleted = false;

  /// True while the storefront is loading and GoKwik is being launched.
  bool _launchingGokwik = false;
  bool _gokwikInjected  = false;
  Timer? _gokwikTimer;

  /// Shown instead of the web view when GoKwik could not be started.
  String? _error;

  /// Bumped on every navigation, so a GoKwik "modal closed" event that is
  /// followed by a redirect (e.g. to the thank-you page) doesn't close us.
  int _navigationCount = 0;

  /// Cart mode: true while the side cart is showing (not GoKwik checkout).
  bool _cartOpen = false;
  bool _closingCart = false;

  /// Cart mode: product opened from the side cart, shown once it's closed.
  String? _openProductAfterClose;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(_bridgeName, onMessageReceived: _onBridgeMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _navigationCount++;
            // A redirect (e.g. Shopify's theme preview link) throws away a
            // script injected into the previous page, so inject it again.
            if (_launchingGokwik) _gokwikInjected = false;
            if (mounted) setState(() => _isLoading = true);
            _checkForOrderCompletion(url);
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _isLoading = false);
            _checkForOrderCompletion(url);
            _maybeLaunchGokwik(url);
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _checkForOrderCompletion(url);
          },
          onNavigationRequest: (request) => _handleNavigationRequest(request),
          onWebResourceError: (error) {
            debugPrint('CheckoutWebView error: ${error.description}');
            if (error.isForMainFrame == true && _launchingGokwik) {
              _fail('page load error: ${error.description}');
            }
          },
        ),
      );
    _startGokwik();
  }

  @override
  void dispose() {
    _gokwikTimer?.cancel();
    super.dispose();
  }

  /// Converts app cart lines to the storefront's `/cart/add.js` format.
  /// Storefront API variant IDs are GIDs; the web cart needs the numeric ID.
  List<Map<String, int>> _gokwikItems() {
    final items = <Map<String, int>>[];
    for (final line in widget.lines) {
      final id = int.tryParse(line.variantId.split('/').last.split('?').first);
      if (id == null || line.quantity <= 0) continue;
      items.add({'id': id, 'quantity': line.quantity});
    }
    return items;
  }

  void _startGokwik() {
    // An empty cart can still be opened; GoKwik shows its empty state.
    if (_gokwikItems().isEmpty && !widget.openCart) {
      _fail('no valid cart lines');
      return;
    }
    setState(() {
      _error           = null;
      _launchingGokwik = true;
      _gokwikInjected  = false;
    });
    _armTimer(_pageLoadTimeout, 'page load timeout');
    _controller.loadRequest(_startUrl());
  }

  /// The side cart opens on a light page of the GoKwik cart theme, as a
  /// preview (without Shopify's preview bar) until the theme is published.
  Uri _startUrl() {
    if (!widget.openCart) {
      return Uri.parse('${ShopifyConstants.storeUrl}/cart');
    }
    final themeId = ShopifyConstants.gokwikCartThemeId;
    return Uri.parse(
      '${ShopifyConstants.storeUrl}${ShopifyConstants.gokwikCartPage}',
    ).replace(
      queryParameters:
          themeId == null ? null : {'preview_theme_id': themeId, 'pb': '0'},
    );
  }

  void _armTimer(Duration timeout, String reason) {
    _gokwikTimer?.cancel();
    _gokwikTimer = Timer(timeout, () {
      if (_launchingGokwik) _fail(reason);
    });
  }

  void _maybeLaunchGokwik(String url) {
    if (!_launchingGokwik || _gokwikInjected) return;
    final host = Uri.tryParse(url)?.host;
    if (host != Uri.parse(ShopifyConstants.storeUrl).host) return;

    _gokwikInjected = true;
    _armTimer(_stepTimeout, 'GoKwik script timeout');
    final items = jsonEncode(_gokwikItems());
    final openCart = widget.openCart;
    _controller.runJavaScript('''
(function () {
  // Android can report the same page finished more than once.
  if (window.__rookiesGokwikInjected) return;
  window.__rookiesGokwikInjected = true;
  function post(m) { try { $_bridgeName.postMessage(m); } catch (e) {} }
  var items = $items;
  var openCart = $openCart;
  var tries = 0;
  function gokwikReady() {
    if (typeof window.triggerGokwikCustomCheckout !== 'function' || !window.gokwikSdk) return false;
    return !openCart || typeof window.openGokwikSideCart === 'function';
  }
  function waitForGokwik() {
    if (gokwikReady()) {
      start();
      return;
    }
    if (++tries > 100) { post('failed:gokwik-not-loaded'); return; }
    setTimeout(waitForGokwik, 250);
  }
  // Sends the website cart back as "cart:[{id, quantity}]" so the app cart
  // can be updated to match.
  function postCart() {
    fetch('/cart.js', { credentials: 'same-origin' })
      .then(function (r) { return r.json(); })
      .then(function (c) {
        post('cart:' + JSON.stringify(c.items.map(function (i) {
          return { id: i.variant_id, quantity: i.quantity };
        })));
      })
      .catch(function () { post('cart:null'); });
  }
  function openSideCart() {
    // The website's chat bubble would sit over the side cart's Checkout
    // button.
    var style = document.createElement('style');
    style.textContent = '#spur-live-chat { display: none !important; }';
    document.head.appendChild(style);
    var checkingOut = false;
    // The side cart's Checkout button calls initCheckout and then closes
    // the side cart; only a close without it means the customer left.
    var initCheckout = window.gokwikSdk.initCheckout;
    window.gokwikSdk.initCheckout = function () {
      checkingOut = true;
      post('checkout');
      return initCheckout.apply(this, arguments);
    };
    var closeSideCart = window.closeGokwikSideCart;
    window.closeGokwikSideCart = function () {
      var result = closeSideCart.apply(this, arguments);
      if (!checkingOut) postCart();
      return result;
    };
    window.__rookiesReopenCart = function () {
      checkingOut = false;
      window.openGokwikSideCart();
    };
    window.__rookiesCloseCart = function () {
      if (checkingOut) return;
      window.closeGokwikSideCart();
    };
    window.gokwikSdk.on('modal_closed', function () { post('closed'); });
    return Promise.resolve(window.openGokwikSideCart());
  }
  // Makes the website cart match the app cart in one request, or none if
  // it already does: emptying and refilling it takes about twice as long.
  // Cart attributes are copied onto the order, so Shopify can tell app
  // orders apart from website orders.
  function syncCart() {
    return fetch('/cart.js', { credentials: 'same-origin' })
      .then(function (r) {
        if (!r.ok) throw new Error('cart read ' + r.status);
        return r.json();
      })
      .then(function (cart) {
        var current = {};
        var updates = {};
        cart.items.forEach(function (i) {
          current[i.variant_id] = (current[i.variant_id] || 0) + i.quantity;
          updates[i.variant_id] = 0;
        });
        items.forEach(function (i) {
          updates[i.id] = (updates[i.id] || 0) + i.quantity;
        });
        var inSync = cart.attributes['Order Source'] === 'App' &&
          Object.keys(updates).every(function (id) {
            return (current[id] || 0) === updates[id];
          });
        if (inSync) return;
        return fetch('/cart/update.js', {
          method: 'POST',
          credentials: 'same-origin',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            updates: updates,
            attributes: { 'Order Source': 'App' }
          })
        })
          .then(function (r) {
            if (!r.ok) throw new Error('cart update ' + r.status);
            return r.json();
          })
          .then(function (updated) {
            // Sold-out items are dropped rather than refused.
            if (items.length && !updated.item_count) throw new Error('cart empty');
          });
      });
  }
  function start() {
    post('step:gokwik-ready');
    syncCart()
      .then(function () {
        post('step:cart-ready');
        if (openCart) {
          return openSideCart().then(function () { post('cart-opened'); });
        }
        window.gokwikSdk.on('modal_closed', function () { post('closed'); });
        window.triggerGokwikCustomCheckout();
        post('opened');
      })
      .catch(function (e) { post('failed:' + e); });
  }
  waitForGokwik();
})();
''');
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    final msg = message.message;
    if (!mounted) return;

    if (msg == 'opened' || msg == 'cart-opened') {
      // Also clears an earlier timeout error if GoKwik opened late.
      _gokwikTimer?.cancel();
      setState(() {
        _launchingGokwik = false;
        _error = null;
        _cartOpen = msg == 'cart-opened';
      });
    } else if (msg.startsWith('step:')) {
      debugPrint('CheckoutWebView: $msg');
      if (_launchingGokwik) _armTimer(_stepTimeout, 'timeout after $msg');
    } else if (msg == 'checkout') {
      // Checkout started from the side cart.
      _cartOpen = false;
      NotificationService.instance.track('checkout_started');
    } else if (msg.startsWith('cart:')) {
      _onSideCartClosed(msg.substring('cart:'.length));
    } else if (msg == 'closed') {
      // Closing the GoKwik sheet without paying returns to the cart. Wait a
      // moment first: after a successful order GoKwik closes the sheet and
      // then redirects, which we must not interrupt.
      final navBefore = _navigationCount;
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted || _orderCompleted) return;
        if (_navigationCount != navBefore) return;
        if (widget.openCart) {
          _cartOpen = true;
          _controller.runJavaScript('window.__rookiesReopenCart();');
        } else {
          Navigator.of(context).pop(false);
        }
      });
    } else if (msg.startsWith('failed')) {
      _fail(msg);
    }
  }

  /// The side cart was closed: copy its contents ([cartJson], from
  /// `/cart.js`, or "null" if it couldn't be read) into the app cart and
  /// leave, opening a product if one was tapped in the side cart.
  void _onSideCartClosed(String cartJson) {
    if (_orderCompleted) return;
    try {
      final items = jsonDecode(cartJson);
      if (items is List) {
        final lines = <int, int>{};
        for (final item in items.cast<Map<String, dynamic>>()) {
          final id = item['id'] as int;
          lines[id] = (lines[id] ?? 0) + (item['quantity'] as int);
        }
        CartService.instance.syncFromWeb(lines);
      }
    } catch (e) {
      debugPrint('CheckoutWebView: could not read web cart ($e)');
    }
    _leaveCart();
  }

  void _leaveCart() {
    if (!mounted || !_cartOpen) return;
    _cartOpen = false;
    final router = GoRouter.of(context);
    final product = _openProductAfterClose;
    Navigator.of(context).pop(false);
    if (product != null) router.push('/products/$product');
  }

  /// Back button / app bar close in cart mode: closes the side cart the
  /// same way its X does, so edits are synced; leaves anyway if the page
  /// doesn't answer.
  void _closeCart() {
    if (!widget.openCart || !_cartOpen) {
      Navigator.of(context).pop(false);
      return;
    }
    if (_closingCart) return;
    _closingCart = true;
    _controller.runJavaScript('window.__rookiesCloseCart();');
    Future.delayed(const Duration(seconds: 3), _leaveCart);
  }

  void _fail(String reason) {
    debugPrint('CheckoutWebView: GoKwik could not start ($reason)');
    _gokwikTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _launchingGokwik = false;
      _error = 'Checkout is unavailable right now.\nPlease try again in a moment.';
    });
  }

  static bool _isStoreHost(String host) {
    final h = host.toLowerCase();
    final store = Uri.parse(ShopifyConstants.storeUrl).host;
    return h == store ||
        h == 'www.$store' ||
        h == ShopifyConstants.shopDomain ||
        h.endsWith('.shopify.com');
  }

  void _checkForOrderCompletion(String url) {
    if (_orderCompleted) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final path = uri.path.toLowerCase();
    final isThankYou = path.contains('thank_you') ||
        path.contains('thank-you') ||
        path.contains('thankyou') ||
        // Shopify's order status page (/<shop id>/orders/<token>) on the
        // store, where GoKwik lands after payment. Not the account's order
        // list (/account/orders), which a page can link to before paying.
        (_isStoreHost(uri.host) &&
            RegExp(r'^(/\d+)?/orders/[^/]+').hasMatch(path));
    if (isThankYou) {
      _orderCompleted = true;
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
  }

  /// Opens a payment-app link. Android payment pages often use
  /// `intent://pay?...#Intent;scheme=upi;package=...;end` links, which
  /// url_launcher can't open directly, so they are turned back into the
  /// app's own link (e.g. `upi://pay?...`); if that app isn't installed the
  /// intent's browser fallback URL is opened instead.
  Future<bool> _launchExternal(Uri uri, String rawUrl) async {
    try {
      return await _launchExternalOrThrow(uri, rawUrl);
    } catch (e) {
      debugPrint('CheckoutWebView: could not open $rawUrl ($e)');
      return false;
    }
  }

  Future<bool> _launchExternalOrThrow(Uri uri, String rawUrl) async {
    if (uri.scheme.toLowerCase() != 'intent') {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    final hashIndex = rawUrl.indexOf('#Intent;');
    if (hashIndex < 0) return false;
    final target = rawUrl.substring('intent://'.length, hashIndex);
    final params = <String, String>{};
    for (final part in rawUrl.substring(hashIndex + '#Intent;'.length).split(';')) {
      final eq = part.indexOf('=');
      if (eq > 0) params[part.substring(0, eq)] = part.substring(eq + 1);
    }

    final scheme = params['scheme'];
    if (scheme != null && scheme.isNotEmpty) {
      final appUri = Uri.tryParse('$scheme://$target');
      if (appUri != null &&
          await launchUrl(appUri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    }

    final fallback = params['S.browser_fallback_url'];
    if (fallback != null) {
      final fallbackUri = Uri.tryParse(Uri.decodeComponent(fallback));
      if (fallbackUri != null) {
        return launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    }
    return false;
  }

  Future<NavigationDecision> _handleNavigationRequest(
    NavigationRequest request,
  ) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;

    final scheme      = uri.scheme.toLowerCase();
    final isWebScheme = scheme == 'http' || scheme == 'https';
    // iOS (WKWebView) also reports iframe loads here, and GoKwik's payment
    // sheet creates about:blank / about:srcdoc / blob: frames. These must
    // load in the web view, not be handed to launchUrl as a "payment app".
    final isInternalScheme = scheme == 'about' ||
        scheme == 'data' ||
        scheme == 'blob' ||
        scheme == 'javascript';

    // A product tapped in the side cart opens the app's product page
    // rather than the website's.
    final productMatch = RegExp(r'^/products/([^/?#]+)').firstMatch(uri.path);
    if (widget.openCart &&
        _cartOpen &&
        request.isMainFrame &&
        _isStoreHost(uri.host) &&
        productMatch != null) {
      _openProductAfterClose = productMatch.group(1);
      _closeCart();
      return NavigationDecision.prevent;
    }

    if (isWebScheme || isInternalScheme) return NavigationDecision.navigate;

    final launched = await _launchExternal(uri, request.url);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Could not open payment app for this method.',
            style: TextStyle(
              fontFamily: AppFonts.body,
              color: AppColors.onPrimary,
            ),
          ),
        ),
      );
    }
    return NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.openCart) return _cartScaffold();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: AppColors.primary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        leadingWidth: 44,
        titleSpacing: 0,
        title: Text(
          'CHECKOUT',
          maxLines: 1,
          style: TextStyle(
            fontFamily: AppFonts.heading,
            fontSize: (MediaQuery.of(context).size.width * 0.09)
                .clamp(20.0, 40.0),
            fontStyle: FontStyle.italic,
            height: 1,
            color: AppColors.primary,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(Icons.close_rounded, color: AppColors.primary),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
      body: _webViewBody(),
    );
  }

  /// Cart mode has no app bar: the side cart brings its own header and X.
  /// Back closes the side cart so its edits reach the app cart.
  Widget _cartScaffold() => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _closeCart();
    },
    child: Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            _webViewBody(),
            // Way out while the cart is loading or failed to open.
            if (_error != null || _launchingGokwik)
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: Icon(Icons.close_rounded, color: AppColors.primary),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _webViewBody() => Stack(
    children: [
      WebViewWidget(controller: _controller),
      if (_error != null)
        Positioned.fill(child: _errorView(_error!))
      else if (_isLoading || _launchingGokwik)
        Positioned.fill(
          child: ColoredBox(
            color: AppColors.bg,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
        ),
    ],
  );

  Widget _errorView(String message) => ColoredBox(
        color: AppColors.bg,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(_s(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: _s(48), color: AppColors.hint),
                SizedBox(height: _s(12)),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: _s(13),
                    color: AppColors.secondaryText,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: _s(20)),
                ElevatedButton(
                  onPressed: _startGokwik,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    elevation: 0,
                    shape: AppShapes.button,
                    padding: EdgeInsets.symmetric(
                        horizontal: _s(28), vertical: _s(12)),
                  ),
                  child: Text(
                    'RETRY',
                    style: TextStyle(
                      fontFamily: AppFonts.bold,
                      fontSize: _s(13),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
