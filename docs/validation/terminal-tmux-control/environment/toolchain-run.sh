#!/bin/sh
set -eu
export TMPDIR='/workspace/scratch/6c8a74f9de7f/toolchain/tmp'
export PUB_CACHE='/workspace/scratch/6c8a74f9de7f/toolchain/pub-cache'
export CARGO_HOME='/workspace/scratch/6c8a74f9de7f/toolchain/cargo'
export XDG_CONFIG_HOME='/workspace/scratch/6c8a74f9de7f/toolchain/config'
export XDG_CACHE_HOME='/workspace/scratch/6c8a74f9de7f/toolchain/cache'
export FLUTTER_ROOT="/workspace/scratch/6c8a74f9de7f/toolchain/flutter"
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true
export RUSTC='/workspace/scratch/6c8a74f9de7f/toolchain/rust/bin/rustc'
export PATH='/workspace/scratch/6c8a74f9de7f/toolchain/bin:/workspace/scratch/6c8a74f9de7f/toolchain/rust/bin':"$PATH"
exec "$@"
