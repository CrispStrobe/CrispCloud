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
    sed -n '1,200p' "$LOG_FILE" >&2
    exit 1
  fi
done

if grep -Eqi \
  'loading libcrypto in an unsafe way|unrecognized selector|SIGABRT|Abort trap' \
  "$LOG_FILE"; then
  echo "error: fatal startup signature found in app log" >&2
  sed -n '1,200p' "$LOG_FILE" >&2
  exit 1
fi

echo "CrispCloud remained healthy for ${WATCH_SECONDS}s"
