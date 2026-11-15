#!/bin/sh
set -eu

source_file="$SRCROOT/fuse_bridge.c"
output_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
output_file="$output_dir/crispcloud_fuse_bridge"

# One compile-time switch controls both the Dart UI and the native helper.
# Usage: flutter build macos --dart-define=CRISP_ENABLE_FUSE=true
fuse_enabled=false
saved_ifs="$IFS"
IFS=,
for encoded in ${DART_DEFINES:-}; do
  decoded=$(printf '%s' "$encoded" | /usr/bin/base64 -D 2>/dev/null || true)
  if [ "$decoded" = CRISP_ENABLE_FUSE=true ]; then fuse_enabled=true; fi
done
IFS="$saved_ifs"
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
    --entitlements "$SRCROOT/Runner/FuseBridge.entitlements" \
    --timestamp=none "$output_file"
fi
