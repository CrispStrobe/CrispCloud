#!/bin/sh
set -eu

source_file="$SRCROOT/fuse_bridge.c"
output_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
output_file="$output_dir/crispcloud_fuse_bridge"

# Validate Dart/native profile agreement before compiling or retaining a helper.
rm -f "$output_file" "$output_dir/CrispDistribution.json"
fuse_enabled=$(python3 "$SRCROOT/../tool/macos_distribution.py" stage)
helper_entitlements="$SRCROOT/Runner/FuseBridge.entitlements"
if [ "${CRISP_BUILD_PROFILE:-appstore}" = github ]; then
  helper_entitlements="$SRCROOT/Runner/DirectFuse.entitlements"
fi
if [ "$fuse_enabled" != true ]; then
  # Incremental builds must not retain a helper from an earlier opt-in build.
  rm -f "$output_file"
  echo 'Optional macFUSE/FUSE-T helper excluded (CRISP_ENABLE_FUSE is false)'
  exit 0
fi
mkdir -p "$output_dir"
"${CC:-clang}" -arch arm64 -arch x86_64 -std=c11 -O2 -Wall -Wextra -Werror \
  -I"$SRCROOT/vendor" "$source_file" -o "$output_file"

if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
    --options runtime --entitlements "$helper_entitlements" \
    --timestamp=none "$output_file"
fi
