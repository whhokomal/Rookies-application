import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/widgets/slant_chip.dart';

/// [mini] is a compact version of [small] (the home Explore Collections tabs);
/// [largeCompact] is a smaller [large] (the home Explore category chips).
enum StickerChipStyle { small, large, mono, mini, largeCompact }

/// Stand-in for black on the chips in dark theme.
const Color _kDarkInk = Color(0xFF2A2A2A);

/// Offset-shadow color in dark theme: a lighter grey so it stands out
/// against the background.
const Color _kDarkShadow = Color(0xFF4A4A4A);

/// Slanted "sticker" chip used by the category filters. Unselected: white
/// with a black outline and black offset shadow. Selected: red with a black
/// shadow for [StickerChipStyle.large], black with a red shadow otherwise.
///
/// With [fadeAnimation], selecting the chip softly fades it to the selected
/// colors (fill, text and shadow together); deselecting snaps straight
/// back to white.
class StickerChip extends StatelessWidget {
  const StickerChip({
    super.key,
    required this.label,
    required this.selected,
    required this.style,
    required this.onTap,
    this.fadeAnimation = false,
  });

  final String label;
  final bool selected;
  final StickerChipStyle style;
  final VoidCallback onTap;
  final bool fadeAnimation;

  /// How long the [fadeAnimation] color fade takes.
  static const Duration fadeDuration = Duration(milliseconds: 350);

  @override
  Widget build(BuildContext context) {
    final bool large = style == StickerChipStyle.large;
    final bool mono = style == StickerChipStyle.mono;
    final bool mini = style == StickerChipStyle.mini;
    final bool largeCompact = style == StickerChipStyle.largeCompact;
    // Red-when-selected styling shared by both large variants.
    final bool redFill = large || largeCompact;
    final double height = large ? 48 : (largeCompact ? 28 : (mini ? 26 : 32));
    final double shadow = large ? 4 : (mini ? 2 : 3);
    final double borderWidth = large ? 2 : (mini ? 1.2 : 1.5);
    final EdgeInsets padding = EdgeInsets.symmetric(
      horizontal: large ? 20 : (mini ? 10 : (largeCompact ? 11 : 14)),
    );

    // Softened to dark grey in dark theme so the black fill and shadows
    // don't disappear into the near-black background.
    final bool dark = ThemeService.instance.isDark;
    final Color selectedFill = redFill
        ? SlantChip.accent
        : (dark ? _kDarkInk : Colors.black);
    final Color restingShadow = dark ? _kDarkShadow : Colors.black;
    final Color selectedShadow = redFill ? restingShadow : SlantChip.accent;

    TextStyle textStyle(Color color) => TextStyle(
      fontFamily: mono ? AppFonts.number : AppFonts.heading,
      fontSize: large
          ? 30
          : largeCompact
          ? 16
          : (mono ? 12 : (mini ? 14 : 18)),
      // Anton has one weight; w700 made Flutter fake-bold it. Only the
      // mono (Archivo) chips get a real bold.
      fontWeight: mono ? FontWeight.w700 : FontWeight.w400,
      letterSpacing: mono ? 1.2 : 0.4,
      height: 1,
      color: color,
    );

    // t = 0 is the resting (unselected) look, 1 the selected look.
    Widget chipAt(double t) => Container(
      height: height,
      alignment: Alignment.center,
      padding: padding,
      decoration: BoxDecoration(
        color: Color.lerp(Colors.white, selectedFill, t),
        border: Border.all(
          color: Color.lerp(Colors.black, selectedFill, t)!,
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Color.lerp(restingShadow, selectedShadow, t)!,
            offset: Offset(shadow, shadow),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        style: textStyle(Color.lerp(Colors.black, Colors.white, t)!),
      ),
    );

    final Widget chip = fadeAnimation
        ? TweenAnimationBuilder<double>(
            tween: Tween(end: selected ? 1.0 : 0.0),
            // Only the newly selected chip fades; deselecting snaps back.
            duration: selected ? fadeDuration : Duration.zero,
            curve: Curves.easeOut,
            builder: (context, t, _) => chipAt(t),
          )
        : chipAt(selected ? 1.0 : 0.0);

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        // Room for the slant and the offset shadow so neither gets clipped.
        padding: EdgeInsets.only(left: large ? 6 : 4, right: large ? 10 : 8),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(-0.2),
          child: chip,
        ),
      ),
    );
  }
}

/// A horizontally scrollable row of [StickerChip]s, centred when it fits.
class StickerChipRow extends StatelessWidget {
  const StickerChipRow({
    super.key,
    required this.height,
    required this.children,
  });

  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth - 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// One option inside a [GlassFilterPill].
class GlassFilterOption {
  const GlassFilterOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
}

/// Filter row: the caption (e.g. "FIT & FABRIC") sits in a smoky glass pill
/// styled like the bottom nav bar, and the options follow as plain floating
/// text with no button chrome. Scrolls horizontally when it overflows.
class GlassFilterPill extends StatelessWidget {
  const GlassFilterPill({
    super.key,
    required this.caption,
    required this.options,
  });

  final String caption;
  final List<GlassFilterOption> options;

  @override
  Widget build(BuildContext context) {
    final Color ink = ThemeService.instance.isDark
        ? Colors.white
        : Colors.black;

    return SizedBox(
      height: 40,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _GlassCaption(caption),
            const SizedBox(width: 8),
            for (final option in options)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: option.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 12,
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: TextStyle(
                      fontFamily: AppFonts.accent,
                      fontSize: 12,
                      fontWeight: option.selected
                          ? FontWeight.w700
                          : FontWeight.w400,
                      // RobotoMono is a variable font, so the weight has to
                      // be set on its wght axis to actually render bold.
                      fontVariations: [
                        FontVariation('wght', option.selected ? 700 : 400),
                      ],
                      letterSpacing: 1.2,
                      height: 1,
                      color: option.selected
                          ? SlantChip.accent
                          : ink.withValues(alpha: 0.7),
                      // Thin same-colour shadows either side thicken the
                      // strokes so the selection reads as bold even where
                      // the wght axis renders lighter than expected.
                      shadows: option.selected
                          ? const [
                              Shadow(
                                color: SlantChip.accent,
                                offset: Offset(0.4, 0),
                              ),
                              Shadow(
                                color: SlantChip.accent,
                                offset: Offset(-0.4, 0),
                              ),
                            ]
                          : const [],
                    ),
                    child: Text(option.label, maxLines: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Clear glass pill built from the bottom nav bar's recipe (backdrop blur,
/// thin white rim, top-lit sheen, 1px highlight along the top edge), but
/// with a near-transparent tint so the page shows through instead of
/// turning grey. Text follows the theme ink so it stays readable.
class _GlassCaption extends StatelessWidget {
  const _GlassCaption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final bool dark = ThemeService.instance.isDark;
    final Color ink = dark ? Colors.white : const Color(0xFF111111);
    const radius = BorderRadius.all(Radius.circular(100));

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Stack(
          children: [
            Container(
              height: 30,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: radius,
                color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.black.withValues(alpha: 0.10),
                ),
              ),
              // Top-lit sheen, painted over the tint.
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.12 : 0.55),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.6],
                ),
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: AppFonts.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.6,
                  height: 1,
                  color: ink,
                ),
              ),
            ),
            // 1px highlight along the top edge, as on the nav bar.
            Positioned(
              top: 0,
              left: 10,
              right: 10,
              child: IgnorePointer(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.0),
                        Colors.white.withValues(alpha: 0.9),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
