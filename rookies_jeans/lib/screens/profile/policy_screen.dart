import 'package:flutter/material.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/models/shop_policy_model.dart';
import 'package:rookies_jeans/services/shopify_storefront_service.dart';
import 'package:rookies_jeans/widgets/html_content.dart';
import 'package:rookies_jeans/widgets/page_app_bar.dart';

double _s(BuildContext c, double base) =>
    Responsive.of(c, baseW: 375).s(base);

/// A store policy (Shopify admin → Settings → Policies), shown natively.
class PolicyScreen extends StatefulWidget {
  const PolicyScreen({super.key, required this.type});

  final ShopPolicyType type;

  @override
  State<PolicyScreen> createState() => _PolicyScreenState();
}

class _PolicyScreenState extends State<PolicyScreen> {
  late Future<ShopPolicy?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ShopPolicy?> _load() async =>
      (await ShopifyStorefrontService.instance.getShopPolicies())[widget.type];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: pageAppBar(context, widget.type.label),
      body: FutureBuilder<ShopPolicy?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            );
          }
          final policy = snap.data;
          if (policy == null || policy.body.trim().isEmpty) {
            return PageLoadError(
              onRetry: () => setState(() => _future = _load()),
            );
          }
          return SelectionArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                _s(context, 20),
                _s(context, 20),
                _s(context, 20),
                _s(context, 32) + MediaQuery.of(context).padding.bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppLayout.maxContentMedium,
                  ),
                  child: HtmlContent(html: policy.body),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
