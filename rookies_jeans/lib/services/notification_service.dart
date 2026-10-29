import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/services/shopify_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Push notifications. The app only reports what the customer does (cart
/// changes, checkout, products viewed, wishlist); notification_worker/
/// decides what to send and when, and sends it through Firebase.
///
/// Everything here is best effort: a failure is logged and never shown to
/// the customer or allowed to break the flow that reported it.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _installIdKey = 'notifications_install_id';
  static const String _askedKey = 'notifications_permission_asked';

  /// Android channels; the worker picks one per message.
  static const _ordersChannel = AndroidNotificationChannel(
    'orders', 'Order updates',
    description: 'Order confirmation, shipping and delivery',
    importance: Importance.high,
  );
  static const _offersChannel = AndroidNotificationChannel(
    'offers', 'Offers and reminders',
    description: 'New drops, sales, cart and wishlist reminders',
    importance: Importance.defaultImportance,
  );

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String? _installId;

  /// Opens an in-app path such as `/products/<handle>`. Set by main.dart.
  void Function(String link)? openLink;

  /// Link from the notification that launched the app, waiting for the
  /// splash screen to finish.
  String? _pendingLink;

  /// Returns the launch notification's link once, or null.
  String? takePendingLink() {
    final link = _pendingLink;
    _pendingLink = null;
    return link;
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('[Notifications] $msg');
  }

  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      final prefs = await SharedPreferences.getInstance();
      _installId = prefs.getString(_installIdKey) ?? _newInstallId();
      await prefs.setString(_installIdKey, _installId!);

      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          // Firebase asks for permission on iOS; don't ask twice.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => _open(r.payload),
      );
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_ordersChannel);
      await android?.createNotificationChannel(_offersChannel);

      final messaging = FirebaseMessaging.instance;
      // iOS shows pushes that arrive while the app is open by itself;
      // Android needs the local notification below.
      await messaging.setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true);
      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data['link']));
      // The worker sends to FCM registration tokens. firebase_messaging 17
      // deprecates them in favour of installation IDs, but tokens are what
      // the FCM HTTP v1 send API takes, so keep them until it moves.
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen((_) => register());

      final launch = await messaging.getInitialMessage();
      _pendingLink = launch?.data['link'] as String?;

      _ready = true;
      // Already allowed (asked on an earlier launch): keep the worker's
      // token and sign-in state fresh.
      final settings = await messaging.getNotificationSettings();
      if (_isAllowed(settings.authorizationStatus)) unawaited(register());
    } catch (e) {
      _log('initialize failed: $e');
    }
  }

  /// Asks for permission the first time it's called (call it at a moment
  /// the customer sees the value: after adding to cart or wishlist, after
  /// signing in), then registers this install with the worker.
  Future<void> requestPermission() async {
    if (!_ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_askedKey) ?? false) return;
      await prefs.setBool(_askedKey, true);
      final settings = await FirebaseMessaging.instance.requestPermission();
      _log('permission: ${settings.authorizationStatus}');
      await register();
    } catch (e) {
      _log('requestPermission failed: $e');
    }
  }

  /// Sends this install's push token and signed-in customer to the worker.
  Future<void> register() async {
    if (!_ready) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.getNotificationSettings();
      final allowed = _isAllowed(settings.authorizationStatus);
      if (Platform.isIOS && allowed) {
        // The FCM token needs the APNs token, which can arrive a moment late.
        for (var i = 0; i < 5 && await messaging.getAPNSToken() == null; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      // ignore: deprecated_member_use
      final token = allowed ? await messaging.getToken() : null;
      await _post('register', {
        'fcmToken': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'enabled': allowed,
        'customerAccessToken':
            await ShopifyAuthService.instance.getSavedCustomerToken(),
      });
    } catch (e) {
      _log('register failed: $e');
    }
  }

  /// Reports one customer action to the worker (see the event list at the
  /// top of notification_worker/src/index.js).
  void track(String type, [Map<String, Object?> data = const {}]) {
    if (!_ready) return;
    unawaited(_post('event', {'type': type, 'data': data}));
  }

  Future<void> _post(String path, Map<String, Object?> body) async {
    try {
      final res = await http
          .post(
            Uri.parse('${ShopifyConstants.notificationsUrl}/$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'installId': _installId, ...body}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) _log('$path → ${res.statusCode} ${res.body}');
    } catch (e) {
      _log('$path failed: $e');
    }
  }

  void _showForeground(RemoteMessage message) {
    final n = message.notification;
    if (n == null || !Platform.isAndroid) return;
    final channel = n.android?.channelId == _ordersChannel.id
        ? _ordersChannel
        : _offersChannel;
    _local.show(
      id: message.hashCode,
      title: n.title,
      body: n.body,
      payload: message.data['link'] as String?,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id, channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          icon: 'ic_notification',
        ),
      ),
    );
  }

  void _open(String? link) {
    if (link == null || !link.startsWith('/')) return;
    final open = openLink;
    if (open == null) {
      _pendingLink = link;
    } else {
      open(link);
    }
  }

  static bool _isAllowed(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  static String _newInstallId() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
  }
}
