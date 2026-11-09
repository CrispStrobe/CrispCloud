#!/usr/bin/env bash
# Prime dart_smb2's content-addressed Apple asset cache from the repository's
# exact upstream mirror. GitHub's release CDN intermittently returns HTTP 504
# for the upstream asset; `gh release download` uses the API and is reliable in
# Actions. The SHA-256 values are the ones pinned by dart_smb2 0.2.1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/.dart_tool/hooks_runner/shared/dart_smb2/build"
RELEASE="dart-smb2-libsmb2-r9"
SQLITE_RELEASE="ci-native-assets-20261109"
REPO="CrispStrobe/CrispCloud"
SQLITE_CACHE="$ROOT/.dart_tool/hooks_runner/shared/sqlite3/build"

fetch() {
  local asset="$1" expected="$2" dest tmp
  dest="$CACHE/$expected/$asset"
  if [[ -f "$dest" ]] && printf '%s  %s\n' "$expected" "$dest" | shasum -a 256 -c - >/dev/null 2>&1; then
    echo "dart_smb2 cache: $asset already present"
    return
  fi
  mkdir -p "$CACHE/$expected"
  tmp="$dest.tmp.$$"
  gh release download "$RELEASE" --repo "$REPO" --pattern "$asset" --output "$tmp" --clobber
  printf '%s  %s\n' "$expected" "$tmp" | shasum -a 256 -c -
  mv "$tmp" "$dest"
  echo "dart_smb2 cache: primed $asset"
}

fetch libsmb2_ios.xcframework.zip a1f0b15bf0f173165e36abcfcea3b944f469fc2c7e3bd2b6d3d16df7a6c38f63
fetch libsmb2_macos.xcframework.zip 922defa3509e550d32d66d7e8f84ef95ddf53fb9bb96a8ff85e01537765129e6

fetch_sqlite() {
  local asset="$1" expected="$2" dir="$3" dest tmp
  dest="$SQLITE_CACHE/$dir/libsqlite3.dylib"
  if [[ -f "$dest" ]] && printf '%s  %s\n' "$expected" "$dest" | shasum -a 256 -c - >/dev/null 2>&1; then
    echo "sqlite3 cache: $asset already present"
    return
  fi
  mkdir -p "$SQLITE_CACHE/$dir"
  tmp="$dest.tmp.$$"
  gh release download "$SQLITE_RELEASE" --repo "$REPO" --pattern "$asset" --output "$tmp" --clobber
  printf '%s  %s\n' "$expected" "$tmp" | shasum -a 256 -c -
  mv "$tmp" "$dest"
  echo "sqlite3 cache: primed $asset"
}

fetch_sqlite libsqlite3.arm64.ios.dylib d14af900727328a6ae064217003618a7a860c79ac5bb1cab13334e249e7a4b6d download-13d4454f
fetch_sqlite libsqlite3.arm64.macos.dylib 71074bec684ce243031c34ba16314dcfc39efefa77e72cc95f19b446b224254f download-42619d6
