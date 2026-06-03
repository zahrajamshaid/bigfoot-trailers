import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'app.dart';
import 'core/platform/platform_support.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // Ignore initialization errors on unsupported platforms/configurations.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase Messaging only has Android + iOS implementations here.
  // Skipping on web and desktop keeps the app runnable in Chrome and on
  // Windows; live in-app push there flows through the WebSocket channel.
  if (PlatformSupport.supportsFcm) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
  runApp(const BigfootApp());
}
