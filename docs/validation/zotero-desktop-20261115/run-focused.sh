#!/usr/bin/env bash
set -euo pipefail

validation_root="$(cd "$(dirname "$0")" && pwd)"
validation_workspace="$(dirname "$validation_root")"
validation_sdk="${ZOTERO_VALIDATION_SDK:-$validation_workspace/runtime-dart-3.13.7/dart-sdk}"
export TMPDIR="$validation_workspace/runtime-dart-3.13.7/tmp"
export PUB_CACHE="$validation_workspace/runtime-dart-3.13.7/pub-cache"
export XDG_CONFIG_HOME="$validation_workspace/runtime-dart-3.13.7/config"
export DART_SUPPRESS_ANALYTICS=1
mkdir -p "$TMPDIR" "$PUB_CACHE" "$XDG_CONFIG_HOME"
cd "$validation_root"

"$validation_sdk/bin/dart" --version > dart-version.log 2>&1
"$validation_sdk/bin/dart" pub get > pub-get.log 2>&1

for validation_suite in zotero_client host_transport; do
  "$validation_sdk/bin/dartaotruntime" \
    "$validation_sdk/bin/snapshots/frontend_server_aot.dart.snapshot" \
    --sdk-root "$validation_sdk/" \
    --platform "$validation_sdk/lib/_internal/vm_platform_strong.dill" \
    --target vm --enable-asserts --no-embed-source-text \
    --no-print-incremental-dependencies \
    --packages .dart_tool/package_config.json \
    --output-dill ".dart_tool/${validation_suite}_test.dill" \
    "test/${validation_suite}_test.dart" \
    > "${validation_suite}-compile.log" 2>&1
  "$validation_sdk/bin/dartvm" --enable-asserts \
    --packages=.dart_tool/package_config.json \
    ".dart_tool/${validation_suite}_test.dill" \
    > "${validation_suite}-tests.log" 2>&1
done

"$validation_sdk/bin/dart" analyze --fatal-infos . > analysis.log 2>&1
