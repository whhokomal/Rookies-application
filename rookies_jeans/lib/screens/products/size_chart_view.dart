import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Displays a Kiwi size chart in a WebView.
///
/// The [controller] is created and navigated by the caller (see
/// `_prewarmSizeChart` in ProductDetailPage) as soon as the product loads,
/// so that by the time this sheet opens the page has often already finished
/// loading in the background — avoiding a cold WebView + network round trip
/// in the tap-to-open critical path.
class SizeChartView extends StatelessWidget {
  final WebViewController controller;
  final ValueListenable<bool> loading;

  const SizeChartView({
    super.key,
    required this.controller,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    // Fixed-height sheet rather than a DraggableScrollableSheet: the sheet's
    // own drag handling used to win every vertical swipe, so the chart page
    // inside the WebView could never scroll. The eager recognizer hands all
    // gestures on the page to the WebView.
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(
                  controller: controller,
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: loading,
                  builder: (context, isLoading, _) => isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
