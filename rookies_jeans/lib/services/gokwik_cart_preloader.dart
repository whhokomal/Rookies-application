import 'dart:async';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/utils/webview_fresh.dart';

/// Callbacks of a cart web view. Fields can be swapped while it is loading,
/// so a page preloaded in the background can be handed to the cart screen.
class CartWebHooks {
  void Function(String url)? onPageStarted;
  void Function(String url)? onPageFinished;
  void Function(int progress)? onProgress;
  void Function(String url)? onUrlChange;
  void Function(WebResourceError error)? onWebResourceError;
  FutureOr<NavigationDecision> Function(NavigationRequest request)?
      onNavigationRequest;
  void Function(JavaScriptMessage message)? onMessage;
}

/// A cart page handed over by [GokwikCartPreloader.take].
class PreloadedCart {
  PreloadedCart(this.controller, this.hooks, this.finishedUrl);
  final WebViewController controller;
  final CartWebHooks hooks;

  /// Set when the page has already finished loading.
  final String? finishedUrl;
}

/// Loads GoKwik's side-cart page in a hidden web view after something is
/// added to the cart, so opening the cart doesn't wait for the website.
/// Each preloaded page is used once; [warm] again to get another.
class GokwikCartPreloader {
  GokwikCartPreloader._();
  static final GokwikCartPreloader instance = GokwikCartPreloader._();

  static const String bridgeName = 'RookiesCheckout';
  static const Duration _delay = Duration(seconds: 3);
  static const Duration _maxAge = Duration(minutes: 30);

  Timer? _timer;
  WebViewController? _controller;
  CartWebHooks? _hooks;
  DateTime? _loadedAt;
  String? _finishedUrl;
  bool _failed = false;

  /// The page GoKwik's side cart opens on: a light page of the GoKwik cart
  /// theme, as a preview (without Shopify's preview bar) until published.
  static Uri cartPageUri() {
    final themeId = ShopifyConstants.gokwikCartThemeId;
    return Uri.parse(
      '${ShopifyConstants.storeUrl}${ShopifyConstants.gokwikCartPage}',
    ).replace(
      queryParameters:
          themeId == null ? null : {'preview_theme_id': themeId, 'pb': '0'},
    );
  }

  /// Builds a web view whose callbacks go through [hooks]. The bridge channel
  /// is added up front: Android only picks one up on the next page load.
  static WebViewController buildController(CartWebHooks hooks) {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        bridgeName,
        onMessageReceived: (m) => hooks.onMessage?.call(m),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => hooks.onPageStarted?.call(url),
          onPageFinished: (url) => hooks.onPageFinished?.call(url),
          onProgress: (p) => hooks.onProgress?.call(p),
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) hooks.onUrlChange?.call(url);
          },
          onWebResourceError: (e) => hooks.onWebResourceError?.call(e),
          onNavigationRequest: (request) =>
              hooks.onNavigationRequest?.call(request) ??
              NavigationDecision.navigate,
        ),
      );
  }

  /// Starts preloading a few seconds from now, unless a page is already
  /// loaded (and still fresh) or about to be.
  void warm() {
    if (_timer?.isActive == true) return;
    if (_controller != null && !_failed && !_isStale) return;
    _timer = Timer(_delay, _load);
  }

  bool get _isStale =>
      _loadedAt == null || DateTime.now().difference(_loadedAt!) > _maxAge;

  void _load() {
    final hooks = CartWebHooks()
      ..onPageStarted = (_) {
        _finishedUrl = null;
      }
      ..onPageFinished = (url) {
        _finishedUrl = url;
      }
      ..onWebResourceError = (e) {
        if (e.isForMainFrame == true) _failed = true;
      };
    _hooks = hooks;
    _controller = buildController(hooks);
    _loadedAt = DateTime.now();
    _finishedUrl = null;
    _failed = false;
    WebViewFresh.load(_controller!, cartPageUri());
  }

  /// Hands over the preloaded page, or null if there is none usable. The
  /// caller must replace every field of the returned hooks.
  PreloadedCart? take() {
    _timer?.cancel();
    final controller = _controller;
    final hooks = _hooks;
    final usable = controller != null && hooks != null && !_failed && !_isStale;
    final result =
        usable ? PreloadedCart(controller, hooks, _finishedUrl) : null;
    _controller = null;
    _hooks = null;
    return result;
  }
}
