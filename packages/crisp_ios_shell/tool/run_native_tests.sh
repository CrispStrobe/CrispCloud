#!/bin/bash
# The same-process suite is the required gate. Separate runs only reveal failures
# masked by its first assertion; they cannot change the original gate result.
set -euo pipefail

SIMULATOR_UDID="$1"
TEST_EXECUTABLE="$2"
if xcrun simctl spawn "$SIMULATOR_UDID" "$TEST_EXECUTABLE"; then
  exit 0
else
  SUITE_STATUS=$?
fi

printf 'DIAGNOSTIC: full native suite failed with status %s; running individual cases\n' "$SUITE_STATUS"
if TEST_CASES="$(xcrun simctl spawn "$SIMULATOR_UDID" "$TEST_EXECUTABLE" --list)"; then
  while IFS= read -r TEST_CASE; do
    [[ -n "$TEST_CASE" ]] || continue
    printf 'DIAGNOSTIC: native case %s\n' "$TEST_CASE"
    if xcrun simctl spawn "$SIMULATOR_UDID" "$TEST_EXECUTABLE" "$TEST_CASE"; then
      :
    else
      printf 'DIAGNOSTIC: native case %s failed with status %s\n' "$TEST_CASE" "$?"
    fi
  done <<< "$TEST_CASES"
else
  printf 'DIAGNOSTIC: could not list native cases\n'
fi
exit "$SUITE_STATUS"
