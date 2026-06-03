import 'package:flutter/foundation.dart';

/// Capability flags for plugins that aren't available on every target.
///
/// Built on top of [kIsWeb] + [defaultTargetPlatform] so the checks themselves
/// are safe to read on web (where importing `dart:io` would crash) and on
/// Windows desktop (where mobile-only plugins like firebase_messaging,
/// permission_handler, and flutter_pdfview have no implementation).
abstract final class PlatformSupport {
  static bool get isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// firebase_messaging only has Android + iOS implementations in our setup.
  /// On web and desktop it must be skipped entirely — calling it throws.
  static bool get supportsFcm => isMobile;

  /// permission_handler ships native implementations for Android + iOS only.
  /// Desktop targets handle permissions through the OS-level file/camera
  /// dialogs themselves, so the plugin must not be invoked.
  static bool get supportsPermissionHandler => isMobile;

  /// flutter_pdfview embeds a mobile native PDF view (PDFKit on iOS,
  /// AndroidPdfViewer on Android). On desktop we open the file with the OS
  /// default PDF handler via url_launcher instead.
  static bool get supportsInAppPdfView => isMobile;
}
