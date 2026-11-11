# Directory totals and catalog ingestion: 2026-11-11

The feature branch contains three performance commits through
[`e9dd5db`](https://github.com/CrispStrobe/CrispCloud/commit/e9dd5dbbb8581e16f228d4f51239adf7d0b22660).
The strongest measured improvement is inline folder totals: **655.778 to
321.007 ms**, a **51.0% reduction in elapsed time**, on the same 8,000-file
cached-provider fixture. Durable snapshot saving also improved. The measurements
do **not** establish a consistent improvement in full directory scans or
snapshot reopening.

The additional multi-root batch workflow was restored into source checkpoint
[`43a2c0f`](https://github.com/CrispStrobe/CrispCloud/commit/43a2c0f26ad89f0514ad0c4aff3edb351e017697)
after the execution workspace became unavailable. Its original
[recovery source](recovery/README.md) remains available with exact provenance.
The restored code includes the final publication-status and captured-session
label repairs. Hosted validation of this restored source is recorded below.

## Active implementation

### Aggregate-only inline totals

[`c2cbe78`](https://github.com/CrispStrobe/CrispCloud/commit/c2cbe787f397982b624e7609c4ad4a40b111eb4d)
adds a typed `scanSummary` result and uses it for inline folder measurement.
The summary and detailed report use the same traversal, validation, cancellation,
source checks and limits. A size-only request does not build, freeze or sort a
complete display tree. Full reports continue to retain their file metadata and
directory structure.

Inline publication uses an exact-object row index hint, with a search fallback
if rows move. A different row at the same path cannot receive an old result.
Duplicate progress counters no longer generate redundant pane notifications.
Full scans also share empty leaf child lists and allocate builder child lists
only when needed.

This reduces retained result objects; it does not make traversal constant-memory.
Duplicate detection still retains accepted path keys, and a provider can
materialize a whole directory before the scan's entry budget applies. The pane
still allows two measurements at a time, with 20,000 processed entries and depth
128 per measurement. An outstanding directory read must finish before Stop can
take effect. Unknown sizes, links, partial results and invalidated sources retain
their existing semantics.

### Storage identity calculation

[`e9dd5db`](https://github.com/CrispStrobe/CrispCloud/commit/e9dd5dbbb8581e16f228d4f51239adf7d0b22660)
caches the derived storage identity in a weak per-client cache. Every lookup
rereads all identity inputs before reusing the result. Provider, account, bucket,
namespace, root and persistent-identity changes still invalidate it. Anonymous
sessions retain their existing identity behavior.

This removes repeated digest work during large scans without caching access
grants or authorization decisions. Exact source, current client and generation
checks remain active. Regression cases cover mutated identity fields, equivalent
client instances, getter failures, anonymous transitions, encrypted wrappers and
the real operation backend.

### Durable catalog pages

[`1cbf863`](https://github.com/CrispStrobe/CrispCloud/commit/1cbf863d40e1f6cd0d6b21f629f8354f1d208e27)
adds immutable, pre-encoded page batches and reuses serialized collection rows.
A batch has at most four records, 512 KiB per record and 2 MiB in total.

Native storage drains all submitted writes, including synchronous and
asynchronous failures; each record still uses a flushed temporary file and
atomic rename. Browser storage enqueues the group in one IndexedDB transaction
and waits for its terminal result. These bounds limit a write group, not the
entire scan or import's memory use.

Snapshot saving and reopening avoid repeated serialization and aggregation.
Read-ahead is bounded to four pages; validation still follows manifest order.
Checksums, structural checks, compare-and-swap publication and the existing
format remain in place. Cancellation is checked around expensive work.
A successfully published snapshot, including one confirmed by recovery readback,
remains saved if Stop arrives afterward.

The special case where both publication acknowledgement and recovery readback
fail still needs the unconfirmed-save repair preserved in the recovery bundle.
Do not interpret a cancelled or failed acknowledgement as proof that nothing
was saved.

### Native metadata path processing

The same persistence checkpoint includes a narrow direct-child path shortcut for
canonical absolute, non-root POSIX parents and ordinary single-component names.
Windows, roots, double-leading or trailing separators, relative or non-normalized
paths, backslashes and colons retain the original path processing. Link and type
checks remain active. No new native library or FFI scanner is activated.

This change has deterministic path coverage, but its isolated performance benefit
has not been established. The full traversal observations below include it
together with the other changes.

## Measured results

Baseline:
[`d0a1e93`](https://github.com/CrispStrobe/CrispCloud/commit/d0a1e93e6c094403cb23f0941bfcea580c7b5968).
Performance revision:
[`e9dd5db`](https://github.com/CrispStrobe/CrispCloud/commit/e9dd5dbbb8581e16f228d4f51239adf7d0b22660).

| Workload | Baseline median | Performance median | Observed change |
| --- | ---: | ---: | --- |
| Inline totals; 8,000 pane rows and 8,000 scanned files | 655.778 ms | 321.007 ms | 51.0% less time |
| Save balanced snapshot; 24,000 files and 460 folders; pooled 10 runs per revision | 1,029.551 ms | 772.586 ms | 25.0% less time |
| Import 10,000 collection rows from two identities | 791.156 ms | 741.453 ms | 6.3% less time; ranges overlap |
| Full balanced native scan; pooled 10 runs per revision | 1,250.920 ms | 1,340.004 ms | 7.1% more time; inconsistent sessions |
| Reopen balanced snapshot; pooled 10 runs per revision | 815.106 ms | 862.086 ms | 5.8% more time |

The initial balanced full-scan session was slower, 1,196.377 to 1,535.648 ms.
A matched repeat was faster, 1,409.912 to 1,004.967 ms. Both sessions are retained;
the faster repeat is not substituted for the combined result. The wide
24,000-file directory also measured slower, 805.457 to 922.273 ms. The
1,010-empty-directory fixture changed from 436.645 to 427.894 ms.

Snapshot saves improved in both balanced sessions, although their magnitudes
differed. Wide snapshot save medians changed from 926.650 to 821.745 ms; empty
snapshot saves changed from 73.407 to 51.015 ms. Reopening results are mixed.
There is no supported explanation that assigns this variance to host scheduling
or a particular optimization without another controlled experiment.

The collection import writes 20 pages containing 4,641,463 encoded bytes and
preserves six selected rows. Baseline samples ranged from 689.763 to
1,249.770 ms; performance samples ranged from 466.041 to 861.622 ms. Its 6.3%
median improvement is a modest observation, not a throughput guarantee.

### Protocol and correctness

These are serial Linux x86-64 Flutter test/JIT measurements with Flutter 3.47.8
and Dart 3.13.7. Each session has one warmup and five timed iterations. Fixtures,
compilation, process startup, oracle generation, assertions and cleanup are
outside the stopwatch. Snapshot timing excludes scanning; collection timing
covers encoding, saving and durable publication, followed by untimed reopening
and verification. No file contents are read.

The balanced fixture contains 24,000 files, 460 descendant directories and
359,116,800 logical bytes. The wide fixture has the same files and bytes in one
directory. Independent oracle checks verify file paths, sizes and microsecond
mtimes. Full-scan checks also retain directory metadata, empty folders, child
order and subtree totals. Snapshot reopening verifies the original full result,
including flags, diagnostics and scan timestamps. The collection check verifies
every serialized row, source identity and selected mark after a fresh-store
reopen.

The aggregate-only benchmark verifies totals against the independently checked
full report. It deliberately does not retain per-file display nodes, so its
output is not a replacement for a saved detailed catalog.

[Recovered measurement data](benchmarks/storage-scan-linux-2026-11-11.json)
contains every retained sample and the oracle digests. Records for which only a
summary survived are marked explicitly. Pooled snapshot statistics were computed
from complete logs before the outage; not all underlying samples survived in the
captured output. No missing samples have been reconstructed.

The restored collection benchmark, after applying hosted formatter output, has
SHA-256 `c3ab5063a691b1b7f224ea596ec12f65e2c50ec2a9f6337cf0343b4310226200`,
exactly matching the frozen file used for both original runs. Its restored README
also matches the recorded final SHA-256. The benchmark is now committed at
[`ef3ca3c`](https://github.com/CrispStrobe/CrispCloud/commit/ef3ca3c038bab1a2af7765eb09d395d994431e99).
This establishes source identity; it does not represent a new benchmark run.

These measurements do not establish cold-drive, live cloud, network-share,
mobile or complete native release-app performance. A new AOT comparison was
prepared but never compiled or run.

## Marked-folder batch workflow

The restored implementation adds a reviewable queue for saving snapshots of
marked folders. It captures exact row origins before awaiting,
rejects more than 32 roots, and holds at most two scan/save slots until durable
saving finishes. Reads sharing one remote client are serialized, as are saves.
Each job uses the full scanner so its saved report keeps the complete tree.
Successfully saved reports remain accessible after Stop or a source disconnect.

The implementation includes browser menu and command-palette entry points, per-job
progress and outcomes, opening the exact saved report, and nine locale catalogs.
The initial implementation passed 62 tests across its focused UI, analyzer and
localization gate. The final repair distinguishes an unconfirmed publication from
a definite failure or cancellation and directs the user to saved history before
retrying.

Before restoration, that final repair was untested. Some recovered files came
from executed pre-format edit text, and the last localization/widget changes
were separately marked as proposed. All base hashes and exact contexts were
checked before staging the combined source. An additional review corrected
source labels so another live session sharing a persisted account identity
cannot supply the label for the captured client. The new regression exercises
the actual review dialog, saved label, original totals and original-source loss.

The original recovery bundles remain inert documentation; runtime code is
committed separately. The historical 62-test result and assembly checks do not
establish acceptance of the restored source. Use the later hosted evidence below.

## Validation and remaining gates

The current restored runtime is
[`ef3ca3c`](https://github.com/CrispStrobe/CrispCloud/commit/ef3ca3c038bab1a2af7765eb09d395d994431e99).
Its [workspace run](https://github.com/CrispStrobe/CrispCloud/actions/runs/43035543058)
completed successfully: **913 tests passed**, **163 Dart files checked with zero
formatting changes**, targeted analysis with **zero errors, seven warnings and
60 informational findings**, and a successful final committed-format gate.
The [Chrome job](https://github.com/CrispStrobe/CrispCloud/actions/runs/43035543238/job/130573305650)
also passed at that exact revision, including IndexedDB concurrency and paged
restart recovery.

The first restored run at `43a2c0f` recorded 912 passes and one failed compact
Arabic history interaction. The test called `ensureVisible` and tapped before
the resulting layout frame. The correction waits for that frame and explicitly
requires the button to be hit-testable, preserving the 390 by 780 viewport,
1.5 text scaling and complete offline-history checks. The corrected case passes
in the 913-test run. Hosted formatter output was recovered from its digest-checked
artifact and applied with exact context and before/after Git hash checks.

The separate source-evidence job initially rejected a stale reviewed-source
fingerprint. An audit of all 128 recorded inputs reproduced the prior fingerprint
and identified exactly two changed files: a formatter-only host-key help-string
wrap in the CLI and the palette's batch-command import/dispatch. The other 126
inputs, dependency inventory and root lock remained identical. The
[review record](crypto-audit.md) describes the delta and the
reviewed binding refresh. This is separate from the workspace and browser test
results; it does not establish platform release acceptance.

The separate main workflow's broader tests and platform builds are reported only
when completed at their exact revision; this workspace success does not imply
that every CI job or platform release has passed.

| Completed check | Result and boundary |
| --- | --- |
| Shared scanner, summary, access, workers and inline measurement | 124 tests passed at the first performance checkpoint |
| Durable page batches, snapshot store and collection paging | 64 tests passed |
| Native child paths, links, workers and access lifetimes | 19 tests passed |
| Identity cache, captured targets, sync binding, inline totals and shared scans | 139 tests passed after the identity optimization |
| Initial batch UI, analyzer and localization | 62 tests passed before the final unconfirmed-save repair; source was not committed as active runtime code |
| Benchmark fixtures and persistence oracles | Completed for the retained baseline and performance measurements |
| Hosted workspace behavior step at the performance revision | 814 tests passed; targeted analysis succeeded with 66 nonfatal issues; the final formatting check failed in three CLI files |
| Hosted browser storage and terminal job | Passed, including IndexedDB concurrency and paged restart recovery |

These gates overlap and must not be added into a claimed unique test total.
Earlier broad application, analysis and release-build results in
[the workspace record](workspace-ux.md) are historical and do not validate this
performance revision.

The local browser persistence test compiled and reached loading, but Chromium
startup failed at a restricted socket operation with EPERM. No local browser
assertions ran. The later
[hosted browser job](https://github.com/CrispStrobe/CrispCloud/actions/runs/43026970946/job/130544314870)
passed at the performance revision, including IndexedDB concurrency and paged
restart recovery. The
[hosted workspace workflow](https://github.com/CrispStrobe/CrispCloud/actions/runs/43026970576)
passed 814 behavior tests and its targeted analysis step, then failed the final
formatting check for three CLI files. That correction remains separate from
performance behavior. The main Linux analysis step passed; that old run's broad test step was later
cancelled when newer checkpoints were pushed and is not acceptance evidence.

The workspace disappeared before the final local publication repair, combined
broad regressions, full current static analysis, optimized application build and
source-evidence rerun could complete. Subsequent GitHub restoration and hosted
validation completed the runtime repair and the focused acceptance above.
All source, tests, retained measurements and recovery artifacts are durable on
the remote feature branch. PR #40 remains a draft.

The batch runtime has been restored and validated as recorded above; the recovery
bundles are retained for provenance and should not be reapplied over those files.
Repeat full scans and snapshot loads under the same controlled setup, including
the production AOT probe, before choosing further traversal or read-ahead changes.
Keep native and provider-backed measurements separate and preserve all correctness
and source-lifetime checks.
