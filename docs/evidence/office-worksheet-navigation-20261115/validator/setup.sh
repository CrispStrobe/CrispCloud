#!/usr/bin/env bash
set -euo pipefail
QUDS_SETUP_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$QUDS_SETUP_ROOT/env.sh"
mkdir -p "$QUDS_SETUP_ROOT/downloads"
ln -sf /lib/x86_64-linux-gnu/libsqlite3.so.0 "$QUDS_SETUP_ROOT/lib/libsqlite3.so"
if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  git clone --depth 1 --branch 3.47.8 https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
fi
QUDS_FLUTTER_COMMIT="$(git -C "$FLUTTER_ROOT" rev-parse HEAD)"
if [[ "$QUDS_FLUTTER_COMMIT" != 737ba8f885dc774b53b442759999a312c9461e4e ]]; then
  printf 'Unexpected Flutter commit: %s\n' "$QUDS_FLUTTER_COMMIT" >&2
  exit 1
fi
if [[ ! -x "$DOTNET_ROOT/dotnet" ]]; then
  curl -fL --connect-timeout 20 --max-time 120 https://dot.net/v1/dotnet-install.sh -o "$QUDS_SETUP_ROOT/downloads/dotnet-install.sh"
  bash "$QUDS_SETUP_ROOT/downloads/dotnet-install.sh" --version 8.0.428 --install-dir "$DOTNET_ROOT" --no-path
fi
if [[ ! -x "$CARGO_HOME/bin/cargo" ]]; then
  curl -fL --connect-timeout 20 --max-time 120 https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init -o "$QUDS_SETUP_ROOT/downloads/rustup-init"
  curl -fL --connect-timeout 20 --max-time 120 https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init.sha256 -o "$QUDS_SETUP_ROOT/downloads/rustup-init.sha256"
  (cd "$QUDS_SETUP_ROOT/downloads" && sha256sum --check rustup-init.sha256)
  chmod +x "$QUDS_SETUP_ROOT/downloads/rustup-init"
  "$QUDS_SETUP_ROOT/downloads/rustup-init" -y --no-modify-path --profile minimal --default-toolchain 1.100.0
fi
flutter --version --machine > "$QUDS_SETUP_ROOT/flutter-version.json"
flutter precache --linux
python3 "$QUDS_SETUP_ROOT/build_validator.py" "$QUDS_SETUP_ROOT/../quds_office_suite/tool/office-validation/Program.cs"
