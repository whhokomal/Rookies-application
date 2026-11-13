import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Loads web pages so that edits made on the website always show up in the
/// app, instead of an older copy kept in the WebView's cache.
///
/// * Every page request asks the server for the latest version
///   (`Cache-Control: no-cache`), so the HTML is re-checked on each open.
/// * On Android, the WebView disk cache (shared by all web views) is cleared
///   once per app launch, so stale scripts/styles/images from an earlier run
///   are dropped too. Cookies and local storage are kept — the shopper's
///   cart and GoKwik login are not affected.
///
/// iOS is not cleared: WKWebView's `clearCache` also wipes local storage,
/// which would log shoppers out of GoKwik. Shopify serves theme assets with
/// version query strings, so the no-cache page request is enough there.
class WebViewFresh {
  WebViewFresh._();

  static bool _clearedThisLaunch = false;

  static const Map<String, String> noCacheHeaders = {
    'Cache-Control': 'no-cache, no-store, must-revalidate',
    'Pragma': 'no-cache',
  };

  /// Loads [uri] in [controller], always fetching the newest page.
  static Future<void> load(WebViewController controller, Uri uri) async {
    if (!_clearedThisLaunch &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      _clearedThisLaunch = true;
      try {
        await controller.clearCache();
      } catch (e) {
        debugPrint('WebViewFresh: clearCache failed ($e)');
      }
    }
    await controller.loadRequest(uri, headers: noCacheHeaders);
  }
}
