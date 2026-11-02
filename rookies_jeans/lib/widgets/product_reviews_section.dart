import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/services/reviews_service.dart';
import 'package:rookies_jeans/widgets/rating_badge.dart';
import 'package:rookies_jeans/widgets/web_view_screen.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) {
  final local = d.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// Tappable "★★★★☆ 4.5 (12 reviews)" line under the product title.
class RatingSummaryLine extends StatelessWidget {
  const RatingSummaryLine({super.key, required this.reviews, this.onTap});

  final ProductReviews reviews;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final count = reviews.reviewCount;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StarRow(rating: reviews.averageRating, size: 16),
            const SizedBox(width: 6),
            Text(
              formatRating(reviews.averageRating),
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '($count ${count == 1 ? 'review' : 'reviews'})',
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 13,
                color: AppColors.secondaryText,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Customer Reviews" block on the product page: average, star breakdown,
/// the latest reviews (3 at first, more on "Show more") and a button to
/// write one.
class ProductReviewsSection extends StatefulWidget {
  const ProductReviewsSection({
    super.key,
    required this.reviews,
    required this.productId,
    required this.productHandle,
  });

  final ProductReviews reviews;
  final String productId;
  final String productHandle;

  @override
  State<ProductReviewsSection> createState() => _ProductReviewsSectionState();
}

class _ProductReviewsSectionState extends State<ProductReviewsSection> {
  static const int _initialCount = 3;
  static const int _showMoreStep = 5;

  ProductReviews get reviews => widget.reviews;

  /// Every review fetched so far (page 1 comes with [reviews]).
  late List<ProductReview> _loaded = [...reviews.reviews];
  int _pagesLoaded = 1;
  int _visible = _initialCount;
  bool _loadingMore = false;

  @override
  void didUpdateWidget(covariant ProductReviewsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId ||
        oldWidget.reviews != widget.reviews) {
      _loaded = [...reviews.reviews];
      _pagesLoaded = 1;
      _visible = _initialCount;
      _loadingMore = false;
    }
  }

  bool get _hasMore =>
      _visible < _loaded.length || _loaded.length < reviews.reviewCount;

  Future<void> _showMore() async {
    final want = _visible + _showMoreStep;
    if (want > _loaded.length && _loaded.length < reviews.reviewCount) {
      final productId = widget.productId;
      setState(() => _loadingMore = true);
      final next = await ReviewsService.instance
          .getReviewsPage(productId, _pagesLoaded + 1);
      if (!mounted || widget.productId != productId) return;
      setState(() {
        _loadingMore = false;
        if (next.isEmpty) {
          // Nothing more came back; stop offering "Show more".
          _visible = _loaded.length;
          return;
        }
        _pagesLoaded++;
        _loaded.addAll(next);
        _visible = want;
      });
      return;
    }
    setState(() => _visible = want);
  }

  void _openWriteReview(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebViewScreen(
          title: 'Write a Review',
          url: ReviewsService.writeReviewUrl(widget.productHandle),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double s(double base) =>
        Responsive.of(context, baseW: 400, maxScale: 1.25).s(base);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform(
            transform: Matrix4.skewX(-0.2),
            alignment: Alignment.bottomLeft,
            child: Text(
              'CUSTOMER REVIEWS',
              style: TextStyle(
                fontFamily: AppFonts.heading,
                fontSize: s(22).clamp(20.0, 28.0),
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (reviews.reviewCount == 0)
            Text(
              'No reviews yet. Bought this? Be the first to tell others '
              'how it fits.',
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 13,
                height: 1.5,
                color: AppColors.secondaryText,
              ),
            )
          else ...[
            _summary(),
            const SizedBox(height: 8),
            for (final review in _loaded.take(_visible)) ...[
              Divider(height: 24, color: AppColors.border),
              _ReviewTile(review: review),
            ],
            if (_hasMore) ...[
              const SizedBox(height: 12),
              Center(
                child: _loadingMore
                    ? SizedBox(
                        height: 36,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary),
                          ),
                        ),
                      )
                    : TextButton(
                        onPressed: _showMore,
                        child: Text(
                          'SHOW MORE',
                          style: TextStyle(
                            fontFamily: AppFonts.accent,
                            fontSize: 13,
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.primary,
                          ),
                        ),
                      ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              onPressed: () => _openWriteReview(context),
              style: OutlinedButton.styleFrom(
                shape: AppShapes.button,
                side: BorderSide(color: AppColors.primary),
                foregroundColor: AppColors.primary,
              ),
              child: Text(
                'WRITE A REVIEW',
                style: TextStyle(fontFamily: AppFonts.accent, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Big average on the left, a bar per star on the right.
  Widget _summary() {
    final total = reviews.reviewCount;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          children: [
            Text(
              formatRating(reviews.averageRating),
              style: TextStyle(
                fontFamily: AppFonts.heading,
                fontSize: 40,
                color: AppColors.primary,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            StarRow(rating: reviews.averageRating, size: 14),
            const SizedBox(height: 4),
            Text(
              '$total ${total == 1 ? 'review' : 'reviews'}',
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 11,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            children: [
              for (int star = 5; star >= 1; star--)
                _histogramRow(star, reviews.starCounts[star - 1], total),
            ],
          ),
        ),
      ],
    );
  }

  Widget _histogramRow(int star, int count, int total) {
    final label = TextStyle(
      fontFamily: AppFonts.body,
      fontSize: 11,
      color: AppColors.secondaryText,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 10, child: Text('$star', style: label)),
          const Icon(Icons.star_rounded, size: 12, color: kRatingStarColor),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : count / total,
                minHeight: 6,
                backgroundColor: AppColors.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(kRatingStarColor),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 22,
            child: Text('$count', style: label, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final ProductReview review;

  @override
  Widget build(BuildContext context) {
    final name =
        review.reviewerName.isEmpty ? 'Customer' : review.reviewerName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StarRow(rating: review.rating.toDouble(), size: 14),
            const Spacer(),
            if (review.createdAt != null)
              Text(
                _formatDate(review.createdAt!),
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 11,
                  color: AppColors.hint,
                ),
              ),
          ],
        ),
        if (review.title.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            review.title,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
        if (review.body.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            review.body,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 13,
              height: 1.45,
              color: AppColors.primary,
            ),
          ),
        ],
        if (review.pictureUrls.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: review.pictureUrls.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: review.pictureUrls[i],
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: AppColors.fieldFill),
                  errorWidget: (_, _, _) =>
                      Container(color: AppColors.fieldFill),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              name,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
              ),
            ),
            if (review.verifiedBuyer) ...[
              const SizedBox(width: 8),
              const Icon(Icons.verified_rounded,
                  size: 14, color: AppColors.success),
              const SizedBox(width: 3),
              Text(
                'Verified Buyer',
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 11,
                  color: AppColors.success,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
