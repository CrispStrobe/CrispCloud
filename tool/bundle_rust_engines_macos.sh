#!/usr/bin/env bash
# Build the optional Rust storage engines (SMB + Filen/Internxt bridges) for
# macOS and embed them in an already built CrispCloud.app so the GUI can
# select "Rust" / "Auto" without CRISP_*_LIBRARY paths.
#
#   tool/bundle_rust_engines_macos.sh build/macos/Build/Products/Release/CrispCloud.app
#
# The libraries land in Contents/Frameworks/lib<crate>.dylib, the location
# RustSmbSession / NativeRustCloudApi probe after explicit paths. Re-sign the
# app afterwards (tool/sign_macos_local.sh signs nested code), or pass
# CODESIGN_IDENTITY to sign the two dylibs here. Builds universal binaries
# when both Apple targets are installed (rustup target add x86_64-apple-darwin).
# This is a developer/qualification path; release packaging, notarization and
# the store review of these engines are separate gates.
set -euo pipefail

app="${1:-}"
if [[ -z "$app" || ! -d "$app/Contents" ]]; then
  echo "usage: $0 path/to/CrispCloud.app" >&2
  exit 64
fi
root="$(cd "$(dirname "$0")/.." && pwd)"
pkg="$root/packages/crisp_storage"
frameworks="$app/Contents/Frameworks"
mkdir -p "$frameworks"

targets=(aarch64-apple-darwin)
if rustup target list --installed 2>/dev/null | grep -qx x86_64-apple-darwin; then
  targets+=(x86_64-apple-darwin)
fi

for spec in "rust:crisp_smb_bridge" "rust_cloud:crisp_cloud_bridge"; do
  dir="${spec%%:*}"
  crate="${spec##*:}"
  inputs=()
  for target in "${targets[@]}"; do
    MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}" \
      cargo build --manifest-path "$pkg/$dir/Cargo.toml" --release --locked \
      --target "$target"
    inputs+=("$pkg/$dir/target/$target/release/lib$crate.dylib")
  done
  out="$frameworks/lib$crate.dylib"
  if [[ ${#inputs[@]} -gt 1 ]]; then
    lipo -create "${inputs[@]}" -output "$out"
  else
    cp "${inputs[0]}" "$out"
  fi
  install_name_tool -id "@rpath/lib$crate.dylib" "$out"
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --timestamp=none --sign "$CODESIGN_IDENTITY" "$out"
  fi
  echo "embedded $out ($(lipo -archs "$out"))"
done
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  echo "note: dylibs are unsigned; re-sign the app (tool/sign_macos_local.sh)." >&2
fi
