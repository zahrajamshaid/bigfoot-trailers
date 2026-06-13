import 'package:local_notifier/local_notifier.dart';

import '../core/platform/platform_support.dart';

/// Surfaces live events as native OS toast notifications on desktop
/// (Windows/macOS/Linux).
///
/// Mobile uses FCM + in-app banners; web has no equivalent. On those targets
/// every method here is a no-op, so call sites don't need to branch.
///
/// On Windows, the OS only displays toasts for an app that has a Start Menu
/// shortcut carrying an AppUserModelID. [ShortcutPolicy.requireCreate] makes
/// `local_notifier` create that shortcut on first run, so toasts work for the
/// portable (unpackaged) build as well as the MSIX one.
class DesktopNotificationService {
  bool _ready = false;

  Future<void> initialize() async {
    if (!PlatformSupport.isDesktop || _ready) return;
    await localNotifier.setup(
      appName: 'Bigfoot Trailers',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    _ready = true;
  }

  /// Shows a toast. Silently does nothing on non-desktop targets or before
  /// [initialize] has completed — a missed toast must never crash the app.
  Future<void> show({required String title, required String body}) async {
    if (!_ready || !PlatformSupport.isDesktop) return;
    if (title.isEmpty && body.isEmpty) return;
    try {
      await LocalNotification(title: title, body: body).show();
    } catch (_) {
      // Toast delivery is best-effort; the in-app notification centre is the
      // source of truth, so swallow any OS-level failure.
    }
  }
}
