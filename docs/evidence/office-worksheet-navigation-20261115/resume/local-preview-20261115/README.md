# Local worksheet preview continuation — 15 November 2026

This checkpoint continues without waiting on GitHub Actions, as requested by
the user. It records actual local execution at `52f2dec46cdd31c99b7dd0cae8294cbe450056c4`.

## Observed results

| Check | Result |
| --- | --- |
| Pinned toolchain | Flutter 3.47.8 / Dart 3.13.7 / Rust 1.100.0 / Clang 19 installed and executable |
| Locked dependency resolution | Passed; `pubspec.lock` SHA-256 unchanged |
| Formatter | Passed; two files, zero changes |
| Strict focused analysis | Passed; no warnings, infos or errors in the two changed files |
| Worksheet test launch | Stopped before tests: Kindling's real native build exhausted disk space |
| Fresh UI captures / workbook outputs | None from this attempt; visual acceptance remains open |

The formatter, analyzer and failed test launch each reported 7,400 input
hashes with no changed inputs. The existing system-SQLite wrapper completed
its transaction/foreign-key probe and restored the source manifest.

See [the structured checkpoint](remote-checkpoint.json) for exact commands,
versions, source identities, lockfile hashes and returned outcomes. This is
an observation report reconstructed from actual tool results. It is **not**
a copy of the full local log/receipt files.

## Why local execution stopped

The ebook conversion dependency's Cargo release build failed with
`No space left on device (os error 28)`. The filesystem then prevented new
sandboxed commands, including cleanup, from starting. Patch-based cleanup
failed at the same setup stage; the computer-use interface was unavailable.
A narrowly scoped elevated cleanup of reproducible package-index metadata
was rejected because this workspace disables sandbox escalation.

The implementation and formatting checkpoints are already remote. The full
new local receipts and prepared verifiers remain under this workspace's
evidence and `runtime-bootstrap/` directories; disk exhaustion prevented
reading/uploading them. The successful hosted artifact archive and previous
independent acceptance receipts remain safely committed and are separate
from this failed local launch.

## Resume after space is available

Preserve the current local logs before retrying. Free additional workspace
capacity or reclaim completed native build intermediates after verifying the
copied code asset and successful hook receipt. Keep partial/failed receipts
separate; do not disable native hooks, substitute fake libraries, or change
the dependency graph to get past this environment failure.

The runtime environment is already prepared:

```bash
source /workspace/scratch/110418c5427b/runtime-bootstrap/flutter-env.sh
source /workspace/scratch/110418c5427b/runtime-bootstrap/native-env.sh
```

From the app checkout, retry in a fresh gate output directory:

```bash
OFFICE_NAVIGATION_PREVIEW=1 python3 tool/with_ci_system_sqlite.py \
  flutter --suppress-analytics test --no-pub --reporter expanded \
  test/widget/office_sheet_navigation_workflow_test.dart
```

Then inspect the actual rename dialog and 390-pixel Arabic host captures;
verify their source/font/dimension receipts and the six saved navigation
workbooks independently. No later GitHub host-job outcome is assumed, and
GitHub queue monitoring should not resume as a completion dependency.
