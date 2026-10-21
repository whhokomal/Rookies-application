import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/constants/app_ui.dart';

double _s(BuildContext c, double base) =>
    Responsive.of(c, baseW: 375).s(base);

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({
    super.key,
    required this.title,
    required this.url,
  });

  final String title;
  final String url;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError  = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() {
            _isLoading = true;
            _hasError  = false;
          }),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (_) => setState(() {
            _isLoading = false;
            _hasError  = true;
          }),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0.5,
        shadowColor: AppColors.border,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: _s(context, 18).clamp(16.0, 26.0),
              color: AppColors.primary),
          onPressed: () => context.pop(),
        ),
        leadingWidth: 44,
        titleSpacing: 0,
        title: Text(
          widget.title.toUpperCase(),
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
      body: Stack(
        children: [
          if (_hasError)
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(_s(context, 24)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded,
                        size: _s(context, 48).clamp(40.0, 66.0),
                        color: AppColors.secondaryText),
                    SizedBox(height: _s(context, 12)),
                    Text(
                      'Failed to load page',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: ShopifyConstants.fontBody,
                        fontSize: _s(context, 14).clamp(13.0, 18.0),
                        color: AppColors.secondaryText,
                      ),
                    ),
                    SizedBox(height: _s(context, 16)),
                    ElevatedButton(
                      onPressed: () => _controller.reload(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        elevation: 0,
                        shape: AppShapes.button,
                      ),
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          fontFamily: ShopifyConstants.fontBody,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            WebViewWidget(controller: _controller),
          if (_isLoading && !_hasError)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: AppColors.primary,
            ),
        ],
      ),
    );
  }
}
