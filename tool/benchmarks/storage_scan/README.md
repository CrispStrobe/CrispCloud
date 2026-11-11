# Directory scan and snapshot comparisons

These opt-in Flutter benchmarks measure the real local scan adapter and native
snapshot storage. They never read file contents. Use disposable synthetic
fixtures, keep all benchmarks and compilers serialized, and compare revisions on
the same host with the same fixtures and runtime.

## Fixtures and independent truth

Create each fixture once, outside either source checkout. The destination must
not already exist. The balanced shape preserves the original workload. File
sizes are logical sparse-file sizes, not allocated disk usage.

| Shape | Files | Descendant folders | Purpose |
| --- | ---: | ---: | --- |
| `balanced` | 24,000 | 460 | File-heavy traversal through several levels |
| `wide` | 24,000 | 0 | One large directory, result retention and child sorting |
| `empty` | 0 | 1,010 | Directory enumeration, scheduling and cancellation checkpoints |

From a checkout containing the benchmark infrastructure:

```sh
SCAN_BENCH_FIXTURES=/absolute/disposable/scan-benchmarks
mkdir -p "$SCAN_BENCH_FIXTURES"
for shape in balanced wide empty; do
  python3 tool/create_storage_scan_fixture.py "$SCAN_BENCH_FIXTURES/$shape" --shape "$shape"
  python3 tool/benchmarks/dart_scan_probe/generate_oracle.py \
    "$SCAN_BENCH_FIXTURES/$shape" "$SCAN_BENCH_FIXTURES/$shape.oracle.json"
done
```

The Python oracle independently walks the completed fixture with no-follow
metadata reads. It records every file path, size and microsecond modification
time, every directory's modification time, and each subtree's byte/file/folder
totals. Missing roots, traversal errors, links and special files fail oracle
generation. Keep fixture contents and timestamps unchanged for both revisions.

## Comparable full-scan and snapshot runs

Use the same copies of these harness files in baseline and final worktrees:

- `test/storage_scan_benchmark_test.dart`
- `test/storage_scan_snapshot_benchmark_test.dart`
- `test/support/storage_scan_benchmark_oracle.dart`

They use APIs present before the summary scan optimization. Copy only the
harness files into the baseline worktree; keep its production sources and
dependency lockfile at the baseline revision. Record that revision and the
harness source hashes with the results. Resolve dependencies before measuring.

Run from each worktree, with the revision label set to its actual source commit:

```sh
export STORAGE_SCAN_BENCHMARK_REVISION=actual-source-commit
export STORAGE_SCAN_BENCHMARK_RUNS=5
for shape in balanced wide empty; do
  export STORAGE_SCAN_BENCHMARK_ROOT="$SCAN_BENCH_FIXTURES/$shape"
  export STORAGE_SCAN_BENCHMARK_MANIFEST="$SCAN_BENCH_FIXTURES/$shape.manifest.json"
  export STORAGE_SCAN_BENCHMARK_ORACLE="$SCAN_BENCH_FIXTURES/$shape.oracle.json"
  flutter test --no-pub --concurrency=1 --tags benchmark --run-skipped \
    test/storage_scan_benchmark_test.dart
  flutter test --no-pub --concurrency=1 --tags benchmark --run-skipped \
    test/storage_scan_snapshot_benchmark_test.dart
done
```

If the environment needs a repository build wrapper, use the same wrapper for
both revisions and record that fact. Do not replace runtime dependencies solely
for one side of the comparison.

Each benchmark performs one unmeasured warmup followed by five measured samples.
Compilation, process startup, oracle loading, correctness checks and digest
calculation are outside the stopwatch. Full scans include worker startup and
shutdown, access wrappers, source/path checks, bounds, progress callbacks,
cancellation checkpoints, immutable nodes and sorted children.

Every scan is checked against the independent metadata oracle and final progress
counts. The output includes all samples, median/minimum/maximum, callback counts,
source revision, and a stable metadata fingerprint. The original size-only
manifest remains supported, but an oracle is required for a fully verified
baseline/final comparison. A run without one explicitly reports that omission.

Snapshot timing starts after a separately verified full scan. Save and reopen
are measured separately, including durable native storage operations. Each load
must match the complete original snapshot fingerprint, including its metadata,
subtree totals, scan timestamps, flags and diagnostics. The stable metadata
fingerprint in the final record can also be compared across source revisions.

## Scope of conclusions

These are warm local filesystem and Flutter-test measurements. They do not
predict cold storage, remote provider latency, release-app UI latency, or memory
usage. Compare full-tree scans with full-tree scans. Report summary scans as a
separate mode because they intentionally do not retain descendant display nodes.
Keep raw samples and correctness evidence; do not turn timing expectations into
machine-dependent test pass/fail thresholds.
