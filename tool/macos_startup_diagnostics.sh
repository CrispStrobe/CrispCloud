#!/usr/bin/env bash
# Read-only diagnostics for a failed startup; never signs or launches the app.
set -uo pipefail

app_path="${1:?usage: macos_startup_diagnostics.sh <app> <pid> <start-time>}"
app_pid="${2:?missing process id}"
start_time="${3:?missing start time}"
executable="$app_path/Contents/MacOS/CrispCloud"

printf '\n%s\n' '--- macOS startup diagnostics (read-only) ---'
if [[ ! "$app_pid" =~ ^[0-9]+$ ]]; then
  echo 'Invalid process id; refusing an unbounded system log query.'
  exit 2
fi
if [[ "$(uname -s)" != Darwin ]] || ! file -b "$executable" | grep -q 'Mach-O'; then
  echo 'Skipping macOS security diagnostics: executable is not a macOS Mach-O binary.'
  exit 0
fi

# A failed check is diagnostic evidence, not a reason to skip remaining checks.
run_check() {
  printf '\n$'
  printf ' %q' "$@"
  printf '\n'
  "$@" 2>&1
  local status=$?
  printf '[diagnostic exit status: %s]\n' "$status"
  return 0
}

run_check /usr/bin/codesign --verify --deep --strict --verbose=4 "$app_path"
run_check /usr/bin/codesign --display --verbose=4 "$executable"
run_check /usr/bin/codesign --display --entitlements :- "$executable"
run_check /usr/bin/otool -L "$executable"
run_check /usr/bin/lipo -info "$executable"
helper="$app_path/Contents/Resources/crispcloud_fuse_bridge"
if [[ -f "$helper" ]]; then
  run_check /usr/bin/codesign --verify --strict --verbose=4 "$helper"
  run_check /usr/bin/codesign --display --entitlements :- "$helper"
fi

# Restrict diagnostics to this exact process and app launch interval. Security
# daemons may log termination decisions outside the application's own process.
app_name="$(basename "$app_path" .app)"
escaped_name="${app_name//\\/\\\\}"
escaped_name="${escaped_name//\"/\\\"}"
predicate="processID == $app_pid OR ((process == \"kernel\" OR process == \"amfid\" OR process == \"taskgated\" OR process == \"syspolicyd\") AND eventMessage CONTAINS[c] \"$escaped_name\")"
run_check /usr/bin/log show --style compact --start "$start_time" \
  --end "$(date -u '+%Y-%m-%d %H:%M:%S')" --timezone UTC \
  --info --debug --predicate "$predicate"
