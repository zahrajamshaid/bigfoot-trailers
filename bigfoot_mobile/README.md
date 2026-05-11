# Bigfoot Mobile

Production management app for Bigfoot Trailers.

## Flavors

- `development`
- `staging`
- `production`

Environment mapping is handled by `FLAVOR` in `lib/core/config/app_environment.dart`.

Default endpoints:

- Development API: `http://localhost:3000/v1`
- Development WS: `ws://localhost:3000/ws`
- Staging API: `https://staging-api.bigfoottrailers.com/v1`
- Staging WS: `wss://staging-api.bigfoottrailers.com/ws`
- Production API: `https://api.bigfoottrailers.com/v1`
- Production WS: `wss://api.bigfoottrailers.com/ws`

You can override with dart defines:

- `--dart-define=API_BASE_URL=...`
- `--dart-define=WS_URL=...`
- `--dart-define=SSL_PIN_SHA256=<sha256_fingerprint[,sha256_fingerprint...]>`

## Build Scripts

- `build_dev.sh`
- `build_staging.sh`
- `build_prod.sh`

These scripts build release APKs with the matching flavor and `FLAVOR` define.
Staging and production scripts also enable obfuscation and split debug symbols.

## Android Signing

1. Copy `android/key.properties.example` to `android/key.properties`.
2. Fill in keystore values.
3. Place your keystore file at the configured path.

If `android/key.properties` is missing, release builds fall back to debug signing.

## Security Controls

- Rooted-device block in production flavor.
- Secure screenshot blocking for payroll screens.
- Optional SSL pinning through `SSL_PIN_SHA256` dart define.

## Firebase

- FCM token registration on login is enabled.
- Background message handler is wired.
- Android notification channel: `Bigfoot Alerts` (`bigfoot_alerts`).

## Native Assets

- Launcher icons generated via `flutter_launcher_icons`.
- Android splash generated via `flutter_native_splash`.

