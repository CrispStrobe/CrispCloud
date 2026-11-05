#!/usr/bin/env bash
# Build the macOS release app with the version and git commit embedded.
#
# Usage: tool/build_macos_release.sh [extra flutter build args...]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1)"
GIT_HASH="$(git rev-parse --short HEAD)"

exec flutter build macos --release \
  --dart-define=APP_VERSION="$VERSION" \
  --dart-define=GIT_HASH="$GIT_HASH" \
  "$@"
