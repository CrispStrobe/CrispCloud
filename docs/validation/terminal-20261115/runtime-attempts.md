# Terminal runtime validation attempt — 2026-11-15

## Status

**The native Flutter feature suites did not execute.** The first requested suite reached kernel compilation, but the workspace ran out of disk space while Flutter copied the compiled kernel for execution and persistent caching. No passing native Flutter test count is claimed for this continuation. The earlier PR #140 results belong to that earlier source revision.

This record separates successful toolchain preparation from application validation. The feature sources and their tests were changing in parallel; the incomplete attempt is not an exact-source qualification of a final commit.

## Successfully observed prerequisites

| Item | Observed result |
| --- | --- |
| Flutter framework | Tag `3.47.8`; `flutter --version` reported revision `737ba8f885`. |
| Flutter engine | `cf636b1dfb818dd6a3ff16e390e93b1a036969c8`. |
| Engine content hash | `dfd2e6cb7d319db05e3bf1503f3e2ac60f6288a2`. |
| Dart | `3.13.7 (stable)`, Linux x64. |
| Native test engine | The actual `flutter_tester --help` executable ran and reported the pinned engine/content hashes. This is a startup check, not a widget test. |
| Focused dependency resolution | `dart pub get --offline` completed and reported 106 resolved dependencies. Direct versions were taken from the application lockfile. The focused graph was not a full application build or a full-production lockfile enforcement run. |
| Published package retrieval | Downloaded package archives were checked against the SHA-256 in the corresponding pub.dev version metadata before extracting runtime sources. |
| libdbm | The focused harness used the exact application-locked Git commit `547b5bfce1d3cd663810a3ceae35336857956139`. |
| Production source | Harness `lib`, `test`, `packages`, and `assets` paths were symlinks to the actual application checkout. No replacement application classes or transport stubs were introduced by the harness. |
| Production manifests | The validation setup did not edit the application `pubspec.yaml` or `pubspec.lock`. |

### Focused direct dependencies

`flutter`, `flutter_localizations`, and `flutter_test` came from the pinned SDK. The focused manifest also selected:

- `flutter_riverpod 2.6.1`, `shared_preferences 2.5.6`, `xterm2 5.4.0`, `dartssh2 4.1.0`.
- `flutter_secure_storage 9.2.4`, `web_socket_channel 3.0.3`, `crypto 3.0.7`, `path 1.9.1`, `http 1.6.0`.
- `flutter_lints 3.0.2` for analysis configuration.
- Existing application overrides `meta 1.19.0`, `pointycastle 4.0.0`, and `uuid 4.5.1`.
- Actual local `packages/crisp_storage` and its relative `filen_client` dependency, plus the exact pinned libdbm source above.

The focused manifest did not enable the application's unrelated Rust SMB build define. The real `crisp_storage` hook therefore performed its existing no-op path. The `objective_c` hook performed its existing Linux no-op path. This does not qualify those native subsystems or PTY packaging.

## Runtime preparation and space reductions

The initial complete checkout occupied approximately 718 MiB. The shared overlay was already almost full. History and unrelated tracked binary material were retained remotely while the local checkout was made sparse.

A minimal pinned SDK was assembled from the official engine artifact base:

`https://storage.googleapis.com/flutter_infra_release/flutter/cf636b1dfb818dd6a3ff16e390e93b1a036969c8/`

Used artifacts included `dart-sdk-linux-x64.zip`, `linux-x64/artifacts.zip`, `flutter_patched_sdk.zip`, `sky_engine.zip`, and `flutter_gpu.zip`. Selected ZIP entries were checked for expected expanded lengths and ZIP CRCs. Native Flutter shader compilation additionally required the original `impellerc` executable.

To fit the workspace, downloaded dependency test/example/documentation trees, published developer caches, screenshots, and the optional SharedPreferences DevTools web UI bundle were omitted or removed. Runtime Dart libraries, native-hook source, package metadata, and licenses used by the harness remained original package content.

The sandbox has no `/tmp`; commands used a writable workspace `TMPDIR`. The unchanged Flutter tool was compiled into a kernel with `--no-link-platform --no-embed-sources`, then run through a small shell wrapper. This avoided retaining both a source-compilation service and a compiled Flutter tool. The two generated no-op hook kernels were similarly recompiled without embedded source text or linked platform code, reducing their combined size from approximately 22 MiB to 2.6 MiB. This changed generated cache artifacts, not application or dependency source.

The Flutter test frontend's correct option is `--no-embed-source-text`. It is passed by the companion [frontend starter](frontend_without_sources.dart) through Flutter's supported `--frontend-server-starter-path` option. `--extra-front-end-options` is not accepted by this Flutter `test` command. The starter delegates to the original pinned frontend snapshot, preserves all supplied arguments and standard I/O, and omits embedded source text only. Widget creation tracking was also disabled for the attempt. Compiler and test assertions were not disabled.

## Attempts and final blocker

Several preparatory attempts failed before test loading because a minimal install initially omitted a required SDK compiler snapshot, the product platform summary needed by hook compilation, or `impellerc`. These prerequisites were restored from the exact official engine artifacts. Two attempted flag spellings were rejected by the CLI/frontend before compilation; the documented final command below uses the corrected spelling.

The final attempt requested:

1. `test/ssh_jump_host_test.dart`
2. `test/ssh_jump_transport_test.dart`
3. `test/ssh_jump_dialog_test.dart`
4. `test/terminal_arrangements_test.dart`
5. `test/terminal_arrangements_dialog_test.dart`

Its last observed runner result was a **load error at +0 completed tests**, for the first file. The relevant error was:

```text
Error: Flutter failed to create a directory at
"/workspace/scratch/32cc0ca57b2f/.terminal-tools/terminal-harness/build/test_cache/build".
The target device is full.
FileSystemException: Creation failed ... (OS Error: No space left on device, errno = 28)
```

The first test kernel compiled to approximately 24 MiB. Flutter created another approximately 24 MiB execution copy and then failed creating its persistent test-cache copy. The filesystem reported zero bytes available. The test process was interrupted and returned exit code 130; no test assertions or native feature behavior were qualified.

The abandoned compiler directory was:

`/workspace/scratch/32cc0ca57b2f/.terminal-tools/tmp/flutter_tools.ZYLOVM`

Its known 24 MiB intermediate was:

`flutter_test_compiler.UMUNGF/output.dill`

Disk exhaustion then prevented the sandbox helper itself from starting, including otherwise safe cleanup commands and patch reads. This is an environment failure, not evidence that the feature tests pass or fail.

## Commands and reproduction

The original workspace helper used:

```sh
export PUB_CACHE=/workspace/scratch/32cc0ca57b2f/.terminal-tools/pub-cache
export TMPDIR=/workspace/scratch/32cc0ca57b2f/.terminal-tools/tmp
export FLUTTER_ROOT=/workspace/scratch/32cc0ca57b2f/.terminal-tools/flutter
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true
```

The Flutter tool was prepared from unchanged SDK source with:

```sh
dart compile kernel --no-link-platform --no-embed-sources \
  --packages="$FLUTTER_ROOT/packages/flutter_tools/.dart_tool/package_config.json" \
  --output="$FLUTTER_ROOT/bin/cache/flutter_tools.dill" \
  "$FLUTTER_ROOT/packages/flutter_tools/bin/flutter_tools.dart"
```

The wrapper then invoked the compiled tool through the SDK's `dart --disable-dart-dev`, with the same tool package configuration. The frontend starter was compiled using the same two kernel size-reduction options.

The final attempted command, run inside `.terminal-tools/terminal-harness`, was:

```sh
../flutter-focused test --no-pub --no-track-widget-creation \
  --frontend-server-starter-path=/workspace/scratch/32cc0ca57b2f/.terminal-tools/frontend_without_sources.dill \
  --concurrency=1 --reporter expanded \
  test/ssh_jump_host_test.dart \
  test/ssh_jump_transport_test.dart \
  test/ssh_jump_dialog_test.dart \
  test/terminal_arrangements_test.dart \
  test/terminal_arrangements_dialog_test.dart
```

For a fresh environment, use the repository's pinned complete Flutter SDK and normal dependency instructions with adequate free space. The ordinary `flutter test` command does not need the storage-saving starter when capacity is sufficient. Run the new feature suites and the existing terminal regressions against the final checked-out commit, preserving the resulting logs and source binding.

The subsequently added shell integration, input ownership, broadcast, profiles, session discovery, and full workspace widget suites were **not executed by this runtime attempt**. The complete application provider graph, browser tests, packaged desktop/mobile builds, live SSH gateways/jump hosts, and live tmux/screen persistence also remain outside this attempt's qualification.

**No GitHub Actions result was awaited, and no workflow was triggered by this validation preparation.**
