#!/usr/bin/env bash
# Source this file before local qualification; all caches remain in the workspace.
export QUDS_TOOLCHAIN_ROOT=/workspace/scratch/0b93849cdeb9/toolchains
export CRISP_TOOLCHAIN_ROOT="$QUDS_TOOLCHAIN_ROOT"
export FLUTTER_ROOT="$QUDS_TOOLCHAIN_ROOT/flutter"
export CARGO_HOME="$QUDS_TOOLCHAIN_ROOT/cargo-home"
export RUSTUP_HOME="$QUDS_TOOLCHAIN_ROOT/rustup-home"
export PUB_CACHE="$QUDS_TOOLCHAIN_ROOT/pub-cache"
export TMPDIR="$QUDS_TOOLCHAIN_ROOT/tmp"
export XDG_CACHE_HOME="$QUDS_TOOLCHAIN_ROOT/cache"
export XDG_CONFIG_HOME="$QUDS_TOOLCHAIN_ROOT/config"
export PATH="$QUDS_TOOLCHAIN_ROOT/bin:$QUDS_TOOLCHAIN_ROOT/native/usr/lib/llvm-19/bin:$QUDS_TOOLCHAIN_ROOT/native/usr/bin:$CARGO_HOME/bin:$FLUTTER_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$QUDS_TOOLCHAIN_ROOT/native/usr/lib/x86_64-linux-gnu:$QUDS_TOOLCHAIN_ROOT/native/usr/lib/llvm-19/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CI=true
export DART_DISABLE_ANALYTICS=true
export DART_SUPPRESS_ANALYTICS=true
export FLUTTER_SUPPRESS_ANALYTICS=true
