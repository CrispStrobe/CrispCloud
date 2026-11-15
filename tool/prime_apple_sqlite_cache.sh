#!/usr/bin/env bash
# Prime only the pinned SQLite assets. SMB is built from reviewed Rust source.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SQLITE_RELEASE="ci-native-assets-20261109"
REPO="CrispStrobe/CrispCloud"
SQLITE_CACHE="$ROOT/.dart_tool/hooks_runner/shared/sqlite3/build"

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
