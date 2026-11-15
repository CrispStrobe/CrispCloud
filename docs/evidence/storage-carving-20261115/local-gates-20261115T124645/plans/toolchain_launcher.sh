#!/usr/bin/env bash
set -euo pipefail
source /workspace/scratch/1e19fe1d39ae/toolchains/env.sh
if [[ "${1-}" == dart ]]; then
  shift
  exec "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" "$@"
fi
exec "$@"
