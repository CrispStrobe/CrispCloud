#!/usr/bin/env bash
set -euo pipefail
source /workspace/scratch/1e19fe1d39ae/toolchains/env.sh
cd "$CRISP_TOOLCHAIN_ROOT"
mkdir -p receipts/logs
flutter/bin/cache/dart-sdk/bin/dart pub cache preload flutter/.pub-preload-cache/*.tar.gz > receipts/logs/sdk-cache-preload.log 2>&1
flutter/bin/cache/dart-sdk/bin/dart pub --directory flutter/packages/flutter_tools get --offline > receipts/logs/sdk-pub-offline.log 2>&1
flutter --no-version-check --suppress-analytics precache --linux --no-android --no-ios --no-web --no-macos --no-windows --verbose > receipts/logs/flutter-precache-linux.log 2>&1
flutter --no-version-check --suppress-analytics --version --machine > receipts/flutter-version.json
flutter/bin/cache/dart-sdk/bin/dart --version > receipts/dart-version.txt 2>&1
ldd flutter/bin/cache/artifacts/engine/linux-x64/flutter_tester > receipts/flutter-tester-ldd.txt
python3 setup_probes.py
