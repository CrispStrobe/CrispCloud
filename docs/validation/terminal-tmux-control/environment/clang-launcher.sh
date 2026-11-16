#!/bin/sh
export TMPDIR='/workspace/scratch/6c8a74f9de7f/toolchain/tmp'
export LD_LIBRARY_PATH="/workspace/scratch/6c8a74f9de7f/toolchain/native/usr/lib/x86_64-linux-gnu:/workspace/scratch/6c8a74f9de7f/toolchain/native/usr/lib/llvm-19/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "/workspace/scratch/6c8a74f9de7f/toolchain/native/usr/lib/llvm-19/bin/clang" "$@"
