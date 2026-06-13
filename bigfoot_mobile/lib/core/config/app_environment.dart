import 'package:flutter/foundation.dart';

import '../platform/platform_support.dart';

enum AppFlavor {
  development,
  staging,
  production,
}

class AppEnvironment {
  static const String _flavorDefine = String.fromEnvironment('FLAVOR');
  static const String _apiBaseUrlDefine = String.fromEnvironment('API_BASE_URL');
  static const String _wsUrlDefine = String.fromEnvironment('WS_URL');

  /// The live hosted backend (duckdns). Desktop builds (Windows/macOS/Linux)
  /// talk to this by default: there is no local emulator, and the
  /// Android-emulator host alias (10.0.2.2) / `localhost` dev defaults don't
  /// apply on a desktop machine. Override with `--dart-define=API_BASE_URL=...`
  /// (and `WS_URL=...`) to point a desktop build at a local backend instead.
  static const String _hostedHost = 'bigfoot-trailers.duckdns.org';

  static AppFlavor get flavor {
    switch (_flavorDefine.trim().toLowerCase()) {
      case 'development':
      case 'dev':
        return AppFlavor.development;
      case 'staging':
      case 'stage':
        return AppFlavor.staging;
      case 'production':
      case 'prod':
        return AppFlavor.production;
      default:
        // No explicit FLAVOR dart-define: assume production for release
        // builds (so the rooted-device gate stays armed) and development
        // for debug/profile builds (so engineers can run on test devices
        // without passing the flag every time).
        return kReleaseMode ? AppFlavor.production : AppFlavor.development;
    }
  }

  static String get apiBaseUrl {
    if (_apiBaseUrlDefine.isNotEmpty) return _apiBaseUrlDefine;
    if (PlatformSupport.isDesktop) return 'https://$_hostedHost/v1';
    switch (flavor) {
      case AppFlavor.development:
        return kIsWeb ? 'http://localhost:3000/v1' : 'http://10.0.2.2:3000/v1';
      case AppFlavor.staging:
        return 'https://staging-api.bigfoottrailers.com/v1';
      case AppFlavor.production:
        return 'https://api.bigfoottrailers.com/v1';
    }
  }

  static String get wsUrl {
    if (_wsUrlDefine.isNotEmpty) return _wsUrlDefine;
    if (PlatformSupport.isDesktop) return 'wss://$_hostedHost/ws';
    switch (flavor) {
      case AppFlavor.development:
        return kIsWeb ? 'ws://localhost:3000/ws' : 'ws://10.0.2.2:3000/ws';
      case AppFlavor.staging:
        return 'wss://staging-api.bigfoottrailers.com/ws';
      case AppFlavor.production:
        return 'wss://api.bigfoottrailers.com/ws';
    }
  }

  static bool get isProduction => flavor == AppFlavor.production;
}
