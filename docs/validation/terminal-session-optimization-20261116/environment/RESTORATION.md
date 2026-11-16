# Local validation toolchain

The workspace runner is `../toolchain/run` when working inside CrispCloud.
It sets only workspace-owned caches/temporary paths, PATH and extracted shared-library paths.
The production application manifests and lockfile are unchanged.

## Reproduce

1. Clone official Flutter tag 3.47.8 at 737ba8f885dc774b53b442759999a312c9461e4e. Its unmodified launcher obtains Dart 3.13.7.
2. Run `warm_pub.py` to fetch the exact 322 SDK/application hosted archives and verify their SHA-256 values. Full package trees are retained.
3. Run `restore_native.py` to verify/install the 23 recorded Debian/Rust/tmux artifacts locally. Rust/Cargo 1.100.0, Clang 19.1.7, CMake 3.31.6 and Ninja 1.12.1 are available through the runner.
4. Resolve the official Flutter tools package offline and build its snapshot with the standard flags in `bin/internal/shared.sh`. The separate launcher uses that snapshot; SDK source files are unmodified.
5. Let standard app resolution fetch the exact Git mirrors, then run `../toolchain/run flutter pub get --enforce-lockfile --offline`.
6. Run normal Flutter test commands through the runner; native asset hooks remain enabled. The initial Linux PTY prerequisite command and result are in `environment-setup.json`.

All archive hashes, active compiler/runtime hashes, version outputs, initial/current app manifest hashes, and actual socket probes are in `environment-setup.json` and its referenced logs.
No GitHub Actions command is needed. Real Unix sockets are denied by this host, so tmux daemon, Unix-agent and Chromium runtime acceptance remains blocked.

## Prerequisite result

`terminal_process_test.dart` completed with **6 passing tests, 1 Windows-only skip and no failures** on the normal application graph. All native hooks built. Actual Linux PTYs covered TTY identity, ANSI/final output, resize, Unicode, Ctrl+C and disposal. This prepares the environment and is separate from the feature acceptance cohort.
