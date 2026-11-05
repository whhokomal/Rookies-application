import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A network image with [BannerGrain] over it. The grain only appears once the
/// photo has loaded, so placeholders and failed images stay plain.
class GrainedNetworkImage extends StatelessWidget {
  const GrainedNetworkImage({
    super.key,
    required this.imageUrl,
    this.httpHeaders,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fadeInDuration = const Duration(milliseconds: 500),
    this.placeholder,
    this.errorWidget,
    this.grain = true,
  });

  final String imageUrl;
  final Map<String, String>? httpHeaders;
  final BoxFit fit;
  final Alignment alignment;
  final Duration fadeInDuration;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;

  /// False for shots on a plain background, where grain shows up as speckle.
  final bool grain;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      httpHeaders: httpHeaders,
      fit: fit,
      alignment: alignment,
      fadeInDuration: fadeInDuration,
      placeholder: placeholder,
      errorWidget: errorWidget,
      imageBuilder: grain
          ? (_, image) => Stack(
                fit: StackFit.expand,
                children: [
                  Image(image: image, fit: fit, alignment: alignment),
                  const BannerGrain(),
                ],
              )
          : null,
    );
  }
}

/// Subtle film grain over a banner, generated in code so no texture asset is
/// needed. Fills its parent and ignores touches.
class BannerGrain extends StatefulWidget {
  const BannerGrain({super.key});

  @override
  State<BannerGrain> createState() => _BannerGrainState();
}

class _BannerGrainState extends State<BannerGrain> {
  static const int _tileSize = 256;

  /// Strongest speck, out of 255. Raise for heavier grain.
  static const int _maxAlpha = 12;

  /// Physical pixels per speck; 1 is too fine to see on a high-density phone.
  static const double _speckSize = 2;

  // Built once and shared; every banner uses the same tile.
  static final Future<ui.Image> _tile = _buildTile();

  ui.Image? _image;

  /// Random black and white specks of varying strength. Plain alpha rather
  /// than a blend mode, so it looks the same on every GPU backend. Fixed seed
  /// so the texture doesn't change between launches.
  static Future<ui.Image> _buildTile() {
    final random = math.Random(7);
    final pixels = Uint8List(_tileSize * _tileSize * 4);
    for (int i = 0; i < pixels.length; i += 4) {
      final alpha = random.nextInt(_maxAlpha + 1);
      // Premultiplied, so a white speck's channels equal its alpha.
      final channel = random.nextBool() ? alpha : 0;
      pixels[i] = channel;
      pixels[i + 1] = channel;
      pixels[i + 2] = channel;
      pixels[i + 3] = alpha;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      _tileSize,
      _tileSize,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  void initState() {
    super.initState();
    _tile.then((image) {
      if (mounted) setState(() => _image = image);
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.expand();
    return IgnorePointer(
      // Its own layer, so swiping the banner underneath doesn't repaint it.
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _GrainPainter(
            image,
            _speckSize / MediaQuery.devicePixelRatioOf(context),
          ),
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter(this.tile, this.scale);

  final ui.Image tile;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.ImageShader(
          tile,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Matrix4.diagonal3Values(scale, scale, 1).storage,
        ),
    );
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) =>
      oldDelegate.tile != tile || oldDelegate.scale != scale;
}
