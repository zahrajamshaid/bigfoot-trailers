# Windows Desktop — Phase 1 Progress

Snapshot of what was done to make the Flutter mobile app compile and launch
as a native Windows `.exe`. Pivoted away mid-build to handle a higher-
priority change, so this is checkpoint, not done.

## Decisions made

- **Target**: native Windows `.exe` via `flutter build windows`. (Previously
  considered PWA — switched to native at user request.)
- **Notifications**: real-time while app is open, fed by the existing
  WebSocket channel (`WsClient`). FCM stays mobile-only; on Windows we'll
  surface live events via a Windows-toast plugin (planned Phase 3, not
  done in Phase 1).
- **Phasing**: keep work iterative so each phase ends in a runnable state.
  Phase 1 = compile + launch only. Don't try to ship every feature in one
  shot.

## Inventory at start

- `bigfoot_mobile/windows/` already scaffolded by an earlier
  `flutter create --platforms=windows`; runner + CMakeLists in place.
- `flutter devices` lists Windows desktop as a connected device (Win11,
  Flutter 3.32.8, desktop already enabled).
- Mobile-only plugins identified as blockers:
  - `firebase_messaging` — no Windows native impl
  - `firebase_core` — only initialized for FCM, so gated alongside it
  - `permission_handler` — no Windows native impl
  - `flutter_pdfview` — no Windows native impl
- Plugins that *do* work on Windows and need no change:
  `dio`, `socket_io_client`, `flutter_secure_storage` (9.x+),
  `share_plus`, `path_provider`, `connectivity_plus`, `url_launcher`,
  `geolocator` (Win32 backend), `image_picker` (file-dialog fallback),
  `file_picker`, `shared_preferences`, `crypto`, `uuid`.

## Changes shipped

### Windows runner cosmetics

[bigfoot_mobile/windows/runner/main.cpp](windows/runner/main.cpp)
- Window title: `"bigfoot_mobile"` → `"Bigfoot Trailers"`
- Default origin: `(10, 10)` → `(100, 100)`
- Default size: `1280 × 720` → `1440 × 900`

[bigfoot_mobile/windows/runner/Runner.rc](windows/runner/Runner.rc)
- `CompanyName`: `"com.bigfoottrailers"` → `"Bigfoot Trailers"`
- `FileDescription`: `"bigfoot_mobile"` → `"Bigfoot Trailers Production Management"`
- `LegalCopyright`: company name normalized
- `ProductName`: `"bigfoot_mobile"` → `"Bigfoot Trailers"`

### Platform capability helper

New: [bigfoot_mobile/lib/core/platform/platform_support.dart](lib/core/platform/platform_support.dart)
- `PlatformSupport.isMobile` / `isDesktop` / `isWindows`
- Feature flags read at call sites:
  - `supportsFcm` — gates firebase_messaging
  - `supportsPermissionHandler` — gates permission_handler
  - `supportsInAppPdfView` — gates flutter_pdfview's `PDFView` widget
- Built on `kIsWeb` + `defaultTargetPlatform` so the file itself is safe
  to read on every target (no `dart:io` import).

### Plugin gating

[bigfoot_mobile/lib/main.dart](lib/main.dart)
- `Firebase.initializeApp` + `FirebaseMessaging.onBackgroundMessage` now
  fire only when `PlatformSupport.supportsFcm` is true.
- Was previously gated on `!kIsWeb`; the new check correctly skips
  desktop too.

[bigfoot_mobile/lib/services/push_notification_service.dart](lib/services/push_notification_service.dart)
- `initialize(...)`: early-returns on non-mobile targets.
- `getToken()`: returns null on non-mobile targets.
- Dart import lines preserved — the plugin's Dart API is platform-
  neutral and only the *calls* are guarded.

[bigfoot_mobile/lib/core/camera/camera_service.dart](lib/core/camera/camera_service.dart)
- `_ensureCameraPermission` / `_ensureGalleryPermission`: return true
  on desktop, trusting `image_picker`'s built-in OS file dialog to
  handle picker-level permissions.
- `_currentPosition`: returns null on desktop (no permission_handler
  to gate the GPS request). Photo GPS-tagging is a phone-capture
  nicety; desktop users aren't capturing photos on the floor anyway.

[bigfoot_mobile/lib/shared/widgets/pdf_viewer_screen.dart](lib/shared/widgets/pdf_viewer_screen.dart)
- Body conditionally renders:
  - mobile → `PDFView(filePath: ...)` (as before)
  - desktop → `_DesktopPdfPlaceholder` (new) which calls
    `url_launcher` with `LaunchMode.externalApplication` to hand the
    file off to the user's default PDF reader (Edge / Adobe / etc.).
  - includes a "Reopen" button for races + a small file-path readout.

## What's NOT done yet

### Phase 1 remaining
- `flutter build windows --debug` was started, then stopped when this
  pivot landed. Need to re-run, watch for compile errors, and iterate.
  Likely candidates if it fails:
  - any remaining `dart:io` usage that assumes POSIX paths
  - plugins I missed in the inventory (haven't grepped exhaustively)
  - the firebase plugin's CMake might still try to register itself —
    if so, conditionally remove from
    `bigfoot_mobile/windows/flutter/generated_plugins.cmake`
    after `pub get` regenerates it.

### Phase 2 (after Phase 1 passes)
- Verify the existing responsive shell behaves at desktop widths
  (`Breakpoints.expanded` = 1240, `large` = beyond). NavigationRail
  should already kick in at tablet+, but layouts on each screen need
  walk-through verification.
- Mouse hover affordances on tappable rows / cards
  (`MouseRegion(cursor: SystemMouseCursors.click)`).
- Keyboard: Enter to submit forms, Esc to close dialogs.

### Phase 3 (notifications)
- Add `flutter_local_notifications` (full Windows toast support) or
  `local_notifier` (lighter, Windows + macOS + Linux). Wire it to
  `NotificationsViewModel._subscribeWs` so every event that today
  surfaces as an in-app snackbar also fires a Windows toast.
- Request notification permission on first sign-in via the Windows
  Action Center prompt (handled by the plugin).

### Phase 4 (distribution)
- App icon (`windows/runner/resources/app_icon.ico` already in place;
  replace with the Bigfoot logo at the right multi-resolution
  embedded sizes).
- MSIX installer or a simpler zipped portable build.
- CI workflow analogous to `.github/workflows/android-distribute.yml`
  but for `flutter build windows --release` + artifact upload.

## How to resume

1. `cd bigfoot_mobile`
2. `flutter pub get` (already done at checkpoint — clean run)
3. `flutter build windows --debug` — log to a file and inspect first
   error.
4. If a Windows-incompatible plugin compiles in, find its
   `pubspec.yaml` `platforms:` block and add a conditional pubspec
   override only if absolutely needed. The current gating handles
   the runtime side; the build error (if any) is the plugin's
   `windows/CMakeLists.txt` not existing.
5. Once it launches: log in against
   `https://bigfoot-trailers.duckdns.org` and walk the dashboard.
