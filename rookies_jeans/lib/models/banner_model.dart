class HomeBanner {
  final String id;
  final String? imageUrl;
  final String title;
  final String subtitle;

  /// Where tapping the banner goes: a collection handle, a
  /// `/collections/...` or `/products/...` path (full store URLs too), or
  /// any other web URL. Null = the banner isn't tappable.
  final String? link;

  /// Width ÷ height of the uploaded image, when known, so the banner can be
  /// shown whole instead of cropped.
  final double? aspectRatio;

  const HomeBanner({
    required this.id,
    this.imageUrl,
    required this.title,
    required this.subtitle,
    this.link,
    this.aspectRatio,
  });

  /// A `collections_banner` metaobject (the Collections page's own
  /// banners), queried with `image`, `link` field aliases.
  factory HomeBanner.fromCollectionsBannerJson(Map<String, dynamic> json) {
    final link = (json['link']?['value'] as String? ?? '').trim();
    final image = json['image']?['reference']?['image'];
    final width = (image?['width'] as num?)?.toDouble();
    final height = (image?['height'] as num?)?.toDouble();
    return HomeBanner(
      id: json['id'] as String,
      imageUrl: image?['url'] as String?,
      title: '',
      subtitle: '',
      link: link.isNotEmpty ? link : null,
      aspectRatio: (width != null && height != null && width > 0 && height > 0)
          ? width / height
          : null,
    );
  }

  factory HomeBanner.fromMetaobjectJson(Map<String, dynamic> json) {
    final fields = (json['fields'] as List?) ?? [];
    String title = '', subtitle = '', link = '';
    String? imageUrl;

    for (final f in fields) {
      switch (f['key'] as String) {
        case 'title':    title    = f['value'] as String? ?? ''; break;
        case 'subtitle': subtitle = f['value'] as String? ?? ''; break;
        // Shown in Shopify as "Redirect link".
        case 'cta_url':  link     = (f['value'] as String? ?? '').trim(); break;
        case 'image':
          imageUrl = f['reference']?['image']?['url'] as String?;
          break;
      }
    }

    return HomeBanner(
      id: json['id'] as String,
      imageUrl: imageUrl,
      title: title,
      subtitle: subtitle,
      link: link.isNotEmpty ? link : null,
    );
  }
}
