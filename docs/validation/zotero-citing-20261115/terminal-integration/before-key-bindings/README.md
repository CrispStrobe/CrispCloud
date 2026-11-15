# Terminal integration checks after the Zotero branch reconciliation

The merged CrispCloud source at
`f0f3863604ba272149af3b00d165c41abae16521` passed **65 focused terminal tests**
and **three interactive shell smoke scenarios**. The source commit, source
fingerprint and resolved dependency inputs stayed unchanged during the run.

This qualification covers the terminal work brought in from PR #140 during the
final branch reconciliation: nested pane layouts and versioned arrangements,
followed by reviewed OpenSSH destination import. The merge retains both parents,
including the incoming terminal head
`bd086eea48525346216c59e0c899b4d33751029b`.

## Executed checks

| Check | Result | Evidence |
| --- | ---: | --- |
| Nested layout model, arrangement persistence/dialog, SSH config parser/import dialog | 65 passed | [terminal-tests.log](terminal-tests.log) |
| Bash 5.2 scalar and array prompt hooks; Zsh 5.9 precmd hook | 3 passed; no skips | [terminal-shell-smoke.log](terminal-shell-smoke.log) |
| Source and dependency stability | Unchanged | [receipt.json](receipt.json) |
| Genuine Pub resolution followed by enforced lockfile | Passed | [pub-get.log](pub-get.log), [pub-enforce.log](pub-enforce.log) |

The five selected test files are `terminal_pane_layout_test.dart`,
`terminal_arrangements_test.dart`, `terminal_arrangements_dialog_test.dart`,
`ssh_config_import_test.dart`, and `ssh_config_import_dialog_test.dart`.
They exercise layout serialization and limits, saved arrangement migration,
reviewed alias selection, unsupported routing, atomic storage, concurrent
imports, cancellation, bounded errors, narrow layouts, and localization.

These tests use fixtures and injected storage. They do not open private SSH
connections, read private keys or import a user's SSH configuration. The shell
smoke runs the actual application shell helpers in temporary clean Bash/Zsh
sessions and verifies exit statuses, prompt hook order, Unicode directories,
and repeated setup.

## Runtime and reproduction

The runtime is official Flutter **3.47.8** with Dart **3.13.7**. The separate
terminal harness reuses the genuine resolved Office harness graph and adds the
production-declared constraints `dartssh2: ^4.1.0` and
`web_socket_channel: ^3.0.0`. Its enforced lock resolves these to **4.1.0** and
**3.0.3**, respectively, in a 103-package graph. Production manifests and the
Office harness manifest, lockfile and package config were unchanged.

The complete harness manifest and lock are saved as [pubspec.yaml](pubspec.yaml)
and [pubspec.lock](pubspec.lock). [setup-receipt.json](setup-receipt.json) records
the runtime artifact hashes, supporting package manifests, environment, and
resolution evidence. Rebase the recorded absolute package paths when rebuilding
the harness elsewhere, and link its `lib` and `test` directories to the actual
CrispCloud checkout. Resolve the recorded lock before running:

```sh
python3 docs/validation/zotero-citing-20261115/terminal-integration/before-key-bindings/run-checks.py \
  --source /absolute/path/to/CrispCloud \
  --harness /absolute/path/to/crisp-terminal-harness
```

Set `FLUTTER_ROOT` to the provisioned official SDK and provide writable
`PUB_CACHE` and `TMPDIR`. The runner uses the direct Dart binary and official
`flutter_tools.snapshot`, avoiding concurrent shell-wrapper stamp races. Exact
executed commands, exit codes, log hashes and dependency inputs are in the
receipt. [source-before.json](source-before.json) and
[source-after.json](source-after.json) contain every recorded source hash.

This is a focused integration check. It does not certify a native application
build, live SSH behavior, or the full terminal-tabs/provider widget graph.
No GitHub Actions were queried, awaited or rerun.
