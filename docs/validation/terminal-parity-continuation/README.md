# Terminal parity continuation — local evidence

This is the continuation from `4cd8065a`, saved incrementally on
`codex/terminal-screen-workspace` in draft PR #140. It adds nested panes,
OpenSSH configuration import and custom key bindings while qualifying the
previous jump-route, shell, arrangement, discovery and broadcast additions.

## Current verified result

**585 native tests passed, 2 platform-specific tests skipped, 0 failed across
54 test files.** The run used the normal production pubspec and lockfile, pinned
Flutter **3.47.8** / Dart **3.13.7**, and successfully built the application's
native hooks. No GitHub Actions result was queried, awaited or required.

The final source checkpoint is
[`710422b5`](https://github.com/CrispStrobe/CrispCloud/commit/710422b563bf1bae8342ebf7656455526a67288a).
The test run started while those already-frozen source edits were being saved;
its recorded starting HEAD is consequently earlier. Before/after hashes show
no source changes during the run, and all 132 watched paths match the saved
source checkpoint. [The verification receipt](source-checkpoint-verification.json)
records that correspondence. Later evidence, documentation and oracle-tool
commits do not change the tested application code.

| Check | Result | Evidence |
| --- | --- | --- |
| Normal native terminal cohort | 585 passed, 2 skipped, 0 failed; 54 files | [Summary](native-summary.json), [complete log](native-tests.log), [command and source hashes](native-tests.json) |
| Actual Linux PTY | TTY allocation, ANSI/final output, resize, split UTF-8/Unicode input, Ctrl+C and disposal passed within that cohort | [Native log](native-tests.log) |
| Static analysis | 79 terminal-related Dart files, zero issues | [Log](analysis.log), [command and source record](analysis.json) |
| Formatting and whitespace | 79 files checked, zero changes; scoped diff check clean | [Formatter](format.log), [diff check](diff-check.log) |
| Real loopback SSH | 2 passed; interactive SSH PTY case explicitly skipped | [Log](live-ssh.log), [command and unchanged source hashes](live-ssh.json) |
| OpenSSH configuration oracle | 14/14 production importer comparisons against `ssh -G` passed | [Fixtures, command, versions and source hashes](ssh-config-openssh-oracle.json) |
| Interactive shell helpers | Bash 5.2 scalar and array forms, Zsh 5.9 hooks: all 3 scenarios passed | [Source hash and log](shell-smoke.log) |
| Production widget captures | 4 scenarios passed; 16 PNGs inspected, including before/after profile-layout repair | [Visual report](visual/README.md) |
| Workflow configuration | YAML parses; all 169 test references resolve to 103 existing paths using their step working directories | [Receipt](workflow-check.json) |
| Full application web release | Passed with standard release/O4 settings; 4,173 input hashes unchanged | [Summary](web-release-summary.json), [build log](web-release.log), [command and source receipt](web-release.json) |
| Browser execution | 0 tests; Chromium failed before startup because Unix-socket creation was denied | [Startup log](browser-startup-block.log) |

Committed text logs retain their output with trailing whitespace normalized.
Intermediate targeted results overlap with the 585-test cohort and are not
added to that total. The two native skips are the macOS-only real shell fixture
in `terminal_panel_test.dart` and Windows ConPTY in `terminal_process_test.dart`.
The live SSH and visual fixtures are opt-in, separately executed checks.

## What the extra checks establish

The live runner creates disposable client/server keys and two loopback-only
OpenSSH servers. It checks independent host verification for the jump and target,
Unicode command execution through the route, reconnect without another trust
prompt, and rejection of a changed target key without registering a connection.
It uses production SSH code and the normal application dependency graph. Keys,
servers and temporary configuration are cleaned up after the run.

An explicit interactive SSH PTY attempt failed because unprivileged sshd aborted
while writing login records, after `chown(/dev/pts/0, 1000, 5)` failed. The
[environment blocker log](ssh-pty-environment-block.log) preserves the failure.
The final normal live run skips that optional case honestly; separate local Linux
PTY tests pass. No live external SSH host, gateway, real tmux/Screen deployment,
Windows machine, signed macOS application or physical mobile device is qualified.

The full web release attempt reached the compiler, then dart2js exited with
signal 9; the optional WebAssembly probe also exited unsuccessfully. No Dart
compile diagnostic was emitted. Memory pressure is a possible explanation, not
a confirmed diagnosis. The isolated retry **passed** after disabling only the
optional WebAssembly compatibility probe, keeping the release/O4 compiler
settings and production manifests. It produced `build/web` in 216.3 seconds
with `APP_VERSION=1.3.4+27` and `GIT_HASH=710422b5` verified in the artifact.
All 4,173 hashed inputs remained unchanged. The 29,164,959-byte `main.dart.js`
has SHA-256 `046355d47121872062a0389f36cbdcfda14839953a2f94ddba0e44d220e0f88d`.
The [successful build summary](web-release-summary.json) links both attempts and
the complete input hash inventory. This qualifies production release JavaScript
compilation; browser execution and Wasm compatibility remain unqualified.

The Bash/Zsh checks use real interactive shells with pipes. They cover exit
statuses 1 and 7, prompt-hook status/order, Unicode directory encoding and
idempotent repeated setup. Bash 4.4–5.0 compatibility uses the scalar fallback;
those older binaries were not installed in this environment.

Visual captures use production widgets with synthetic sessions and settings;
terminal text in a screenshot is fixture data. The saved-profile footer at
320×320 was repaired. Captured restored four-pane geometry exactly matches the
initial desktop PNG. The captured layout predates the final blocked-divider
no-op fix; that fix is covered by the final native regression. See the visual
receipt for exact widget hashes and font/device limits.

## Integration identity

The initial snapshot audited 32 branch heads and 100 recent PRs. The final
22:36:34 UTC snapshot found 34 branch heads and 100 recent PR heads, including
PRs #155 and #156; its fetch follow-up reached Zotero `6a53294a`. The remote merge
[`454f8a4d`](https://github.com/CrispStrobe/CrispCloud/commit/454f8a4d7452303098b82992b73ee609b02b86f2)
contains every one of those 134 references as an actual ancestor. Verified
squash-equivalent original branch heads are retained as additional parents.

- [Final snapshot, comparisons and fetch follow-up](remote-cutoff-refresh.json)
- [All 134 snapshot references contained](refresh-ancestry-verification.json)
- [Final canonical source verification](canonical-source-cutoff-verification.json)

All **2,391** managed file SHA-256 hashes match the merged tree. All **534**
managed Quds entries match canonical source
`55d46a0fb5f7392dab1a604bc3c15126bd3e380d` by Git blob, mode and size. All **1,857**
legacy parser digests match and retain standalone pin
`4895712158127b2fc930d796e17035c3ca0dac62`. These are source-identity checks;
Office runtime acceptance stays with its own evidence.

## Reproduction

Use the repository's pinned SDK and production lockfile. The 54 exact filenames
are in `native-summary.json`; the recorded command is in `native-tests.json`.
The local wrapper only supplies the installed toolchain/native dependency paths.
Equivalent direct commands are:

```sh
flutter pub get --enforce-lockfile
python3 - <<'PY'
import json
import subprocess
with open('docs/validation/terminal-parity-continuation/native-summary.json') as record:
    files = json.load(record)['suite_files']
subprocess.run([
    'flutter', 'test', '--no-pub', '--concurrency=2', '--reporter=expanded', *files
], check=True)
PY
python3 tool/run_terminal_live_smoke.py --flutter /path/to/flutter
python3 tool/terminal_shell_setup_smoke.py
python3 tool/terminal_ssh_config_oracle.py --dart /path/to/dart
flutter build web --release --no-pub --no-wasm-dry-run \
  --dart-define=APP_VERSION=1.3.4+27 --dart-define=GIT_HASH=710422b5
```

The OpenSSH oracle executes only authored `ssh -G` fixtures, without connecting,
reading keys or executing config directives. Its two portable tools and receipt
carry hashes so future parser changes can be compared against the same cases.
Visual reproduction is documented in [the visual report](visual/README.md).
General platform and manual smoke instructions are in
[the terminal guide](../../terminal.md#build-and-smoke-test-guide).
