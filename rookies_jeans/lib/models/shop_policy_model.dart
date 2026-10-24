/// The store policies set in Shopify admin (Settings → Policies).
enum ShopPolicyType {
  // Same order as the website footer.
  terms('Terms & Conditions', 'termsOfService'),
  shipping('Shipping Policy', 'shippingPolicy'),
  refund('Return & Refund Policy', 'refundPolicy'),
  privacy('Data & Privacy', 'privacyPolicy');

  final String label;

  /// The policy's field on the Storefront API `Shop` object.
  final String shopField;

  const ShopPolicyType(this.label, this.shopField);
}

class ShopPolicy {
  final String title;

  /// HTML, as written in the Shopify policy editor.
  final String body;

  const ShopPolicy({required this.title, required this.body});

  factory ShopPolicy.fromJson(Map<String, dynamic> json) => ShopPolicy(
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
      );
}
