#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/crispcloud-smoke-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
app="$fixture/CrispCloud.app"
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/MacOS/CrispCloud" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${CRISPCLOUD_TEST_STARTUP_OUTPUT:-}"
exec sleep 30
EOF
chmod 700 "$app/Contents/MacOS/CrispCloud"

CRISPCLOUD_TEST_STARTUP_OUTPUT='ℹ️ [Main] Startup UI rendered' \
  "$root/tool/macos_startup_smoke.sh" "$app" 1 "$fixture/success.log"

if CRISPCLOUD_TEST_STARTUP_OUTPUT='ℹ️ [Main] App starting...' \
    "$root/tool/macos_startup_smoke.sh" "$app" 1 "$fixture/no-frame.log"; then
  echo 'error: a startup without a rendered UI was accepted' >&2
  exit 1
fi

if CRISPCLOUD_TEST_STARTUP_OUTPUT='❌ [Main] Critical error creating config service' \
    "$root/tool/macos_startup_smoke.sh" "$app" 1 "$fixture/failed.log"; then
  echo 'error: the startup error screen was accepted' >&2
  exit 1
fi

if CRISPCLOUD_TEST_STARTUP_OUTPUT='WARNING: loading libcrypto in an unsafe way' \
    "$root/tool/macos_startup_smoke.sh" "$app" 1 "$fixture/crypto.log"; then
  echo 'error: an unsafe crypto load was accepted' >&2
  exit 1
fi
