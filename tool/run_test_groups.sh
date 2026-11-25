#!/usr/bin/env bash
# Runs the deterministic Flutter test suite in disjoint file groups, each in a
# fresh `flutter test` process with its own time limit (Linux CI runners).
#
# Why groups: with --coverage, flutter_tester began to segfault after a few
# hundred files in one process and every later tester crashed, hanging the
# job (2026-11-23). The crash grows with the files one process has seen, so
# fresh processes keep any hang short and attributable to one group.
#
# Usage: tool/run_test_groups.sh [--groups N] [--limit 20m] [--coverage DIR]
#                                 [--warn-only]
#   --coverage DIR  also collect coverage, one lcov file per group in DIR
#                   (use many small groups, about 50 files each).
#   --warn-only     report failed groups as warnings and exit 0. For the
#                   coverage job only: the VM can still crash in some groups
#                   with --coverage, and correctness is gated by the plain run.
set -uo pipefail

groups=4
limit=20m
coverage_dir=
warn_only=false
while [ $# -gt 0 ]; do
  case "$1" in
    --groups) groups=$2; shift 2 ;;
    --limit) limit=$2; shift 2 ;;
    --coverage) coverage_dir=$2; shift 2 ;;
    --warn-only) warn_only=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

mapfile -t files < <(find test -name '*_test.dart' | LC_ALL=C sort)
[ "${#files[@]}" -gt 0 ] || { echo 'No test files found' >&2; exit 1; }
[ -z "$coverage_dir" ] || mkdir -p "$coverage_dir"

failed=()
for g in $(seq 0 $((groups - 1))); do
  batch=()
  for i in "${!files[@]}"; do
    if [ $((i % groups)) -eq "$g" ]; then batch+=("${files[$i]}"); fi
  done
  [ "${#batch[@]}" -gt 0 ] || continue
  echo "::group::Test group $((g + 1))/$groups: ${#batch[@]} files"
  # A killed group cannot restore the SQLite hook it added.
  git checkout -- pubspec.yaml
  free -m; df -h / "${RUNNER_TEMP:-/tmp}"
  extra=()
  if [ -n "$coverage_dir" ]; then
    extra=(--coverage --coverage-path "$coverage_dir/group-$((g + 1)).lcov.info")
  fi
  if ! timeout --signal=INT --kill-after=60 "$limit" \
    python3 tool/with_ci_system_sqlite.py flutter test --concurrency=4 \
    --exclude-tags=benchmark,live,deploy,mock_server,integration,connection_dialog,golden \
    "${extra[@]}" "${batch[@]}"
  then
    failed+=("$((g + 1))")
  fi
  echo '::endgroup::'
done
git checkout -- pubspec.yaml

if [ "${#failed[@]}" -gt 0 ]; then
  if [ "$warn_only" = true ]; then
    echo "::warning::Test group(s) failed: ${failed[*]} of $groups (not gating)"
    exit 0
  fi
  echo "::error::Test group(s) failed: ${failed[*]} of $groups"
  exit 1
fi
echo "All $groups test groups passed (${#files[@]} files)"
