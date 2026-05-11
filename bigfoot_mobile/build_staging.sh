#!/usr/bin/env bash
set -euo pipefail

mkdir -p build/symbols/staging

flutter clean
flutter pub get
flutter build apk --release \
  --flavor staging \
  --dart-define=FLAVOR=staging \
  --obfuscate \
  --split-debug-info=build/symbols/staging \
  -t lib/main.dart
