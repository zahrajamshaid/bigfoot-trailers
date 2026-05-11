#!/usr/bin/env bash
set -euo pipefail

flutter clean
flutter pub get
flutter build apk --release \
  --flavor development \
  --dart-define=FLAVOR=development \
  -t lib/main.dart
