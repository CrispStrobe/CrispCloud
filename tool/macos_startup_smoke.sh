#!/usr/bin/env bash

# Launches a built macOS bundle and verifies that it survives startup.
# This catches sandbox/dyld and AppDelegate failures that unit tests cannot.

set -euo pipefail

APP_PATH="${1:?usage: macos_startup_smoke.sh <app> [seconds] [log-file]}"
WATCH_SECONDS="${2:-10}"
LOG_FILE="${3:-${RUNNER_TEMP:-/tmp}/crispcloud-startup.log}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found: $APP_PATH" >&2
  exit 2
fi

EXECUTABLE="$APP_PATH/Contents/MacOS/CrispCloud"
if [[ ! -x "$EXECUTABLE" ]]; then
  echo "error: app executable not found: $EXECUTABLE" >&2
  exit 2
fi

START_TIME="$(date -u '+%Y-%m-%d %H:%M:%S')"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

print_failure_diagnostics() {
  sed -n '1,200p' "$LOG_FILE" >&2
  bash "$SCRIPT_DIR/macos_startup_diagnostics.sh" \
    "$APP_PATH" "$APP_PID" "$START_TIME" >&2 || true
}

"$EXECUTABLE" >"$LOG_FILE" 2>&1 &
APP_PID=$!

cleanup() {
  if kill -0 "$APP_PID" 2>/dev/null; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

for ((second = 0; second < WATCH_SECONDS; second++)); do
  sleep 1
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    set +e
    wait "$APP_PID"
    STATUS=$?
    set -e
    echo "error: CrispCloud exited during startup (status $STATUS)" >&2
    print_failure_diagnostics
    exit 1
  fi
done

if grep -Eqi \
  'loading libcrypto in an unsafe way|unrecognized selector|SIGABRT|Abort trap|Critical error creating config service|Credential storage startup failed|Credential policy check failed|Credential vault inspection failed|texture and its descriptor disagree|Store action needs resolve but no valid resolve texture' \
  "$LOG_FILE"; then
  echo "error: fatal startup signature found in app log" >&2
  print_failure_diagnostics
  exit 1
fi

if ! grep -Eq '\[Main\] (Credential policy ready|Credential vault unlock UI ready|Credential setup UI rendered)' "$LOG_FILE"; then
  echo "error: CrispCloud did not complete credential preflight or render an authorized unlock/setup UI within ${WATCH_SECONDS}s" >&2
  print_failure_diagnostics
  exit 1
fi

echo "CrispCloud rendered its startup UI and remained healthy for ${WATCH_SECONDS}s"
