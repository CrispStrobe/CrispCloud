# Terminal integration after the final branch reconciliation

The merged CrispCloud source at
`6a53294ad086e2a1c6475d888fbed7dcc2591449` passed **124 focused terminal tests**
and **three interactive shell smoke scenarios**. The source commit, source
fingerprint and resolved dependency inputs stayed unchanged during the run.
The qualification receipt reports `qualified: true`.

This source includes the terminal work discovered through the agreed incoming
work cutoff of **2026-11-15 22:34:47.559 UTC**. The final merge preserves both
parents and includes PR #140's head
`a965bfd4a61ca01e6f50bf4d8c433c3fdc9e1423`, covering nested terminal layouts,
reviewed OpenSSH destination import, terminal key bindings and SSH routing fixes.

## Executed checks

| Check | Result | Evidence |
| --- | ---: | --- |
| Nine selected model, persistence, dialog, input, broadcast and mocked SSH suites | 124 passed | [terminal-tests.log](terminal-tests.log) |
| Bash 5.2 scalar and array prompt hooks; Zsh 5.9 precmd hook | 3 passed; no skips | [terminal-shell-smoke.log](terminal-shell-smoke.log) |
| Source commit, source fingerprint and dependency stability | Unchanged | [receipt.json](receipt.json) |
| Genuine Pub resolution followed by enforced lockfile | Passed | [pub-get.log](pub-get.log), [pub-enforce.log](pub-enforce.log) |

The selected files are:

- `terminal_pane_layout_test.dart`
- `terminal_arrangements_test.dart`
- `terminal_arrangements_dialog_test.dart`
- `ssh_config_import_test.dart`
- `ssh_config_import_dialog_test.dart`
- `terminal_key_bindings_test.dart`
- `terminal_user_input_test.dart`
- `terminal_broadcast_test.dart`
- `ssh_jump_transport_test.dart`

These tests cover layout serialization and limits, saved arrangement migration,
reviewed alias selection, unsupported routing, atomic storage, concurrent
imports, key-binding persistence and input dispatch, broadcast behavior, and
SSH authentication, host-key approval and cleanup across multiple hops. They
also exercise cancellation, bounded errors, narrow layouts and localization.

The SSH suites use injected sockets and clients; `.example` session messages in
the log come from test doubles. They do not open private SSH connections, read
private keys, or import a user's SSH configuration. The shell smoke runs the
actual application helpers in temporary clean Bash/Zsh sessions and verifies
exit statuses, prompt hook order, Unicode directories and repeated setup.

## Runtime and reproduction

The runtime is official Flutter **3.47.8** with Dart **3.13.7**. The separate
expanded terminal harness resolves **127 genuine packages**. It uses
production-declared dependencies, including `dartssh2` **4.1.0**,
`web_socket_channel` **3.0.3**, `xterm2` **5.4.0**, and the actual local
`crisp_storage` source. The production `pointycastle: ^4.0.0` override is
retained.

The focused harness uses `crisp_storage`'s supported Dart SSH path with its
optional Rust bridge flags unset. No library implementation, build hook or
production dependency constraint was changed. No native application or native
bridge was built. The original Office harness manifest, lockfile and package
config stayed byte-identical to their initial setup receipt.

The complete harness manifest and lock are [pubspec.yaml](pubspec.yaml) and
[pubspec.lock](pubspec.lock). [setup-receipt.json](setup-receipt.json) records the
runtime artifact hashes, supporting package manifests, environment and
resolution evidence. Rebase the recorded absolute package paths when rebuilding
the harness elsewhere, and link its `lib` and `test` directories to the actual
CrispCloud checkout. Resolve the recorded lock before running:

```sh
python3 docs/validation/zotero-citing-20261115/terminal-integration/run-checks.py \
  --source /absolute/path/to/CrispCloud \
  --harness /absolute/path/to/crisp-terminal-expanded-harness
```

Set `FLUTTER_ROOT` to the provisioned official SDK and provide writable
`PUB_CACHE` and `TMPDIR`. The runner uses the direct Dart binary and official
`flutter_tools.snapshot`, avoiding concurrent shell-wrapper stamp races. Exact
commands, exit codes, log hashes and dependency inputs are in the receipt.
[source-before.json](source-before.json) and [source-after.json](source-after.json)
contain every recorded source hash, including host libraries, selected tests,
and the local storage library and hook inputs.

## Qualification boundary and earlier run

The broader native PTY/filesystem provider graph, full terminal-tabs widgets,
and opt-in live SSH tests are outside this focused qualification. No GitHub
Actions were queried, awaited or rerun.

The earlier **65-test, three-scenario** run at
`f0f3863604ba272149af3b00d165c41abae16521` is retained under
[before-key-bindings](before-key-bindings/README.md). Its overlapping results
are **not added** to the final 124-test count or the three smoke scenarios.
