#!/usr/bin/env bash
set -euo pipefail
source /workspace/scratch/0b93849cdeb9/toolchains/env.sh
if [[ "${1-}" == dart ]]; then
  shift
  exec "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" "$@"
fi
exec "$@"
