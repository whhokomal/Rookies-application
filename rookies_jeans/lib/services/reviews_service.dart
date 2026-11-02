import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:rookies_jeans/constants/shopify_constants.dart';

/// One Judge.me review, as shown in the product page's reviews section.
class ProductReview {
  final int rating;
  final String title;
  final String body;
  final String reviewerName;
  final bool verifiedBuyer;
  final DateTime? createdAt;
  final List<String> pictureUrls;

  const ProductReview({
    required this.rating,
    required this.title,
    required this.body,
    required this.reviewerName,
    required this.verifiedBuyer,
    this.createdAt,
    this.pictureUrls = const [],
  });

  factory ProductReview.fromJson(Map<String, dynamic> json) => ProductReview(
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        title: (json['title'] as String? ?? '').trim(),
        body: _stripHtml(json['body_html'] as String? ?? ''),
        reviewerName: (json['reviewer_name'] as String? ?? '').trim(),
        verifiedBuyer: json['verified_buyer'] == true,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        pictureUrls: [
          for (final p in (json['pictures_urls'] as List? ?? const []))
            if (p is String)
              p
            else if (p is Map && p['original'] is String)
              p['original'] as String,
        ],
      );

  static String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
}

/// A product's Judge.me rating summary plus its first page of reviews.
class ProductReviews {
  final double averageRating;
  final int reviewCount;

  /// Number of reviews per star, index 0 = 1 star ... index 4 = 5 stars.
  final List<int> starCounts;
  final List<ProductReview> reviews;

  const ProductReviews({
    required this.averageRating,
    required this.reviewCount,
    required this.starCounts,
    required this.reviews,
  });

  static const empty = ProductReviews(
    averageRating: 0,
    reviewCount: 0,
    starCounts: [0, 0, 0, 0, 0],
    reviews: [],
  );

  factory ProductReviews.fromJson(Map<String, dynamic> json) {
    final starCounts = [0, 0, 0, 0, 0];
    for (final row in (json['histogram'] as List? ?? const [])) {
      final star = (row['rating'] as num?)?.toInt() ?? 0;
      if (star >= 1 && star <= 5) {
        starCounts[star - 1] = (row['frequency'] as num?)?.toInt() ?? 0;
      }
    }
    return ProductReviews(
      averageRating:
          double.tryParse('${json['average_rating'] ?? 0}') ?? 0,
      reviewCount: (json['number_of_reviews'] as num?)?.toInt() ?? 0,
      starCounts: starCounts,
      reviews: [
        for (final r in (json['reviews'] as List? ?? const []))
          ProductReview.fromJson(r as Map<String, dynamic>),
      ],
    );
  }
}

/// Reads product reviews from Judge.me, the reviews app the website uses.
///
/// Uses the same public JSON endpoint Judge.me's own storefront widget
/// calls, so no API token is needed (nothing secret ships in the app). The
/// endpoint isn't part of Judge.me's documented API; if it ever stops
/// answering, the product page just shows no reviews.
class ReviewsService {
  ReviewsService._();
  static final ReviewsService instance = ReviewsService._();

  static const int pageSize = 10;

  final Map<String, ProductReviews> _cache = {};

  /// Reviews for a product, by its Shopify gid or numeric id. Returns
  /// [ProductReviews.empty] on any failure.
  Future<ProductReviews> getReviews(String productId) async {
    final id = productId.split('/').last;
    final cached = _cache[id];
    if (cached != null) return cached;

    final reviews = await _fetchPage(id, 1);
    if (reviews == null) return ProductReviews.empty;
    _cache[id] = reviews;
    return reviews;
  }

  /// Page [page] (1-based, [pageSize] per page) of a product's reviews, for
  /// "Show more". Empty on any failure.
  Future<List<ProductReview>> getReviewsPage(String productId, int page) async {
    final id = productId.split('/').last;
    return (await _fetchPage(id, page))?.reviews ?? const [];
  }

  Future<ProductReviews?> _fetchPage(String id, int page) async {
    final uri = Uri.https('judge.me', '/reviews/reviews_for_widget', {
      'url': ShopifyConstants.shopDomain,
      'shop_domain': ShopifyConstants.shopDomain,
      'platform': 'shopify',
      'product_id': id,
      'page': '$page',
      'per_page': '$pageSize',
      'sort_by': 'most_recent',
    });
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return ProductReviews.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('ReviewsService page $page [$id] error: $e');
      return null;
    }
  }

  /// The website's product page, scrolled to the Judge.me widget, where the
  /// "Write a review" form lives.
  static String writeReviewUrl(String handle) =>
      '${ShopifyConstants.storeUrl}/products/$handle#judgeme_product_reviews';
}
