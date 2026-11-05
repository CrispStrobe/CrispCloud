#!/usr/bin/env bash
# Builds and inspects a disposable helper; never launches an app or mounts FUSE.
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Skipping macOS FUSE helper signing on this platform'
  exit 0
fi
root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/cc-fuse-signing.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
SRCROOT="$root/macos" TARGET_BUILD_DIR="$fixture" \
  UNLOCALIZED_RESOURCES_FOLDER_PATH=Resources \
  EXPANDED_CODE_SIGN_IDENTITY=- sh "$root/macos/build_fuse_bridge.sh"
helper="$fixture/Resources/crispcloud_fuse_bridge"
codesign --verify --all-architectures --strict "$helper"
codesign -d --entitlements :- "$helper" 2>/dev/null > "$fixture/entitlements.plist"
python3 - "$fixture/entitlements.plist" <<'PYENTS'
import plistlib
import sys

with open(sys.argv[1], 'rb') as source:
    actual = plistlib.load(source)
expected = {
    'com.apple.security.app-sandbox': True,
    'com.apple.security.inherit': True,
}
assert actual == expected, f'Unexpected helper entitlements: {actual}'
PYENTS
lipo "$helper" -verify_arch arm64 x86_64
echo 'Universal FUSE helper signature and sandbox inheritance verified'
