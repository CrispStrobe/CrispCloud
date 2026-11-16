#!/usr/bin/env bash
set -euo pipefail
# Temporarily installed as the pinned SDK's bin/dart by web-resource-runner.py.
# The original executable is kept byte-for-byte at bin/dart.resource-original.
# An explicit SDK path also permits a tiny compiler probe without installation.
CRISP_DART_SDK_ROOT="${CRISP_DART_SDK_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
CRISP_DART_ORIGINAL="${CRISP_DART_ORIGINAL:-$CRISP_DART_SDK_ROOT/bin/dart.resource-original}"

if [[ "${1:-}" == compile && "${2:-}" == js ]]; then
  shift 2
  # Dart 3.13.7 CompileJSCommand invokes this exact AOT snapshot with these
  # implicit compiler arguments. Flutter's arguments pass through untouched,
  # including the standard release O4 optimization and production packages.
  # This fixed old-generation heap cap is the only compilation change.
  exec "$CRISP_DART_SDK_ROOT/bin/dartaotruntime" \
    --old_gen_heap_size=4096 \
    "$CRISP_DART_SDK_ROOT/bin/snapshots/dart2js_aot.dart.snapshot" \
    "--libraries-spec=$CRISP_DART_SDK_ROOT/lib/libraries.json" \
    --cfe-invocation-modes=compile \
    --invoker=dart_cli \
    "$@"
fi

exec "$CRISP_DART_ORIGINAL" "$@"
