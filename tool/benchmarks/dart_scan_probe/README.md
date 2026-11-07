# Dart metadata scan benchmarks

These standalone Dart programs separate filesystem primitive costs from the
production analyzer's complete traversal. They use a synthetic fixture and
never read file contents. No Flutter engine is needed to compile or run them.

## Reproduce

Use the Dart SDK bundled with the repository's documented Flutter toolchain.
Run serially while other benchmarks and compilers are idle. From this directory:

```sh
dart pub get
mkdir -p build
SCAN_BENCH_ROOT="$PWD/build/fixture"
python3 ../../create_storage_scan_fixture.py "$SCAN_BENCH_ROOT"
python3 generate_oracle.py "$SCAN_BENCH_ROOT" build/oracle.json

dart compile exe bin/thin_probe.dart -o build/thin_probe
dart compile kernel bin/thin_probe.dart -o build/thin_probe.dill
dart compile exe bin/production_probe.dart -o build/production_probe

./build/thin_probe --manifest=build/oracle.json --mode=aot --output=build/thin-aot.json
dart build/thin_probe.dill --manifest=build/oracle.json --mode=jit --output=build/thin-jit.json
./build/production_probe --oracle=build/oracle.json --mode=aot --output=build/production-aot.json
```

The fixture generator requires a new directory. Reuse an existing fixture by
omitting the creation command and generating its oracle. The default fixture
contains 24,000 files, 460 descendant directories, zero-byte files and sparse
logical sizes; it contains no links. For memory-safe verification, choose a
root small enough for all metadata to fit comfortably in memory.

Each variant runs one warmup followed by five measured scans. `--runs=5`
changes the measured count; `--variants=name1,name2` selects variants. Timing
starts inside the already-running program. Compilation, runtime startup, oracle
loading, verification, metadata hashing and JSON output are excluded.

## Production harness

`bin/production_probe.dart` imports the repository's real
`StorageScanService`, native reader/worker and immutable models. It does not
copy or replace the traversal. Both adapters advertise the reader's actual
before/after no-follow directory checks. The two variants differ in worker
lifecycle:

| Variant | Native reader |
| --- | --- |
| `production_per_directory_guarded` | Existing `Isolate.run` helper for each directory |
| `production_persistent_guarded` | One `NativeStorageScanWorker` owned by the scan session |

The production limits, cancellation and progress callbacks, event-loop yields,
source checks, path checks, partial-result handling, immutable sorted tree and
awaited session cleanup all run unchanged. The stopwatch includes worker
creation, result delivery and worker shutdown. Verification also checks that
the session closed and that final progress counts match the tree.

This harness supplies an available local source with the same native
`p.context`, case-preserving scan `pathKey`, parent/containment comparisons and
`StorageReference` identity construction. Its stat adapter mirrors normal
existing-parent async type/stat checks. It intentionally omits Flutter and
platform access-scope/plugin work. Use the genuine local-backend Flutter
benchmark for the complete app path; do not label this adapter-only measurement
as the deployed application's end-to-end runtime.

## Primitive probes

`bin/thin_probe.dart` is exploratory code, not the production scanner. Every
variant creates flat file records and size buckets. Variants compare recursive
and iterative `Directory.listSync`, async listing with sync/async stat, and
normalization/basename overhead. Thin walkers trust enumeration's entry types.

Checked-tree variants add explicit directory metadata and children, postorder
byte/file/folder totals, before/after directory no-follow checks, and a
no-follow type check after each stat. The validated variant also adds
production-like lexical containment, parent and duplicate checks. The
whole-isolate variant runs that checked tree in one worker for the entire scan.

These prototypes do not implement application source identity, access scopes,
cancellation/progress, limits or partial-error retention. Separate type/stat
checks are portable Dart operations, not atomic descriptor-relative reads.
They cannot close every adversarial rename race. Their narrower responsibility
and their extra flat-list/bucket work must remain explicit in comparisons.

## Independent correctness oracle

`generate_oracle.py` uses Python `os.walk` and
`os.stat(follow_symlinks=False)` to record every relative file path, exact byte
size and microsecond modification timestamp, plus every directory's metadata
and aggregate totals. It rejects links and special files in benchmark fixtures.
Microsecond timestamps use `st_mtime_ns // 1000`, matching the current Dart
`FileStat` precision. Recreate the oracle when regenerating the fixture, since
its modification times depend on creation time.

Every warmup and measured result is verified outside the timed interval. The
sorted `[relativePath, size, mtimeMicros]` digest must match; each checked or
production tree must also match every folder's path, timestamp, bytes and
descendant counts. Missing, duplicated, relocated or changed entries invalidate
the result rather than being reported as a faster scan. The production harness
also verifies complete status, empty diagnostics and child ordering. Hashes
cover metadata records only; no file contents are read.

## Recorded results

The `results` directory contains original warm-cache Linux measurements from
the synthetic 24,000-file fixture. Fixture locations are replaced by its name
for portability. Runtime/compiler metadata and individual samples are retained.
These numbers do not predict cold HDD, removable-drive, NAS or cloud-listing
performance, and they are not content-hashing benchmarks.

Selected median times on Dart 3.13.7, Linux x64:

| Workload | AOT | JIT |
| --- | ---: | ---: |
| Thin iterative sync metadata, flat entries and size buckets | 201.462 ms | 244.001 ms |
| Async listing plus synchronous stat | 194.882 ms | 196.473 ms |
| Async listing plus awaited stat | 820.760 ms | 833.458 ms |
| Checked tree in one whole-scan isolate | 262.687 ms | 259.285 ms |
| Production scanner with per-directory guarded helper | 403.240 ms | — |
| Production scanner with persistent guarded session | 384.623 ms | — |

The last two rows use identical production scanner/native source files and the
same source-adapter semantics; only worker lifecycle differs. The AOT production
measurement is not a release Flutter application measurement. Production source
hashes and the repository commit are recorded in `production-linux-aot.json`.
