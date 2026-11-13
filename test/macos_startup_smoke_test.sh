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

CRISPCLOUD_TEST_STARTUP_OUTPUT='ℹ️ [Main] Credential policy ready' \
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

# Rendering an application shell is not a successful credential-policy check.
if CRISPCLOUD_TEST_STARTUP_OUTPUT='ℹ️ [Main] Startup UI rendered' \
    "$root/tool/macos_startup_smoke.sh" "$app" 1 "$fixture/shell-only.log"; then
  echo 'error: shell rendering bypassed the credential readiness check' >&2
  exit 1
fi
if CRISPCLOUD_TEST_STARTUP_OUTPUT=$'ℹ️ [Main] Credential policy ready\n❌ [Main] Credential policy check failed' \
    "$root/tool/macos_startup_smoke.sh" "$app" 1 "$fixture/late-policy.log"; then
  echo 'error: a later credential-policy failure was accepted' >&2
  exit 1
fi

# A kernel-style SIGKILL before logging must remain a failure and expose the
# diagnostic path. This disposable shell fixture never launches CrispCloud.
cat > "$app/Contents/MacOS/CrispCloud" <<'EOF_KILLED'
#!/usr/bin/env bash
kill -KILL $$
EOF_KILLED
if "$root/tool/macos_startup_smoke.sh" "$app" 1 "$fixture/killed.log" \
    > "$fixture/killed-diagnostics.log" 2>&1; then
  echo 'error: a startup killed before logging was accepted' >&2
  exit 1
fi
grep -q 'status 137' "$fixture/killed-diagnostics.log"
grep -q 'macOS startup diagnostics (read-only)' "$fixture/killed-diagnostics.log"
grep -q 'not a macOS Mach-O binary' "$fixture/killed-diagnostics.log"

if bash "$root/tool/macos_startup_diagnostics.sh" "$app" invalid \
    '2026-01-01 00:00:00' > "$fixture/invalid-pid.log" 2>&1; then
  echo 'error: diagnostic query accepted an invalid process id' >&2
  exit 1
fi
grep -q 'refusing an unbounded system log query' "$fixture/invalid-pid.log"
