#!/bin/sh
export PUB_CACHE=/tmp/crispcloud-pub-cache-20261116
export CARGO_HOME=/tmp/crispcloud-cargo-20261116
export RUSTUP_HOME=/tmp/crispcloud-rustup-20261116
export CARGO_HTTP_MULTIPLEXING=false
export CARGO_HTTP_TIMEOUT=30
export PATH=/tmp/crispcloud-cargo-20261116/bin:$PATH
exec /Users/christianstrobele/flutter-3.47.8/bin/cache/dart-sdk/bin/dart --packages=/tmp/crispcloud-flutter-tools-packages-20261116.json /Users/christianstrobele/flutter-3.47.8/bin/cache/flutter_tools.snapshot "$@"
