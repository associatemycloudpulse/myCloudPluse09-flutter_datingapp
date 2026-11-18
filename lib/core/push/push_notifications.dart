import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';

/// Holds a launch payload from a killed-state notification tap until the
/// router is ready.
class PendingPushNavigation {
  static String? payload;
}

/// Top-level background handler (app killed / background isolate).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty && DefaultFirebaseOptions.isConfigured) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } catch (error, stack) {
    debugPrint('FCM background Firebase init failed: $error\n$stack');
  }
  await PushNotifications.showFromRemoteMessage(message);
}

/// FCM + local notifications for killed / background delivery.
class PushNotifications {
  PushNotifications._();

  static final _local = FlutterLocalNotificationsPlugin();
  static var _ready = false;
  static var _firebaseReady = false;
  static String? _token;
  static void Function(String token)? onTokenRefresh;

  static String? get token => _token;
  static bool get isFirebaseReady => _firebaseReady;

  static const _messagesChannel = AndroidNotificationDetails(
    'dating_cloud_messages',
    'Messages',
    channelDescription: 'New matches and messages',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
  );

  static const _callsChannel = AndroidNotificationDetails(
    'dating_cloud_calls',
    'Calls',
    channelDescription: 'Incoming voice and video calls',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.call,
    fullScreenIntent: true,
    playSound: true,
    enableVibration: true,
    visibility: NotificationVisibility.public,
  );

  static Future<void> initialize() async {
    await _prepareLocal();
    if (!DefaultFirebaseOptions.isConfigured) {
      debugPrint(
        'FCM disabled: set FIREBASE_PROJECT_ID / API_KEY / APP_ID / '
        'MESSAGING_SENDER_ID in .env (and add android/app/google-services.json).',
      );
      return;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (Platform.isIOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      await messaging.setAutoInitEnabled(true);
      // Backend POST /devices expects a classic FCM registration token.
      // ignore: deprecated_member_use
      _token = await messaging.getToken();
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen((value) {
        _token = value;
        onTokenRefresh?.call(value);
      });

      FirebaseMessaging.onMessage.listen(showFromRemoteMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        PendingPushNavigation.payload = _payloadFor(initial);
      }
      _firebaseReady = true;
      debugPrint('FCM ready. token=${_token == null ? "null" : "present"}');
    } catch (error, stack) {
      debugPrint('FCM init failed: $error\n$stack');
      _firebaseReady = false;
    }
  }

  static Future<String?> resolvePushToken() async {
    if (_token != null && _token!.isNotEmpty) return _token;
    if (!_firebaseReady) return null;
    try {
      // ignore: deprecated_member_use
      _token = await FirebaseMessaging.instance.getToken();
    } catch (_) {}
    return _token;
  }

  static Future<void> _prepareLocal() async {
    if (_ready) return;
    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'dating_cloud_messages',
        'Messages',
        description: 'New matches and messages',
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'dating_cloud_calls',
        'Calls',
        description: 'Incoming voice and video calls',
        importance: Importance.max,
      ),
    );
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        PendingPushNavigation.payload = payload;
      },
    );
    await android?.requestNotificationsPermission();
    _ready = true;
  }

  static Future<void> showFromRemoteMessage(RemoteMessage message) async {
    await _prepareLocal();
    final data = message.data;
    final type = (data['type'] ?? data['event'] ?? '').toString().toLowerCase();
    final isMissed =
        type.contains('missed') ||
        (data['callStatus']?.toString().toUpperCase() == 'MISSED');
    final isCall =
        type.contains('call') ||
        data.containsKey('callId') ||
        data['notificationType'] == 'CALL' ||
        isMissed;
    final callKind = (data['callType'] ?? data['type'] ?? 'call')
        .toString()
        .toLowerCase()
        .contains('video')
        ? 'video'
        : 'voice';
    final title =
        message.notification?.title ??
        (isMissed
            ? 'Missed $callKind call'
            : isCall
            ? 'Incoming $callKind call'
            : (data['title']?.toString() ?? 'Dating Cloud'));
    final body =
        message.notification?.body ??
        data['body']?.toString() ??
        data['preview']?.toString() ??
        (isMissed
            ? 'Tap to open chat'
            : isCall
            ? 'Tap to answer'
            : 'You have a new notification');
    final payload = _payloadFor(message);
    final id = (payload ?? type).hashCode & 0x7fffffff;
    await _local.show(
      id: id == 0 ? 2 : id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: isCall ? _callsChannel : _messagesChannel,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  static void _onOpened(RemoteMessage message) {
    PendingPushNavigation.payload = _payloadFor(message);
  }

  static String? _payloadFor(RemoteMessage message) {
    final data = message.data;
    final callId = data['callId']?.toString();
    if (callId != null && callId.isNotEmpty) return 'call:$callId';
    final conversationId =
        data['conversationId']?.toString() ?? data['conversation_id']?.toString();
    if (conversationId != null && conversationId.isNotEmpty) {
      return conversationId;
    }
    return data['payload']?.toString();
  }
}
