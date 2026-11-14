# Captured binary comparison qualification

This continuation advances the binary-comparison part of stage 6 in the
[storage roadmap](../../storage-capabilities-20261114.md). The
[capability profile](../../binary-comparison-profile.md) defines its source,
identity, work-limit and cleanup contracts. It reuses the existing same-offset
scanner, sparse range index and Hex navigation.

## Qualified source and results

The completed local gates below ran against saved source
**`e52ea1f9399c2547978bb497073adcee5022cc81`**, tree
`b9a1a837770bb6087fcbe500d9429af5cfff2f84`, on Linux x86-64 with
Flutter **3.47.8** / Dart **3.13.7**. The original locked dependency graph
resolved successfully and both production manifest files remained unchanged.
Later documentation/evidence commits do not retroactively qualify new runtime
source changes.

| Gate | Observed result | Evidence |
| --- | --- | --- |
| Eight native comparison, encoding and widget suites | **92 passed; 0 failed; 0 skipped**, exit 0 | [Summary](native-summary.json), [receipt](final-native-receipt.json), [raw log](final-native.log), [compressed JSON events](final-native-events.json.gz) |
| Strict analysis of all 10 changed Dart files | **No issues found**, exit 0 with `--fatal-infos` | [Receipt](final-analysis-receipt.json), [raw log](final-analysis.log) |
| Source/dependency identity around each completed gate | **8,111 tracked non-document paths unchanged**, unchanged package map, no source mismatches | Both completed gate receipts and their complete compressed source inventories |
| Chrome portable capture and scanner gate | **Not executed: browser startup blocked by the environment**; 29 test cases intended | [Interrupted attempt](intermediate/browser-sandbox/README.md) |
| Hosted GitHub Actions | **Queued at observation**, no hosted pass claimed | [Source-head status](hosted-ci-status.json) |

The Chrome attempt reached browser startup, where Chromium's required socket
failed with `Operation not permitted`. No comparison test executed in Chrome.
The waiting run was interrupted with exit 130; its runner did not complete an
after-source check or receipt. The ordinary permission-escalation request was
also rejected before starting a retry. The failed launch and its pre-run source
inventory are retained separately, and no browser qualification is inferred
from native tests or compilation. The storage workflow contains the actual
Chrome command for execution in a permitted runner.

## What the tests cover

- Two bounded reads with matching SHA-256 digests, unchanged metadata that
  conceals changed bytes, captured account identity, equivalent backend paths,
  frozen metadata tokens, and unknown lengths that become known.
- Declared length underruns/overruns, platform byte ceilings, chunk and empty
  chunk budgets, invalid bytes, stalled reads/metadata, cancellation and read
  errors during either capture pass.
- Owned returned windows, immutable captured navigation after live content
  changes, sparse range lookup, unmatched tails, and existing text/encoding
  behavior.
- Failed-open storage cleanup and close ownership; mode changes, swap, Stop
  during preparation or published navigation, disposal, stale asynchronous
  completion and all existing dialog locales.
- Pause-respecting producers that reuse a buffer, including a delayed other
  stream, unequal boundaries and a 100 KiB chunk that crosses the internal
  64 KiB copy boundary. A known digest independently computed for this fixture
  prevents the two-read check from merely reproducing the same capture error.

The largest physical comparison fixture in these suites is 9 MiB. Logical
budget checks do not establish successful 8 GiB native or 32 MiB browser end-to-end
runs. Linux VM/widget results do not qualify native packaging on other targets,
and Chrome runtime qualification remains outstanding.

## Exact attribution and reproduction

[run_gate.py](run_gate.py) checks all tracked non-document blobs against HEAD
before execution, preserves the original command/output and checks the same
inventory and package map afterward. The native and analysis inventories are
identical and retained under the filenames referenced by their receipts:

- [final-native-source.json.gz](final-native-source.json.gz)
- [final-analysis-source.json.gz](final-analysis-source.json.gz)

Both decompress to source-inventory SHA-256
`41651296d2b037df56a26e3dccadc5acc9e090be55982eaabc8d8a2bcb64d438`.
The Git tree deduplicates identical compressed blobs. Gzip files preserve the
complete original bytes; their original/stored hashes and lengths are recorded
in the associated summaries and [files.json](files.json).

The receipts contain exact commands, source commit/tree, tool paths, timings,
exit status, runner hash and package-map hashes. On another machine, use the
pinned SDK and original manifests, resolve dependencies with
`flutter pub get --enforce-lockfile`, then substitute the available Flutter/Dart
executable for the recorded scratch-local wrapper. The eight native suite paths
and ten analysis paths are listed in the receipts. The browser command is:

```sh
flutter test --no-pub --platform chrome --reporter expanded \
  test/binary_comparison_portable_test.dart \
  test/binary_comparison_limits_test.dart
```

Native build-hook prerequisites and verified SDK/compiler provenance are
documented in [setup-notes.md](setup-notes.md),
[toolchain.json](toolchain.json) and
[environment-validation.json](environment-validation.json).

## Preserved failures and remote history

[PROGRESS.md](PROGRESS.md) records incremental remote checkpoints. Setup failures
and working-tree test attempts remain under [intermediate/](intermediate/).
The saved candidate `542c1c8b` exposed a reusable-buffer capture regression
(87 native tests passed, one failed) plus one analysis lint. Its unedited
source-bound receipts remain in
[candidate-542c1c8b](intermediate/candidate-542c1c8b/README.md). The correction at
`e52ea1f9` supplies the source for the final native/analysis results above.

GitHub reports that [PR #104](https://github.com/CrispStrobe/CrispCloud/pull/104)
was merged at candidate `542c1c8b` while qualification was in progress. The
buffer correction and this evidence therefore belong to a follow-up review on
the same recoverable remote branch. No failed candidate is presented as a
passing final gate, and no later source change inherits these results without
an explicit source comparison or new execution.

The implementation adds no runtime dependency. Two matching reads bind observed
captured bytes; they do not prove an atomic provider snapshot or simultaneous
capture of both inputs. Patch application, recovery/carving/rescue imaging,
filesystem writes and the transfer-bandwidth stage remain separately scoped.
