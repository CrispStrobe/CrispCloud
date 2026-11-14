# Binary comparison continuation — recoverable progress

## Preserved starting state

- Baseline: `15a389f57e3a8fe9837f786407ce787fe198386f` on `main`.
- Continuation branch: `integration/storage-binary-20261114`.
- The retained NTFS branch `d504409acc779b670de482247f3231a7247dcd92`
  is an ancestor of this baseline. The repository had no open pull requests
  when this continuation started.
- The source roadmap is `docs/storage-capabilities-20261114.md` at that
  baseline. Its dependency exclusions and separate read/write profiles remain
  the implementation constraints.

## This increment

Stage 6's same-offset binary scan, sparse difference index, changed-range
navigation and small Hex windows already exist in the baseline. This
continuation completes their source-capture and resource-bound contracts,
rather than introducing a second comparison interface.

The intended profile captures two read-only inputs, enforces the existing
8 GiB native / 32 MiB browser per-input snapshot ceilings, checks the capture
against a second bounded SHA-256 read, and navigates only owned captured bytes.
Available source metadata and account identity remain additional checks, not
content hashes. Two matching reads are evidence of the observed bytes, not a
claim of atomic snapshots on a provider without that facility.

Work also covers cancellable metadata waits, finite byte/chunk/time budgets,
empty-chunk yielding, failed-open cleanup, and dialog session ownership across
reload, swap, cancellation and disposal. No patch application, recovery write,
physical-device access, new runtime dependency or deployment is introduced.

## Work ownership and checkpoint policy

- Root owns the read-only captured-source implementation, integration review,
  evidence, all commits and all remote reference changes.
- Core comparison scanning/session integration and regression coverage.
- Viewer lifecycle integration and widget regressions.
- Exact toolchain/dependency preparation and validation support.

Concrete increments are saved with ordinary descendant commits to the remote
branch. Existing source, branches and historical qualification receipts are
preserved. Test claims will identify the revision and actual execution; this
initial checkpoint records the plan only and claims no new passing checks.

## Resume guidance

1. Fetch this continuation and `main`, and inspect their current heads.
2. Read this record and the eventual binary comparison profile.
3. Preserve failed/intermediate attempts separately from final receipts.
4. Continue pushing concrete increments; do not rewrite checkpoint history.

## Initial implementation checkpoint

The first implementation owns two captured sources, checks each against a
second bounded SHA-256 read, and uses only those copies for the existing
sparse-index scan and Hex windows. Source/account changes, declared-length
mismatches, byte/chunk/empty-chunk limits, inactivity and elapsed-work limits,
cancellation, and failed-open cleanup have explicit handling and regression
tests. Viewer loads and navigation have generation ownership, with cleanup on
reload, swap, Stop, failure and disposal. The UI labels captured-copy semantics
and the applicable per-input limit in English plus all eight existing translations.

The exact Flutter 3.47.8 / Dart 3.13.7 SDK has been downloaded and its archive
hash verified. Original locked dependencies are still being prepared at this
checkpoint. The new code has been formatted and whitespace checked, but no
new runtime test pass is claimed yet. This checkpoint is recoverable work in
progress; subsequent commits will preserve corrections and actual results.

## Preserved integration and qualification candidate

- `445e48e6` saved the initial continuation record remotely.
- `ef17fafa` saved the initial capture, scan, viewer and regression implementation.
- `ae30d225` merged main's `9e025c44` release-publication fix without source
  conflicts. Both parents remain in history; no prior checkpoint was rewritten.
- [Draft PR #104](https://github.com/CrispStrobe/CrispCloud/pull/104) tracks review.

The next candidate adds a portable suite that exercises the real native and
browser capture implementations, a documented capability profile, and native/
Chrome coverage in the storage workflow. Browser capture takes ownership of
its private contiguous bytes without a redundant full-size copy.

The original locked dependency graph now resolves successfully. The first
strict analysis identified an incorrect test-only `IOOverrides.runZoned`
argument plus lint findings; these were corrected before runtime qualification.
The initial native attempt reached build hooks but no tests: automatic approval
review blocked an unclear GitHub request. Read-only inspection established that
the existing SMB hook requests a public, hash-pinned build dependency through a
bodyless GET. A normal test-command retry uses that evidence; it does not alter
the hook, dependency graph or approval policy. No native pass is claimed from
the interrupted attempt.

## Reviewed candidate before final gates

The normal unchanged build completed after preparing scratch-local Cargo and
Clang for the app's existing native hooks. The first native comparison run
passed **52 tests**, with no failures or skips. The initial widget run found
three test-helper timeouts: `pumpAndSettle` was waiting for intentionally
blocked progress animations. A targeted helper correction preserved those
busy states, and the next widget run passed **9 tests**, including Stop during
navigation after a result is published and rejection of late completion.
These are intermediate working-tree results, not results for an untested later
revision.

Review also preserved canonical backend-equivalent paths and account-scoped
panel selections when ordinary backend stat records omit UI-owned scope.
Explicitly mismatched accounts remain refused. Browser close now drops the
owned memory buffer even if a closed session remains referenced, and the
profile describes transient chunk-consolidation allocations honestly.

The following saved candidate will be qualified with the combined native
comparison/UI suites, actual Chrome execution of the portable capture and
scanner suites, and strict scoped analysis. `run_gate.py` records the exact
commit, all tracked non-document source blobs, the package map, commands and
unedited output before/after each final gate. The production manifests remain
unchanged; earlier blocked/failed setup and test-helper attempts stay separate.

## Source-bound candidate correction

At saved candidate `542c1c8b97643e5ad2e7c44f35b5417ef95c7d6a`, the combined
native gate passed 87 tests and failed one newly added portable reuse-buffer
case. An asynchronous cancellation wrapper let a pause-respecting producer
resume and reuse its array before the pull consumer had captured the first
chunk. Both reads could observe the same incorrect sequence, so the digest
check alone did not detect it. The failed gate and complete source receipt
remain under `intermediate/candidate-542c1c8b/`, alongside the strict-analysis
receipt for one subsequent brace-style finding.

The correction gives `FileOperationControl.bind` an opt-in synchronous delivery
mode and uses it only at the comparison's pull boundaries. StreamIterator's
pause now reaches the producer before its next yield. All other queue callers
retain the previous default. Capture and direct raw-stream reuse regressions
now pass in a focused 28-test native run; full saved-source native and browser
qualification will use the following corrected checkpoint.
