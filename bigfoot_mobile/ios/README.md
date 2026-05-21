# iOS build setup

Everything that could be done from a non-Mac is already in this repo:

- `Runner/Info.plist` — permission strings, ATS local-networking, push background modes, URL schemes
- `Runner/Runner.entitlements` — `aps-environment = development` (Xcode flips it to `production` automatically when archiving with a distribution profile)
- `Podfile` — platform `iOS 13.0`, standard Flutter podhelper integration
- `project.pbxproj` — `IPHONEOS_DEPLOYMENT_TARGET = 13.0`

What still has to happen on a Mac (one-time, ~15 min):

## 1. Install toolchain

```sh
xcode-select --install               # Xcode CLI tools
sudo gem install cocoapods           # CocoaPods (if not present)
flutter pub get
cd ios && pod install && cd ..
flutter doctor                       # should show Xcode + CocoaPods green
```

## 2. Wire up signing in Xcode

```sh
open ios/Runner.xcworkspace
```

In **Runner → Signing & Capabilities**:

1. Tick **Automatically manage signing**, pick your Apple Developer **Team**.
2. Click **+ Capability → Push Notifications**. (This is what hooks `Runner.entitlements` into the project — once you do this once, Xcode wires `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` into both Debug and Release.)
3. *(Optional)* **+ Capability → Background Modes** — *Remote notifications* should already be ticked because of the Info.plist entry; double-check.

## 3. Drop in the Firebase iOS config

Firebase Messaging will crash on launch without this file.

1. <https://console.firebase.google.com> → your project → ⚙️ → *Project settings* → **Your apps** → *Add app* → iOS, with bundle ID **`com.bigfoottrailers.bigfootMobile`** (matches `project.pbxproj`).
2. Download `GoogleService-Info.plist`.
3. In Xcode, drag it into the `Runner` group → tick *Copy items if needed*, target = *Runner*.
4. Add to `.gitignore` if it contains an APNs key, otherwise commit alongside the project.
5. Upload your **APNs Authentication Key** in the same Firebase project settings (Cloud Messaging tab) so push actually delivers.

## 4. Build commands (point at the live API)

```sh
# Debug run on a connected device or Simulator
flutter run -d <device-id> \
  --dart-define=FLAVOR=production \
  --dart-define=API_BASE_URL=https://bigfoot.206-189-190-150.sslip.io/v1 \
  --dart-define=WS_URL=wss://bigfoot.206-189-190-150.sslip.io/ws

# Release IPA for TestFlight / App Store
flutter build ipa --release \
  --dart-define=FLAVOR=production \
  --dart-define=API_BASE_URL=https://bigfoot.206-189-190-150.sslip.io/v1 \
  --dart-define=WS_URL=wss://bigfoot.206-189-190-150.sslip.io/ws

# Upload — produces an .ipa under build/ios/ipa/
xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios \
  -u "<App Store Connect email>" -p "<app-specific password>"
```

## 5. Optional: per-flavor schemes

Android has `development` / `staging` / `production` flavors with distinct app names. iOS currently has a single scheme (`Runner`) — every `flutter build` produces one IPA regardless of flavor flag. To mirror the Android setup:

1. In Xcode → *Product → Scheme → Manage Schemes…* → duplicate **Runner** three times → name them `Runner-development`, `Runner-staging`, `Runner-production`.
2. In *Build Settings*, add a build configuration per flavor (`Debug-development`, `Release-development`, etc.) and an `.xcconfig` per configuration that sets `PRODUCT_BUNDLE_IDENTIFIER` (e.g. `.dev`, `.staging` suffix) and `INFOPLIST_KEY_CFBundleDisplayName`.
3. `flutter build ipa --flavor production` will then pick the matching scheme/config.

Skip this step unless the client actually wants three separately-installable apps; one scheme covers most cases.

## 6. Known gotchas

- **Permission strings are non-negotiable.** Missing `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` / `NSLocationWhenInUseUsageDescription` causes immediate crashes on first permission request. They're present in `Info.plist`; don't strip them.
- **App Transport Security** allows cleartext only to *local* networks (LAN IPs). Production must keep using HTTPS — point dart-defines at the sslip.io URL.
- **`aps-environment`** stays `development` in the source-controlled entitlements file. Xcode rewrites it during App Store archive automatically — don't hand-edit it to `production`.
- Bundle ID is **`com.bigfoottrailers.bigfootMobile`** (camelCase). Android is `com.bigfoottrailers.bigfoot_mobile` (snake_case). Keep them distinct; don't try to unify, both stores already know them.
