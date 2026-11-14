#!/bin/sh
# Build hooks deliberately filter custom cache variables. Keep real Rust builds
# in this writable scratch toolchain without changing production hook code.
export CARGO_HOME=/workspace/scratch/4f6714f1660a/runtime-setup/cargo
export RUSTUP_HOME=/workspace/scratch/4f6714f1660a/runtime-setup/rustup
export PATH=/workspace/scratch/4f6714f1660a/runtime-setup/rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin:$PATH
exec /workspace/scratch/4f6714f1660a/runtime-setup/rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin/cargo "$@"
