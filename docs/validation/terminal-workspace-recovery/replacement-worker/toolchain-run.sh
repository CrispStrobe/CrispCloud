#!/bin/sh
set -eu
TASK_TOOLCHAIN=/workspace/scratch/732a154614f9/toolchain
export TMPDIR="$TASK_TOOLCHAIN/tmp"
export PUB_CACHE="$TASK_TOOLCHAIN/pub-cache"
export CARGO_HOME="$TASK_TOOLCHAIN/cargo"
export XDG_CONFIG_HOME="$TASK_TOOLCHAIN/config"
export XDG_CACHE_HOME="$TASK_TOOLCHAIN/cache"
export FLUTTER_ROOT="$TASK_TOOLCHAIN/flutter"
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true
export PATH="$TASK_TOOLCHAIN/bin:$TASK_TOOLCHAIN/rust/bin:$TASK_TOOLCHAIN/flutter/bin:$PATH"
exec "$@"
