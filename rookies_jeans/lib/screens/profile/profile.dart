import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/models/shop_policy_model.dart';
import 'package:rookies_jeans/screens/profile/policy_screen.dart';
import 'package:rookies_jeans/services/auth_service.dart';
import 'package:rookies_jeans/services/otp_auth_service.dart';
import 'package:rookies_jeans/widgets/web_view_screen.dart';

const double _kMaxContentW = 640;

double _s(BuildContext c, double base) => Responsive.of(c, baseW: 375).s(base);

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AuthService.instance,
        ThemeService.instance,
      ]),
      builder: (context, _) {
        return AuthService.instance.isLoggedIn
            ? _LoggedInProfile()
            : _LoggedOutProfile();
      },
    );
  }
}

class _LoggedOutProfile extends StatelessWidget {
  const _LoggedOutProfile();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          final screenH = media.size.height;
          final isWide = constraints.maxWidth > _kMaxContentW;
          final halfH = (screenH * (isWide ? 0.5 : 0.66)).clamp(220.0, 560.0);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kMaxContentW),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: halfH,
                      child: Image.asset(
                        'assets/welcome_model.png',
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (_, _, _) => Container(
                          color: AppColors.fieldFill,
                          child: Icon(
                            Icons.person,
                            size: _s(context, 96).clamp(72.0, 140.0),
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      color: AppColors.card,
                      padding: EdgeInsets.fromLTRB(
                        _s(context, 24),
                        _s(context, 28),
                        _s(context, 24),
                        _s(context, 28),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'WELCOME!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppFonts.heading,
                              color: AppColors.primary,
                              fontSize: _s(context, 26).clamp(22.0, 34.0),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: _s(context, 20)),
                          SizedBox(
                            height: _s(context, 50).clamp(46.0, 62.0),
                            child: ElevatedButton(
                              onPressed: () => context.push('/login'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.onPrimary,
                                elevation: 0,
                              ),
                              child: Text(
                                'Sign In',
                                style: TextStyle(
                                  fontFamily: AppFonts.body,
                                  fontSize: _s(context, 16).clamp(14.0, 20.0),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: _s(context, 14)),
                          Center(
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: TextStyle(
                                  fontFamily: AppFonts.body,
                                  fontSize: _s(context, 13).clamp(12.0, 17.0),
                                  color: AppColors.secondaryText,
                                ),
                                children: [
                                  const TextSpan(
                                    text: "Don't have an account? ",
                                  ),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: GestureDetector(
                                      onTap: () => context.push('/register'),
                                      child: Text(
                                        'Create Account',
                                        style: TextStyle(
                                          fontFamily: AppFonts.body,
                                          fontSize: _s(
                                            context,
                                            13,
                                          ).clamp(12.0, 17.0),
                                          color: AppColors.primary,
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: _s(context, 12)),
                    const _MoreSection(showSignOut: false),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoggedInProfile extends StatelessWidget {
  const _LoggedInProfile();

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentW),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: AppColors.card,
                    padding: EdgeInsets.fromLTRB(
                      _s(context, 24),
                      _s(context, 40),
                      _s(context, 24),
                      _s(context, 32),
                    ),
                    child: Column(
                      children: [
                        // Avatar with a pencil on its top right that
                        // opens Edit Profile (the avatar itself does too).
                        Builder(
                          builder: (context) {
                            final double avatar = _s(
                              context,
                              72,
                            ).clamp(64.0, 96.0);
                            final double pencil = _s(
                              context,
                              16,
                            ).clamp(14.0, 20.0);
                            // The pencil's patch: page colour, so the ring
                            // breaks cleanly around the pencil.
                            final double patch = pencil + 8;
                            // Centre it on the ring at 45° (top right).
                            final double r = avatar / 2;
                            final double cx = r + r * 0.7071;
                            final double cy = r - r * 0.7071;
                            return GestureDetector(
                              onTap: () => context.push('/edit-profile'),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: avatar,
                                    height: avatar,
                                    decoration: BoxDecoration(
                                      color: AppColors.fieldFill,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.border,
                                        width: 1.5,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      auth.initials,
                                      style: TextStyle(
                                        fontFamily: AppFonts.body,
                                        fontSize: _s(
                                          context,
                                          24,
                                        ).clamp(20.0, 32.0),
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: cx - patch / 2,
                                    top: cy - patch / 2,
                                    child: Semantics(
                                      button: true,
                                      label: 'Edit profile',
                                      child: Container(
                                        width: patch,
                                        height: patch,
                                        decoration: BoxDecoration(
                                          color: AppColors.card,
                                          shape: BoxShape.circle,
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(
                                          Icons.edit,
                                          size: pencil,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        SizedBox(height: _s(context, 14)),
                        Text(
                          auth.firstName.isNotEmpty
                              ? 'HEY, ${auth.firstName.toUpperCase()}!'
                              : 'HEY!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: AppFonts.heading,
                            fontSize: _s(context, 22).clamp(18.0, 30.0),
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.italic,
                            color: AppColors.primary,
                          ),
                        ),
                        if (auth.phone.isNotEmpty || auth.email.isNotEmpty) ...[
                          SizedBox(height: _s(context, 6)),
                          Text(
                            auth.phone.isNotEmpty ? auth.phone : auth.email,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppFonts.body,
                              fontSize: _s(context, 13).clamp(12.0, 17.0),
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                        SizedBox(height: _s(context, 24)),
                        Row(
                          children: const [
                            Expanded(
                              child: _QuickAction(
                                icon: Icons.inventory_2_outlined,
                                label: 'Order\nHistory',
                                color: Color(0xFFE8A020),
                                route: '/orders',
                              ),
                            ),
                            Expanded(
                              child: _QuickAction(
                                icon: Icons.menu_book_outlined,
                                label: 'Address\nBook',
                                color: Color(0xFF4285F4),
                                route: '/addresses',
                              ),
                            ),
                            Expanded(
                              child: _QuickAction(
                                icon: Icons.chat_bubble_outline_rounded,
                                label: 'Change\nPassword',
                                color: Color(0xFF888888),
                                route: '/change-password',
                              ),
                            ),
                            Expanded(
                              child: _QuickAction(
                                icon: Icons.favorite_border_rounded,
                                label: 'Your\nFavourites',
                                color: Color(0xFFD32F2F),
                                route: '/wishlist',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: _s(context, 12)),
                  const _MoreSection(showSignOut: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreSection extends StatelessWidget {
  const _MoreSection({required this.showSignOut});
  final bool showSignOut;

  void _openWebView(
    BuildContext context, {
    required String title,
    required String url,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewScreen(title: title, url: url),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Delete account?',
          style: TextStyle(
            fontFamily: AppFonts.subheading,
            color: AppColors.primary,
          ),
        ),
        content: Text(
          'This permanently deletes your Rookies account, saved addresses and '
          'profile details. Order records may be kept where the law requires. '
          'This cannot be undone.',
          style: TextStyle(
            fontFamily: AppFonts.body,
            color: AppColors.secondaryText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final error = await OtpAuthService.instance.deleteAccount();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final messenger = ScaffoldMessenger.of(context);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    await AuthService.instance.signOut();
    messenger.showSnackBar(
      const SnackBar(content: Text('Your account has been deleted.')),
    );
    if (context.mounted) context.go('/home');
  }

  void _showThemeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: ThemeService.instance,
          builder: (context, _) {
            final current = ThemeService.instance.mode;

            Widget option(AppThemeMode mode, String label, IconData icon) {
              final selected = current == mode;
              return ListTile(
                leading: Icon(
                  icon,
                  color: selected ? AppColors.primary : AppColors.secondaryText,
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: _s(context, 15).clamp(13.0, 18.0),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? AppColors.primary
                        : AppColors.secondaryText,
                  ),
                ),
                trailing: selected
                    ? Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  ThemeService.instance.setMode(mode);
                  Navigator.of(sheetContext).pop();
                },
              );
            }

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: _s(context, 12)),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      _s(context, 20),
                      _s(context, 16),
                      _s(context, 20),
                      _s(context, 4),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Theme Appearance',
                        style: TextStyle(
                          fontFamily: AppFonts.subheading,
                          fontSize: _s(context, 18).clamp(16.0, 24.0),
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  option(
                    AppThemeMode.light,
                    'Light',
                    Icons.light_mode_outlined,
                  ),
                  option(AppThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                  option(
                    AppThemeMode.system,
                    'System',
                    Icons.settings_suggest_outlined,
                  ),
                  SizedBox(height: _s(context, 8)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Container(
        color: AppColors.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                _s(context, 20),
                _s(context, 20),
                _s(context, 20),
                _s(context, 6),
              ),
              child: Text(
                'MORE',
                style: TextStyle(
                  fontFamily: AppFonts.heading,
                  fontSize: _s(context, 22).clamp(18.0, 30.0),
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                  color: AppColors.primary,
                ),
              ),
            ),
            _MoreTile(
              label: 'Theme Appearance',
              trailingText: ThemeService.instance.label,
              onTap: () => _showThemeSheet(context),
            ),
            for (final type in ShopPolicyType.values)
              _MoreTile(
                label: type.label,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PolicyScreen(type: type)),
                ),
              ),
            _MoreTile(
              label: 'Store Locator',
              onTap: () => _openWebView(
                context,
                title: 'Store Locator',
                url: '${ShopifyConstants.storeUrl}/pages/store-locator',
              ),
            ),
            _MoreTile(
              label: 'Track Your Order',
              onTap: () => _openWebView(
                context,
                title: 'Track Your Order',
                url: ShopifyConstants.trackOrderUrl,
              ),
            ),
            if (showSignOut)
              _MoreTile(
                label: 'Sign Out',
                icon: Icons.logout_rounded,
                onTap: () async {
                  await AuthService.instance.signOut();
                  if (context.mounted) context.go('/home');
                },
              ),
            if (showSignOut)
              _MoreTile(
                label: 'Delete Account',
                icon: Icons.delete_outline_rounded,
                onTap: () => _confirmDeleteAccount(context),
              ),
            SizedBox(height: _s(context, 8)),
          ],
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.label,
    required this.onTap,
    this.icon,
    this.trailingText,
  });
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _s(context, 20),
              vertical: _s(context, 15),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: _s(context, 18).clamp(16.0, 24.0),
                    color: AppColors.secondaryText,
                  ),
                  SizedBox(width: _s(context, 10)),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: _s(context, 14).clamp(13.0, 18.0),
                      color: AppColors.primary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                if (trailingText != null) ...[
                  Text(
                    trailingText!,
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: _s(context, 13).clamp(12.0, 16.0),
                      color: AppColors.hint,
                    ),
                  ),
                  SizedBox(width: _s(context, 6)),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  size: _s(context, 18).clamp(16.0, 24.0),
                  color: AppColors.hint,
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: AppColors.border),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.route,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String route;

  @override
  Widget build(BuildContext context) {
    final circle = _s(context, 56).clamp(48.0, 72.0);
    return GestureDetector(
      onTap: () => context.push(route),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _s(context, 2)),
        child: Column(
          children: [
            Container(
              width: circle,
              height: circle,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: _s(context, 24).clamp(20.0, 32.0),
              ),
            ),
            SizedBox(height: _s(context, 8)),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: _s(context, 11).clamp(10.0, 14.0),
                color: AppColors.secondaryText,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
