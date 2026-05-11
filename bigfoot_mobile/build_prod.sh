#!/usr/bin/env bash
set -euo pipefail

mkdir -p build/symbols/production

flutter clean
flutter pub get
flutter build apk --release \
  --flavor production \
  --dart-define=FLAVOR=production \
  --obfuscate \
  --split-debug-info=build/symbols/production \
  -t lib/main.dart
