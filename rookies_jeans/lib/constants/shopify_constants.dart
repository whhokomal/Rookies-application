
class ShopifyConstants {
  ShopifyConstants._();

  static const String shopDomain = 'rookies-jeans.myshopify.com';
  static const String storefrontAccessToken = '8127f95aa12da6ed0234550d19abd043';
  static const String apiVersion = '2026-04';

  static String get storefrontEndpoint =>
      'https://$shopDomain/api/$apiVersion/graphql.json';

  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'X-Shopify-Storefront-Access-Token': storefrontAccessToken,
      };

  /// Sent with Shopify CDN image requests: the CDN then serves WebP, which is
  /// ~40% smaller than the uploaded JPEG for the home banners.
  static const Map<String, String> imageHeaders = {
    'Accept': 'image/webp,image/*',
  };

  /// The website's existing MSG91 "OTPLOGIN" widget (Mobile Integration OFF),
  /// shared with the app — the app calls the same web widget endpoints the
  /// site's script does, so nothing on MSG91 or the website changes. Both
  /// values are public (Flits prints them on every storefront page). The
  /// MSG91 authkey must NOT live here — it stays in the otp_login_worker.
  static const String msg91WidgetId  = '346745666e47313436363133';
  static const String msg91TokenAuth = '427260TfO1MVHhWyvx66a9d56bP1';

  /// OTP login backend (otp_login_worker/): on Vercel
  /// `https://<project>.vercel.app/api`, on Cloudflare the worker URL.
  static const String otpLoginUrl =
      'https://otploginworker.vercel.app/api';

  /// App Store / Play review demo number: no SMS is sent, the OTP is checked
  /// by the worker against its REVIEW_OTP secret (must match REVIEW_PHONE).
  static const String reviewPhone = '+916123450987';

  static const String storeUrl      = 'https://rookiesjeans.com';
  /// Same "Track Your Order" page the website footer links to (EcoTrack),
  /// where the customer enters their order number and email/phone.
  static const String trackOrderUrl  = '$storeUrl/apps/ecotrack';

  static const String fontHeading    = 'Anton';
  static const String fontSubheading = 'BebasNeue';
  static const String fontBody       = 'Archivo';
  static const String fontAccent     = 'RobotoMono';
  static const String fontBodyBold   = fontAccent;
  static const String fontAlteBold   = fontBody;
  static const String fontNumber     = fontBody;
  static const String fontRupee      = 'Serif4';

  static const String hotDealsHandle    = 'hot-deals';
  static const String trendingNowHandle = 'trending-now';

  /// Shopify navigation menus (Online Store → Menus) that drive Explore
  /// Categories and the Collections tab, in display order. Each item links
  /// to a collection; its sub-items are its nested items, or else the menu
  /// handled like that collection (e.g. "shirts", "tshirts-1").
  static const List<String> exploreMenuHandles = ['top-wear', 'bottom-wear'];

  /// Offline fallback for [exploreMenuHandles] — only used when those menus
  /// can't be loaded. Same shape: tab → group → card, every card a Shopify
  /// collection handle. A group's own `handle` is opened when its title is
  /// tapped ('' = none).
  static const List<Map<String, Object>> exploreMenuSections = [
    {
      'title': 'Top Wear',
      'groups': [
        {
          'title': 'Shirts',
          'handle': 'shirts',
          'items': [
            {'title': 'Cargo Shirts', 'handle': 'cargo-shirts'},
            {'title': 'Check Shirts', 'handle': 'check-shirts'},
            {'title': 'Stripe Shirts', 'handle': 'stripe-shirts'},
            {'title': 'Denim Shirts', 'handle': 'denim-shirts-1'},
            {'title': 'Corduroy Shirts', 'handle': 'corduroy-shirts'},
            {'title': 'Pure Linen Shirts', 'handle': 'pure-linen-shirts'},
            {'title': 'Solid Shirts', 'handle': 'solid-shirts'},
            {'title': 'Printed Shirts', 'handle': 'printed-shirts'},
            {'title': 'Textured Shirts', 'handle': 'textured-shirts'},
            {'title': 'Half Sleeve Shirts', 'handle': 'half-sleeve-shirts'},
            {'title': 'Linen-Blend Shirts', 'handle': 'linen-shirts'},
          ],
        },
        {
          'title': 'T-Shirts',
          'handle': 'tshirts',
          'items': [
            {'title': 'Regular T-Shirts', 'handle': 'regular-tshirts'},
            {'title': 'Oversized T-Shirts', 'handle': 'oversized-tshirts'},
            {'title': 'Polo T-Shirts', 'handle': 'polo-tshirts'},
            {'title': 'Full-Sleeve T-Shirts', 'handle': 'full-sleeve-tshirts'},
          ],
        },
        {
          'title': 'Jackets',
          'handle': 'jacket',
          'items': [
            {'title': 'Denim Jackets', 'handle': 'denim-jackets'},
            {'title': 'Utility Jackets', 'handle': 'utility-jackets'},
            {'title': 'Suede Jackets', 'handle': 'suede-jackets'},
            {'title': 'Puffer Jackets', 'handle': 'puffer-jackets'},
            {'title': 'Leather Jackets', 'handle': 'leather-jackets'},
            {'title': 'Light Jackets', 'handle': 'light-jackets'},
            {'title': 'Shackets', 'handle': 'shackets'},
          ],
        },
        {
          'title': 'Knits & Sweats',
          'handle': 'flatknit-sweaters',
          'items': [
            {'title': 'Sweatshirts', 'handle': 'sweatshirts'},
            {'title': 'Hoodies', 'handle': 'hoodies'},
            {'title': 'Flatknits', 'handle': 'flatknits'},
            {'title': 'Sweaters', 'handle': 'sweaters'},
          ],
        },
        {
          'title': 'Kurtas & Co-ords',
          'handle': '',
          'items': [
            {'title': 'Kurtas', 'handle': 'kurtas'},
            {'title': 'Co-ord Sets', 'handle': 'co-ords'},
          ],
        },
      ],
    },
    {
      'title': 'Bottom Wear',
      'groups': [
        {
          'title': 'Jeans',
          'handle': 'jeans',
          'items': [
            {'title': 'Jann (Loose Stretch)', 'handle': 'jeans-jann'},
            {'title': 'Jesse (Straight Stretch)', 'handle': 'jeans-jesse'},
            {'title': 'Lennon (Slim Stretch)', 'handle': 'jeans-lennon'},
            {'title': 'Mojo (Baggy / Oversized)', 'handle': 'jeans-mojo'},
            {'title': 'Nikki (Signature Bootcut)', 'handle': 'jeans-nikki'},
            {'title': 'Springsteen (Ankle Tapered)', 'handle': 'jeans-springsteen'},
          ],
        },
        {
          'title': 'Cargos & Pants',
          'handle': 'cargos',
          'items': [
            {'title': 'Cargo Pants', 'handle': 'cargo-pants'},
            {'title': 'Balloon Fit Cargos', 'handle': 'balloon-fit-cargos'},
            {'title': 'Utility Pants', 'handle': 'utility-pants'},
            {'title': 'Linen Cargos', 'handle': 'linen-cargos'},
            {'title': 'Denim Cargo', 'handle': 'denim-cargo'},
            {'title': 'Chinos', 'handle': 'chinos'},
            {'title': 'Korean Fit Trousers', 'handle': 'korean-fit-trousers'},
            {'title': 'Linen Trousers', 'handle': 'linen-trousers'},
            {'title': 'Casual Pants', 'handle': 'casual-pants'},
          ],
        },
        {
          'title': 'Shorts',
          'handle': 'shorts',
          'items': [
            {'title': 'Cargo Shorts', 'handle': 'cargo-shorts'},
            {'title': 'Linen Shorts', 'handle': 'linen-shorts'},
            {'title': 'Jorts', 'handle': 'jorts'},
          ],
        },
      ],
    },
  ];

  static const int primaryColorHex   = 0xFF111111;
  static const int accentOrangeHex   = 0xFFFF6B00;
  static const int bgColorHex        = 0xFFFFFFFF;
  static const int cardColorHex      = 0xFFFFFFFF;
  static const int secondaryTextHex  = 0xFF6B6B6B;
  static const int borderColorHex    = 0xFFDDDDDD;
}