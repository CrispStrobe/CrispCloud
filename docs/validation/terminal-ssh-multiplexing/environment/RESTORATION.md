# Restored local toolchain

This setup is environment preparation, not new feature acceptance. It uses the production CrispCloud graph with the checked-in lockfile and normal native build hooks.

## Tool versions and command entry points

Flutter source is the official `3.47.8` tag at `737ba8f885dc774b53b442759999a312c9461e4e`; Dart is 3.13.7. Clang 19.1.7, CMake 3.31.6, Ninja 1.12.1 and Rust/Cargo 1.100.0 are installed under this directory. The SDK source is unmodified.

From `CrispCloud`, prefix commands with `../toolchain/run`:

```sh
../toolchain/run flutter pub get --enforce-lockfile --offline
../toolchain/run flutter test --no-pub --concurrency=1 --reporter=expanded test/terminal_process_test.dart
../toolchain/run dart analyze path/to/files.dart
../toolchain/run python3 tool/run_terminal_validation.py native --evidence path/to/evidence
```

`run` sets workspace-owned temporary/cache paths and adds the required launchers to PATH. `bin/flutter-direct` invokes the standard Flutter tool snapshot compiled by the unmodified official bootstrap; it avoids the per-process-namespace engine-stamp collision in the shell launcher. `bin/clang` and `bin/cmake` provide their extracted shared-library locations. Rust uses a local CARGO_HOME.

## Reproduction and verification

1. Clone official Flutter tag 3.47.8 and verify its Git revision.
2. Run the official Flutter launcher to download the matching Dart SDK and compile the standard Flutter tools snapshot.
3. `warm_pub.py` downloads hosted archives from official pub.dev archive URLs, verifies every SHA-256 against the SDK/application lockfiles, and populates the local cache. All 322 archives passed.
4. `restore_native.py` obtains exact native/Rust artifacts from the preceding acceptance manifests (`native-downloads.json` and `tmux-downloads.json`), verifies their SHA-256 digests, and extracts/installs them locally. All artifacts passed. C and Rust compile-and-execute probes passed.
5. The first online app resolver downloaded normal engine assets and exact Git mirrors, then was interrupted while making hosted metadata requests. The enforced offline resolution completed successfully using the verified cache and unchanged production manifests.
6. Successfully installed download archives were removed to reclaim 598,942,823 bytes; `removed-download-archives.json` records their identities. Extracted verified installations remain.

The environment still denies ordinary Unix socket creation with EPERM. TCP loopback succeeds. No socket-policy workaround was attempted. No GitHub Actions endpoint was used.

Logs and receipts in this directory retain the observed commands/results, including environment preparation attempts. `environment-current.json` records version/provenance information and the separate prerequisite test result.

## Final prerequisite result

`terminal_process_test.dart`: **6 passed, 1 Windows-only skip, 0 failures** after the in-progress source compilation issue was corrected. The passing run exercises actual Linux PTYs, ANSI/final output, resize, Unicode input/output, Ctrl+C and disposal. All normal production native hooks built, including catalogue, SMB/storage, ebook conversion, PTY and SQLite. The first compilation failure remains separately preserved. This is toolchain qualification; it is not the full new-feature regression run.
