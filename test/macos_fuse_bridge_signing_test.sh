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
CRISP_BUILD_PROFILE=github DART_DEFINES=Q1JJU1BfRElTVFJJQlVUSU9OPWdpdGh1Yg==,Q1JJU1BfRU5BQkxFX0ZVU0U9dHJ1ZQ== SRCROOT="$root/macos" TARGET_BUILD_DIR="$fixture" \
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
    'com.apple.security.cs.disable-library-validation': True,
    # Shared with the File Provider extension; release signing expands the prefix.
    'com.apple.security.application-groups': ['$(TeamIdentifierPrefix)crispcloud'],
}
assert actual == expected, f'Unexpected helper entitlements: {actual}'
PYENTS
lipo "$helper" -verify_arch arm64 x86_64
echo 'Universal direct-distribution FUSE helper signature verified'

# Rebuilding with defaults must remove the previously opted-in generated helper.
SRCROOT="$root/macos" TARGET_BUILD_DIR="$fixture" \
  UNLOCALIZED_RESOURCES_FOLDER_PATH=Resources DART_DEFINES= \
  sh "$root/macos/build_fuse_bridge.sh"
[[ ! -e "$helper" ]] || { echo 'Default build retained an optional FUSE helper'; exit 1; }
echo 'Default build excludes the optional helper, including after an opt-in build'
