import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rookies_jeans/services/notification_service.dart';
import 'package:video_player/video_player.dart';

/// Plays assets/Splashscreen.mp4 full screen once, then opens home. If the
/// video can't be played, or stalls, home opens anyway after a timeout.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// App start-up work (sign-in, theme) begun in main(); home opens only
  /// once it has finished, so the video plays while it runs.
  static Future<void> startup = Future.value();

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const String _videoAsset = 'assets/Splashscreen.mp4';

  /// The video opens on ~0.6s of solid black; start just before the logo
  /// fades in.
  static const Duration _videoStart = Duration(milliseconds: 550);

  /// Upper bound on the splash, in case the video never starts or ends.
  static const Duration _maxDuration = Duration(seconds: 8);

  late final VideoPlayerController _controller;
  Timer? _fallback;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _fallback = Timer(_maxDuration, _goHome);
    _controller = VideoPlayerController.asset(_videoAsset);
    _controller.addListener(_onVideoTick);
    _controller.initialize().then((_) async {
      if (!mounted) return;
      await _controller.setVolume(0);
      await _controller.seekTo(_videoStart);
      if (!mounted) return;
      setState(() {});
      await _controller.play();
    }).catchError((Object e) {
      debugPrint('SplashScreen: video failed ($e)');
      _goHome();
    });
  }

  void _onVideoTick() {
    final value = _controller.value;
    if (value.hasError) {
      _goHome();
      return;
    }
    if (value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration) {
      _goHome();
    }
  }

  Future<void> _goHome() async {
    if (_done || !mounted) return;
    _done = true;
    _fallback?.cancel();
    // Normally already done by the time the video ends.
    try {
      await SplashScreen.startup.timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('SplashScreen: start-up not finished ($e)');
    }
    if (!mounted) return;
    context.go('/home');
    // Opened by tapping a notification: show what it was about.
    final link = NotificationService.instance.takePendingLink();
    if (link != null) NotificationService.instance.openLink?.call(link);
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _controller.removeListener(_onVideoTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      // Black like the native launch screen and the video's opening frame,
      // so there's no flash before the video starts.
      backgroundColor: Colors.black,
      body: value.isInitialized
          ? SizedBox.expand(
              // Portrait video; cover fills any screen shape, trimming the
              // edges rather than letterboxing.
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: value.size.width,
                  height: value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
