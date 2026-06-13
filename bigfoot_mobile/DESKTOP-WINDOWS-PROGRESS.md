# Windows Desktop — Phase 1 Progress

**Status: ALL PHASES COMPLETE (2026-06-13).** The Flutter app compiles to a
native Windows `.exe`, launches, connects to the live duckdns backend, raises
desktop toast notifications, and is packaged as a signed MSIX installer + a
portable ZIP ready to hand to the client (`bigfoot_mobile/dist/`). Phase
sections below: 1 = compile/launch, 2 = desktop polish, 3 = notifications,
4 = distribution. Build it with:

```powershell
pwsh bigfoot_mobile/tool/build_windows.ps1            # debug
pwsh bigfoot_mobile/tool/build_windows.ps1 --release  # release
```

Output: `build/windows/x64/runner/Debug/bigfoot_mobile.exe`.

See "Toolchain gotcha" below for why a plain `flutter build windows` fails on
this machine and what the script does about it.

Original checkpoint notes (Phase 1 was paused mid-build for a higher-priority
change) follow.

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

## Phase 1 finish — what the re-run hit and how it was resolved

Re-ran `flutter build windows --debug` and iterated to a clean build + launch.
Two blockers surfaced, neither in app code:

1. **Corrupted Firebase SDK cache.** `firebase_core` *does* have a Windows
   impl — its CMake downloads the Firebase C++ SDK zip. A truncated cached
   zip (`build/windows/x64/firebase_cpp_sdk_windows_*.zip`, ~890 KB instead
   of ~100 MB) caused `cmake -E tar: ZIP decompression failed (-5)`. Fix:
   delete the stale `build/windows` so it re-downloads. Firebase then
   compiled fine and is runtime-gated off via `PlatformSupport.supportsFcm`
   (it builds but never initializes on desktop). The `LNK4099 PDB not found`
   warnings from the prebuilt Firebase libs are harmless.

2. **Missing ATL → `error C1083: Cannot open include file: 'atlstr.h'`.**
   `flutter_secure_storage_windows` includes `<atlstr.h>`. See the toolchain
   gotcha below — this is the real story and the reason the build script
   exists.

The generated_plugins.cmake concern from the original notes turned out moot —
firebase_core compiles cleanly on Windows; no plugin needed stripping.

## Toolchain gotcha — ATL / two VS instances

This machine has **two** VS 2022 instances:
- `D:\VisualStudio` — full VS, **has** the C++ ATL component.
- `C:\Program Files (x86)\...\2022\BuildTools` — Build Tools, **no ATL**.

Flutter's own vswhere check resolves to `D:\VisualStudio`, but **CMake
independently selects BuildTools** for the actual compile. BuildTools lacks
`atlmfc\atlstr.h`, so `flutter_secure_storage_windows` fails to compile.

Things that did **not** work to redirect CMake to the ATL-equipped instance:
- `VSINSTALLDIR` env var — ignored.
- `CMAKE_GENERATOR_INSTANCE` env var alone — ignored ("…will be ignored,
  because CMAKE_GENERATOR is not set").
- `CMAKE_GENERATOR` + `CMAKE_GENERATOR_INSTANCE` together — Flutter still
  drove CMake to BuildTools.

What **does** work (and what `tool/build_windows.ps1` does): both VS instances
share the *identical* MSVC toolset version, so the ATL headers/libs are
byte-identical. The script points `cl.exe`/`link.exe` at the ATL-equipped
instance's `atlmfc` via the `CL` and `LINK` environment variables — which the
MSVC tools read directly, regardless of which instance CMake picked. No admin
needed.

**Permanent fix — APPLIED (2026-06-13).** ATL is now present in the BuildTools
instance, so a plain `flutter build windows` works with no shim (verified by a
from-scratch recompile of flutter_secure_storage_windows without CL/LINK set).
`tool/build_windows.ps1` is now just a harmless safety net (it no-ops the
injection when the selected instance already has ATL).

How it was applied (one-time, elevated — see `tool/_install_atl_elevated.ps1`):
the official VS Installer add kept returning exit 1 because the installer
wanted to self-update first ("Status changed to UpdateAvailable"). The
reliable fallback that worked: replicate the `atlmfc` folder from the
ATL-equipped instance (`D:\VisualStudio`) into BuildTools' MSVC toolset of the
SAME version (14.43.34808) — byte-identical headers/libs, so cl.exe/link.exe
find `atlstr.h` natively. To do the "registered" install instead (e.g. so a
future VS update maintains it), run the official add and re-run it once if the
first attempt updates the installer and exits 1:

```powershell
& "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" `
    modify --passive --norestart `
    --installPath "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" `
    --add Microsoft.VisualStudio.Component.VC.ATL
```

CI note for Phase 4: a clean CI runner with a full VS (ATL included) won't hit
this at all; the shim is only needed where the selected instance lacks ATL.

## Phase 2 — desktop polish (mostly DONE, 2026-06-13)

- **Responsive shell** — verified by inspection + launch. The shell
  (`app_shell.dart`) already drives a `NavigationRail` at tablet+ widths
  (`r.isTablet`, ≥600) and goes `extended` with labels at `large` (≥1240),
  which is what the default 1440×900 window gets. Routed content is centred to
  `maxContentWidth` on tablet+. Login renders correctly centred at desktop
  width. **Remaining:** a logged-in walk of every screen at desktop width
  still needs doing (blocked on test credentials — see below).
- **Mouse hover affordances — DONE.** New reusable
  [lib/shared/widgets/hover_tap.dart](lib/shared/widgets/hover_tap.dart)
  (`HoverTap`) wraps a tap target so mouse users get the click cursor; it's a
  no-op on touch platforms (no gating needed). Applied to the raw
  `GestureDetector` tap targets that lacked a cursor: the shell's brand logo,
  title, and settings avatar; the login "remember email" label; and the
  trailer-list filter chips. (Card/row taps elsewhere use `InkWell`, which
  already shows the cursor + hover highlight.)
- **Keyboard — DONE (already provided).**
  - *Enter to submit:* the login form already submits on Enter — the password
    field uses `onFieldSubmitted: (_) => _submit()` and email Enter advances
    focus. Other forms use standard `TextField` actions.
  - *Esc to close dialogs:* framework-provided. `ModalRoute` binds
    `DismissIntent` (Escape) → pop whenever `barrierDismissible` is true (the
    `showDialog` default). Dialogs intentionally created with
    `barrierDismissible: false` (forced choices) correctly ignore Esc.

### Backend — wired to the live duckdns server (2026-06-13)
`lib/core/config/app_environment.dart` now routes **desktop** builds
(`PlatformSupport.isDesktop`) to the hosted backend:
- API:  `https://bigfoot-trailers.duckdns.org/v1`
- WS:   `wss://bigfoot-trailers.duckdns.org/ws`

The old dev default (`http://10.0.2.2:3000`) is an Android-emulator host alias
that can't resolve on a Windows desktop, so desktop gets the real server
instead. Override with `--dart-define=API_BASE_URL=…` (+ `WS_URL=…`) to point a
desktop build at a local backend. TLS is standard CA validation against
duckdns's Let's Encrypt cert; cert pinning stays off unless `SSL_PIN_SHA256` is
defined at build. Verified end-to-end: login + WebSocket connect ("Connected"
in the app bar) and the dashboard loads live data.

### Phase 2 — logged-in walk-through (done) + a real bug it caught
Logged in against duckdns and walked the owner dashboard at desktop width. The
walk-through immediately surfaced a **latent crash**: the shell built the
`NavigationRail` with both `extended: true` and `labelType: all` at the
`isLarge` (≥1240px) breakpoint, which Flutter asserts against
(`navigation_rail.dart:117`). Mobile/tablet never reach that breakpoint, so
desktop was the first target to hit it. Fixed in `app_shell.dart`: the extended
rail now uses `labelType: none`; non-extended widths keep `all`/`selected`.
After the fix the extended rail (icon + inline label per destination) and the
stat-card grid render correctly with live data.

Optional future polish if needed: hover highlights on bespoke rows,
focus-traversal order on dense forms.

### Phase 3 — notifications (DONE, 2026-06-13)
- Plugin: **`local_notifier`** (Windows/macOS/Linux). Chosen over
  flutter_local_notifications for its lighter footprint and, crucially,
  `ShortcutPolicy.requireCreate` — it installs the Start Menu shortcut carrying
  an AppUserModelID that Windows requires before it will show toasts, so toasts
  work for the **portable** build too (MSIX already carries identity).
- New `lib/services/desktop_notification_service.dart` wraps it; desktop-gated
  via `PlatformSupport.isDesktop` (no-op on mobile/web), best-effort (a missed
  toast never crashes the app). Registered in the `ServiceLocator`, initialized
  (fire-and-forget) in `app.dart`.
- Wired into `NotificationsViewModel._subscribeWs`: every WebSocket event that
  becomes an in-app notification (qcFail, trailerStalled, deliveryDispatched,
  deliveryComplete, workerMessage) also raises an OS toast on desktop, so events
  are seen when the window is in the background.
- No explicit permission prompt: Windows shows toasts based on its own Focus
  Assist settings; `local_notifier` needs no runtime permission grant.
- Also gated the mobile-only root/jailbreak check (`_initializeSecurityGuards`)
  to `PlatformSupport.isMobile` so release desktop builds don't trip a
  MissingPluginException.

### Phase 4 — distribution (DONE, 2026-06-13)
- **App icon:** `flutter_launcher_icons` now has a `windows:` block; ran
  `dart run flutter_launcher_icons` to regenerate
  `windows/runner/resources/app_icon.ico` from the Bigfoot logo (visible in the
  title bar / taskbar).
- **MSIX installer + portable ZIP** — both built. The `msix` dev-dependency +
  `msix_config` in `pubspec.yaml` produce a signed `.msix`; signing uses a
  self-signed code-signing cert at `windows/packaging/bigfoot_trailers.pfx`
  (password `bigfoot`, **gitignored** — private key). The public
  `bigfoot_trailers.cer` is committed for the client to trust. Build commands:
  ```powershell
  flutter build windows --release           # portable build
  dart run msix:create                       # signed installer
  ```
  A ready-to-hand-over set is staged in `bigfoot_mobile/dist/` (gitignored):
  `BigfootTrailers-Setup.msix`, `BigfootTrailers-Portable.zip`,
  `BigfootTrailers.cer`, and `INSTALL.txt` (client instructions for both paths).
- **CI:** `.github/workflows/windows-distribute.yml` (mirrors
  android-distribute.yml) — `workflow_dispatch`, builds `flutter build windows
  --release` with duckdns dart-defines, always uploads the portable ZIP, and
  builds+uploads the MSIX when the `WINDOWS_MSIX_PFX_BASE64` /
  `WINDOWS_MSIX_PASSWORD` secrets are set. GitHub's windows-latest runner has
  ATL, so the local atlstr.h shim isn't needed there.

To regenerate the self-signed cert (e.g. on another machine), see
`windows/packaging/` and the `New-SelfSignedCertificate` command in the project
history; subject must stay `CN=Bigfoot Trailers` to match `msix_config.publisher`.

## How to resume / rebuild

All four phases are complete. To produce a fresh client build:

1. `cd bigfoot_mobile`
2. `pwsh tool/build_windows.ps1 --release` (or plain `flutter build windows
   --release` now that ATL is installed) — runnable
   `build/windows/x64/runner/Release/bigfoot_mobile.exe`.
3. `dart run msix:create` — signed installer.
4. Stage `dist/` (msix + zip + cer + INSTALL.txt) and hand to the client.

Earlier phase notes (kept for context):

1. `cd bigfoot_mobile`
2. `pwsh tool/build_windows.ps1` — produces and you can launch
   `build/windows/x64/runner/Debug/bigfoot_mobile.exe`.
3. Log in against `https://bigfoot-trailers.duckdns.org` and walk the
   dashboard, verifying the responsive shell at desktop widths
   (NavigationRail, breakpoints) and that secure_storage / login / live
   WebSocket updates all work on Windows.
4. Then tackle the Phase 2 polish items above (hover affordances, keyboard
   shortcuts).
