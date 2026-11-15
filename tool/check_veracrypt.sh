#!/usr/bin/env bash
# Local focused validation; no GitHub Actions polling or submission.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter_bin="${FLUTTER:-flutter}"
dart_bin="${DART:-dart}"
python3 tool/with_ci_system_sqlite.py "$flutter_bin" --no-version-check test --no-pub \
  test/veracrypt_test.dart test/veracrypt_header_vectors_test.dart \
  test/veracrypt_compatibility_test.dart test/veracrypt_container_reader_test.dart \
  test/veracrypt_header_worker_test.dart test/veracrypt_viewer_routing_test.dart \
  test/veracrypt_mount_test.dart test/panel_source_test.dart \
  test/panel_source_restore_test.dart test/veracrypt_panel_transfer_test.dart \
  test/panel_swap_view_test.dart test/panel_swap_virtual_test.dart \
  test/widget/veracrypt_unlock_dialog_test.dart test/widget/veracrypt_viewer_test.dart
probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/crisp-veracrypt.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
"$dart_bin" compile js -O2 test/fixtures/veracrypt/web_compatibility_probe.dart -o "$probe_dir/crypto.js"
node tool/run_dart_web_probe.cjs "$probe_dir/crypto.js" \
  'PASS: 5 independent JS PBKDF/header/data/keyfile vectors, 3 invalid geometries, browser Argon2 allocation and PBKDF2 work guards.'
"$dart_bin" compile js -O2 test/support/veracrypt_web_smoke.dart -o "$probe_dir/reader.js"
node tool/run_dart_web_probe.cjs "$probe_dir/reader.js" \
  'PASS: compiled-JavaScript VeraCrypt PIM and native-header TrueCrypt FAT listing, cross-sector file reads, nested files and closed sessions.'
