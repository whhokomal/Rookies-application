import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/services/cart_service.dart';

class RookiesBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const RookiesBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const Color _glassTint     = Colors.black;
  static const double _glassOpacity = 0.28;
  static const Color _glassBorder   = Colors.white;
  static const double _blurAmount   = 24;

  static const Color _activeCircleColor  = Colors.white;
  static const Color _activeIconColor    = Color(0xFF111111);
  static const Color _inactiveIconColor  = Colors.white70;
  static const Color _badgeBg            = AppColors.danger;

  static const int _cartIndex = 4;

  static const List<_NavItem> _items = [
    _NavItem(
    icon: Icons.menu_outlined,
    activeIcon: Icons.menu_rounded,
  ),
  _NavItem(
    icon: Icons.search_rounded,
    activeIcon: Icons.search_rounded,
  ),
  _NavItem(
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
  ),
  _NavItem(
    icon: Icons.person_outline_rounded,
    activeIcon: Icons.person_rounded,
  ),
  _NavItem(
    icon: Icons.shopping_bag_outlined,
    activeIcon: Icons.shopping_bag_rounded,
  ),
];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final factor = (width / 400).clamp(0.9, 1.3).toDouble();
    final barHeight = (48 * factor).clamp(46.0, 58.0);
    final iconSize = (16 * factor).clamp(18.0, 20.0);

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: _blurAmount, sigmaY: _blurAmount),
              child: Stack(
                children: [
                  Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: _glassTint.withValues(alpha: _glassOpacity),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: _glassBorder.withValues(alpha: 0.15),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.10),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.55],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 24,
                    right: 24,
                    child: IgnorePointer(
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.45),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: barHeight,
                    child: Row(
                      children: List.generate(_items.length, (i) {
                        final item = _items[i];
                        final active = i == currentIndex;
                        return Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onTap(i),
                            child: Center(
                              child: _NavIcon(
                                icon: active ? item.activeIcon : item.icon,
                                active: active,
                                iconSize: iconSize,
                                showCartBadge: i == _cartIndex,
                                activeCircleColor: _activeCircleColor,
                                activeIconColor: _activeIconColor,
                                inactiveIconColor: _inactiveIconColor,
                                badgeColor: _badgeBg,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.icon,
    required this.active,
    required this.iconSize,
    required this.showCartBadge,
    required this.activeCircleColor,
    required this.activeIconColor,
    required this.inactiveIconColor,
    required this.badgeColor,
  });

  final IconData icon;
  final bool active;
  final double iconSize;
  final bool showCartBadge;
  final Color activeCircleColor;
  final Color activeIconColor;
  final Color inactiveIconColor;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    final double circleSize = iconSize + 14;

    final iconWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Icon(
        icon,
        key: ValueKey(active),
        size: iconSize,
        color: active ? activeIconColor : inactiveIconColor,
      ),
    );

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: circleSize,
      height: circleSize,
      decoration: BoxDecoration(
        color: active ? activeCircleColor : Colors.transparent,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: iconWidget,
    );

    if (!showCartBadge) return content;

    return AnimatedBuilder(
      animation: CartService.instance,
      builder: (context, _) {
        final count = CartService.instance.cart.totalQuantity;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            content,
            if (count > 0)
              Positioned(
                right: -2,
                top: -2,
                child: _CountBadge(count: count, color: badgeColor),
              ),
          ],
        );
      },
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      scale: 1,
      child: Container(
        constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 1.1),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
  });
}