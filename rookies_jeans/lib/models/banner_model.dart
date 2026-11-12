class HomeBanner {
  final String id;
  final String? imageUrl;
  final String title;
  final String subtitle;

  /// Where tapping the banner goes: a collection handle, a
  /// `/collections/...` or `/products/...` path (full store URLs too), or
  /// any other web URL. Null = the banner isn't tappable.
  final String? link;

  /// Title of the picked "Collection" when the banner opens one, used as
  /// that page's title.
  final String? collectionTitle;

  /// Text on the banner's button ("Button label" in Shopify). Null = no
  /// button; the button opens [link].
  final String? buttonLabel;

  /// Button text color as `#RRGGBB` ("Button text color" in Shopify). Null =
  /// white. The button itself is clear glass, so "Button color" is unused.
  final String? buttonTextColorHex;

  /// Width ÷ height of the uploaded image, when known, so the banner can be
  /// shown whole instead of cropped.
  final double? aspectRatio;

  const HomeBanner({
    required this.id,
    this.imageUrl,
    required this.title,
    required this.subtitle,
    this.link,
    this.collectionTitle,
    this.buttonLabel,
    this.buttonTextColorHex,
    this.aspectRatio,
  });

  /// A `collections_banner` metaobject (the Collections page's own
  /// banners), queried with `image`, `link` field aliases.
  factory HomeBanner.fromCollectionsBannerJson(Map<String, dynamic> json) {
    final picked = _pickedCollection(json['collection']?['reference']);
    final link = picked?.link ?? (json['link']?['value'] as String? ?? '').trim();
    final image = json['image']?['reference']?['image'];
    final width = (image?['width'] as num?)?.toDouble();
    final height = (image?['height'] as num?)?.toDouble();
    return HomeBanner(
      id: json['id'] as String,
      imageUrl: image?['url'] as String?,
      title: '',
      subtitle: '',
      link: link.isNotEmpty ? link : null,
      collectionTitle: picked?.title,
      aspectRatio: (width != null && height != null && width > 0 && height > 0)
          ? width / height
          : null,
    );
  }

  factory HomeBanner.fromMetaobjectJson(Map<String, dynamic> json) {
    final fields = (json['fields'] as List?) ?? [];
    String title = '', subtitle = '', link = '', buttonLabel = '';
    String? imageUrl, buttonTextColor;
    ({String link, String? title})? picked;

    for (final f in fields) {
      switch (f['key'] as String) {
        case 'title':    title    = f['value'] as String? ?? ''; break;
        case 'subtitle': subtitle = f['value'] as String? ?? ''; break;
        // Shown in Shopify as "Redirect link".
        case 'cta_url':  link     = (f['value'] as String? ?? '').trim(); break;
        case 'button_label':
          buttonLabel = (f['value'] as String? ?? '').trim();
          break;
        case 'button_text_color': buttonTextColor = f['value'] as String?; break;
        case 'collection':
          picked = _pickedCollection(f['reference']);
          break;
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
      // A picked collection wins over the typed redirect link.
      link: picked?.link ?? (link.isNotEmpty ? link : null),
      collectionTitle: picked?.title,
      buttonLabel: buttonLabel.isNotEmpty ? buttonLabel : null,
      buttonTextColorHex: buttonTextColor,
    );
  }

  /// A "Collection" reference as a `/collections/<handle>` link plus its
  /// title; null when none is picked.
  static ({String link, String? title})? _pickedCollection(dynamic ref) {
    final handle = (ref as Map?)?['handle'] as String?;
    if (handle == null || handle.isEmpty) return null;
    final title = (ref?['title'] as String?)?.trim();
    return (
      link: '/collections/$handle',
      title: title == null || title.isEmpty ? null : title,
    );
  }
}
