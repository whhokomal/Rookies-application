import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rookies_jeans/constants/app_ui.dart';

double _s(BuildContext c, double base) =>
    Responsive.of(c, baseW: 375).s(base);

/// The back arrow + big italic title bar used by the pages opened from the
/// Profile "More" list.
PreferredSizeWidget pageAppBar(BuildContext context, String title) {
  return AppBar(
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
      title.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: AppFonts.heading,
        fontSize: (MediaQuery.of(context).size.width * 0.09).clamp(20.0, 40.0),
        fontStyle: FontStyle.italic,
        height: 1,
        color: AppColors.primary,
      ),
    ),
    centerTitle: false,
  );
}

/// Centered "couldn't load" message with a Retry button.
class PageLoadError extends StatelessWidget {
  const PageLoadError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
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
                fontFamily: AppFonts.body,
                fontSize: _s(context, 14).clamp(13.0, 18.0),
                color: AppColors.secondaryText,
              ),
            ),
            SizedBox(height: _s(context, 16)),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                shape: AppShapes.button,
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
