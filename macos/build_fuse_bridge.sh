#!/bin/sh
set -eu

source_file="$SRCROOT/fuse_bridge.c"
output_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
output_file="$output_dir/crispcloud_fuse_bridge"

mkdir -p "$output_dir"
"${CC:-clang}" -arch arm64 -arch x86_64 -std=c11 -O2 -Wall -Wextra -Werror \
  -I"$SRCROOT/vendor" "$source_file" -o "$output_file"

if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
    --timestamp=none "$output_file"
fi
