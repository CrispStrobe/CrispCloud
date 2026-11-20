#!/usr/bin/env bash
# Local builds must keep the app's persistent Keychain identity before launch.
# Usage: bash tool/build_macos_local.sh [--debug|--profile|--release] [--launch] [Flutter build arguments...]
set -euo pipefail
cd "$(dirname "$0")/.."
MODE=release
CONFIGURATION=Release
LAUNCH=false
BUILD_ARGS=()
for argument in "$@"; do
  case "$argument" in
    --debug) MODE=debug; CONFIGURATION=Debug ;;
    --profile) MODE=profile; CONFIGURATION=Profile ;;
    --release) MODE=release; CONFIGURATION=Release ;;
    --launch) LAUNCH=true ;;
    *) BUILD_ARGS+=("$argument") ;;
  esac
done
APP="$PWD/build/macos/Build/Products/$CONFIGURATION/CrispCloud.app"
while IFS= read -r executable; do
  if [[ "$executable" = "$APP/Contents/MacOS/CrispCloud" ]]; then
    echo "This build's app is running. Preserve its open work and use a separate checkout or close it before rebuilding." >&2
    exit 1
  fi
done < <(ps -axo comm=)
# Fail before compilation if a usable persistent identity/profile is missing.
SIGNING_CONFIGURATION="$CONFIGURATION" bash tool/sign_macos_local.sh --check
VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1)"
REVISION="$(git rev-parse --short HEAD)"
flutter build macos "--$MODE" \
  --dart-define="APP_VERSION=$VERSION" \
  --dart-define="GIT_HASH=$REVISION" \
  ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}
SIGNING_CONFIGURATION="$CONFIGURATION" bash tool/sign_macos_local.sh "$APP"
EXPECTED_IDENTITY="=anchor apple generic and identifier \"com.CrispStrobe.cloud\" and certificate leaf[subject.OU] = \"${TEAM:-N9XSJ4M3GT}\""
codesign --verify --deep --strict --test-requirement "$EXPECTED_IDENTITY" "$APP"
if $LAUNCH; then open -n "$APP"; fi
printf 'Stable-signed local app: %s\n' "$APP"
