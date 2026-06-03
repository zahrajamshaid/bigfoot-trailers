import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/platform/platform_support.dart';
import '../firebase_options.dart';

class PushPayload {
  final String? type;
  final String? title;
  final String? body;
  final Map<String, dynamic> data;

  const PushPayload({
    this.type,
    this.title,
    this.body,
    this.data = const {},
  });

  factory PushPayload.fromRemoteMessage(RemoteMessage message) {
    return PushPayload(
      type: message.data['type']?.toString(),
      title: message.notification?.title ?? message.data['title']?.toString(),
      body: message.notification?.body ?? message.data['body']?.toString(),
      data: message.data,
    );
  }
}

class PushNotificationService {
  FirebaseMessaging? _messaging;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  Future<void> initialize({
    required Future<void> Function(PushPayload payload) onForeground,
    required Future<void> Function(PushPayload payload) onOpened,
  }) async {
    // Desktop + web have no FCM implementation here; live notifications on
    // those targets flow through the WebSocket channel only.
    if (!PlatformSupport.supportsFcm) {
      _messaging = null;
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }
    } catch (_) {
      // Firebase may already be initialized or not configured for this platform.
    }

    if (Firebase.apps.isEmpty) {
      _messaging = null;
      return;
    }

    _messaging = FirebaseMessaging.instance;

    await _messaging!.requestPermission(alert: true, badge: true, sound: true);
    await _messaging!.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _foregroundSub?.cancel();
    _openedSub?.cancel();

    _foregroundSub = FirebaseMessaging.onMessage.listen((m) async {
      await onForeground(PushPayload.fromRemoteMessage(m));
    });

    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((m) async {
      await onOpened(PushPayload.fromRemoteMessage(m));
    });

    final initial = await _messaging!.getInitialMessage();
    if (initial != null) {
      await onOpened(PushPayload.fromRemoteMessage(initial));
    }
  }

  Future<String?> getToken() async {
    if (!PlatformSupport.supportsFcm) return null;
    return _messaging?.getToken();
  }

  Map<String, dynamic> parsePayloadString(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
  }
}
