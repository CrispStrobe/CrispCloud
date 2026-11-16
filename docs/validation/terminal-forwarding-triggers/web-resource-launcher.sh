#!/usr/bin/env bash
set -euo pipefail
# Installed temporarily at the pinned SDK's bin/dart by the recorded build
# wrapper. The original ELF stays byte-identical at bin/dart.resource-original.
# Flutter invokes `dart compile js`; SDK 3.13.7's CompileJSCommand delegates to
# this same AOT snapshot with the three implicit arguments reproduced below.
# Only the compiler VM's heap limit changes. All Flutter compiler arguments,
# including O4 and the production package configuration, pass through exactly.
CRISP_SDK_ROOT=/workspace/scratch/43b2a351bc52/toolchain/flutter/bin/cache/dart-sdk
CRISP_COMPILER_HEAP_MB="${CRISP_COMPILER_HEAP_MB:-3072}"
if [[ ! "$CRISP_COMPILER_HEAP_MB" =~ ^[0-9]+$ ]] || \
   (( CRISP_COMPILER_HEAP_MB < 128 || CRISP_COMPILER_HEAP_MB > 4096 )); then
  echo 'CRISP_COMPILER_HEAP_MB must be between 128 and 4096.' >&2
  exit 64
fi
if [[ "${1:-}" == compile && "${2:-}" == js ]]; then
  shift 2
  exec "$CRISP_SDK_ROOT/bin/dartaotruntime" \
    "--old_gen_heap_size=$CRISP_COMPILER_HEAP_MB" \
    "$CRISP_SDK_ROOT/bin/snapshots/dart2js_aot.dart.snapshot" \
    "--libraries-spec=$CRISP_SDK_ROOT/lib/libraries.json" \
    --cfe-invocation-modes=compile \
    --invoker=dart_cli \
    "$@"
fi
exec "$CRISP_SDK_ROOT/bin/dart.resource-original" "$@"
