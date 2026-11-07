# Closing the local scan performance gap

The original comparison was real, but it compared different amounts of work:
about 899 ms for CrispCloud's complete guarded Dart analyzer and 49 ms for
CrispSorter's Rust file-index kernel. Profiling and smaller matched experiments
show that both application overhead and the metadata/representation path matter.
They do not support attributing the whole difference to Dart compilation or
Rust's parallel traversal.

The feature branch now includes a faster **pure-Dart production scanner**.
It measures 500 ms through the actual Flutter local adapter and 385 ms for
the same scanner compiled to AOT with a minimal local adapter. A separate
Rust-to-Dart FFI experiment measures 162 ms including conversion to the real
application tree. That experiment is preserved for reproduction, but it is
not linked into the app and is not yet a replacement for its platform/source
lifecycle.

## Workload and comparison boundaries

All main experiments use the same warm Linux fixture: 24,000 sparse files,
460 descendant directories including 20 empty directories, and 359,116,800
logical bytes. No file contents are hashed or read. The host reports AMD EPYC
9V74 and nine available CPUs; it is a shared virtualized environment. Flutter
is 3.47.8, Dart 3.13.7, and Rust 1.99.1. Startup and compilation are excluded.

Unless stated otherwise, a mode has one warmup followed by five timed runs.
Normal timed fixtures use ASCII names and contain no links or failures.
Correctness checks run outside the stopwatch. The Flutter benchmark checks
every file path and size, counts, and total bytes against an independently
generated manifest. The AOT and richer native experiments also validate file
microsecond mtimes, directory paths, empty directories and subtree aggregates.
The production AOT harness additionally checks directory mtimes and child order.
Separate deterministic tests cover unusual names, links, errors, and lifecycle.

These are not cold-drive, network-share, cloud-API, or mobile measurements.
A native release of the complete Flutter application has not been benchmarked.
The AOT core harness explicitly omits Flutter platform access-grant integration.

## What changed in the app

The implementation is checkpointed in
[`dec6e90e83532612b326d5b7c7ff76c0ccfbd966`](https://github.com/CrispStrobe/CrispCloud/commit/dec6e90e83532612b326d5b7c7ff76c0ccfbd966).

| Complete Flutter adapter scan | Median, ms | Five-run range, ms |
| --- | ---: | ---: |
| Original operation backend | 6,435.569 | 6,188.108–7,263.964 |
| First synchronous background reader, one worker per directory | 899.095 | 876.555–944.697 |
| Current persistent worker and optimized traversal | **500.381** | **487.567–516.123** |

The latest change is **1.80 times faster** on the file-heavy fixture. Compared
with the original operation backend, the complete scan is **12.86 times faster**.
On 1,010 empty directories, the latest change improves 855.743 ms to
**155.165 ms** (122.488–162.179 ms), a **5.52 times** improvement.

The measured production path includes worker creation and shutdown, per-directory
access wrappers, source checks, path validation, entry/depth/byte/diagnostic
limits, cancellation checkpoints, and immutable tree aggregation. The app's
benchmark does not install a progress callback; the production AOT harness
does and records its invocation count. Raw samples and the exact fixture
validation are in [the production benchmark data](benchmarks/storage-scan-linux-2026-11-07.json).

Five specific changes remove avoidable work:

1. **One worker per scan.** A session reuses a metadata isolate for all
   directories, drains pending reads, and closes on success, cancellation,
   root failure, and source invalidation. Overlapping scans own separate
   sessions. Access grants remain on the originating isolate and are held
   until each directory operation finishes.
2. **One owner of directory type verification.** The native reader already
   checks each requested directory without following links before and after
   its listing. Only a reader advertising that capability can suppress the
   scanner's duplicate generic pre-descent stat. Unguarded sources retain it.
3. **Canonical direct-child validation.** For ordinary POSIX and Windows
   paths, a normalized parent plus a single valid name establishes direct
   child membership without reparsing the full path repeatedly. Aliases,
   unusual path styles and nonmatching paths retain the original predicates.
   Duplicate path-key detection, malformed-name rejection and source checks
   remain active.
4. **Budgeted event-loop yields.** At directory boundaries, traversal yields
   once 32 directories or eight milliseconds have elapsed, in addition to the
   existing per-entry and aggregation checkpoints. Cached and denied directory
   trees still allow event-loop cancellation; normal asynchronous I/O also
   yields. This is not a hard eight-millisecond latency bound: an in-flight
   native directory read finishes before the scanner can stop it.
5. **Single-pass aggregation.** A folder's byte/count/completeness fields are
   accumulated together instead of repeatedly folding its children.

The scanner now depends on a narrow `StorageScanSource` contract instead of
Flutter's file-mutation service. That lets the actual production scanner and
native metadata implementation run in an independent AOT benchmark.

## Why the first background-reader implementation cost so much

The [baseline profiler](../tool/benchmarks/scan_profile/README.md) retains a
frozen instrumented version of the approximately 899 ms background-reader
implementation and all raw samples. It does not profile the original 6.4 s
operation-backend version. It used one warmup and three measured JIT runs, so its diagnostic medians
should not be substituted for the five-run production measurements.

| Baseline work | Approximate median | Meaning |
| --- | ---: | --- |
| Root and descendant directory stats | 203 ms | 461 calls through the generic local adapter |
| Native listings, caller side | 478 ms | Worker startup, native metadata, scheduling and return |
| Actual synchronous work inside those workers | 326 ms | Nested inside the listing row |
| Entry path validation | 104 ms | Repeated path normalization/containment/parent checks |
| Explicit directory event-loop delays | 48 ms | One delay per directory |
| Tree aggregation and sorting | 24 ms | Final immutable node construction |

The rows overlap and must not be added as independent costs. Instrumentation
itself increased the full median by about 42 ms. The difference between the
nested worker/handoff and worker-work medians suggests approximately 141 ms
of startup/scheduling/transfer overhead, not a precisely isolated copying cost.

In particular, [`Isolate.run`](https://dart.dev/language/isolates) returns its
final result by transferring ownership through `Isolate.exit`; it does not
copy that returned graph. A persistent worker uses ordinary port messages,
which have different costs for mutable objects. Its actual benefit has been
measured rather than assuming all old handoff overhead disappears.

## How far pure Dart gets

[Reproducible pure-Dart probes](../tool/benchmarks/dart_scan_probe/README.md)
separate filesystem calls, path processing, tree construction, and the complete
production core. The same independent oracle is used across equivalent modes.

| Dart AOT experiment | Median, ms | Scope |
| --- | ---: | --- |
| Iterative synchronous listing and one file stat | 201.462 | Flat metadata/index workload, no app lifecycle |
| Recursive asynchronous listing plus awaited per-file stat | 820.760 | Illustrates the cost of serial async metadata scheduling |
| Strict tree and type checks | 249.169 | Folders, empty directories and aggregation |
| Strict tree in one whole-scan isolate | 262.687 | Includes worker creation and result delivery |
| Actual optimized scanner, guarded per-directory workers | 403.240 | Production core with minimal local adapter |
| Actual optimized scanner, persistent guarded session | **384.623** | Same production core and awaited session shutdown |

The last two modes include the real scanner's path/source checks, bounds,
progress callbacks and cancellation checkpoints. Both perform one root stat
and 461 directory listings per scan; the persistent mode starts and closes
exactly one worker. Their respective five-run ranges are 389.029–413.856 ms
and 370.359–394.638 ms. They are not complete release-app timings.

AOT alone did not erase the gap. The simple iterative scan was 201 ms AOT
versus 244 ms JIT; the strict whole-worker probe was 263 ms AOT versus 259 ms
JIT. Those probes omit parts of the app contract and are useful bounds, not
shipping replacements. The 500 ms Flutter test result and the 385 ms AOT-core
result also use different adapters, so their difference cannot be assigned
entirely to compilation mode.

Pure Dart can therefore deliver a responsive analyzer and substantial speedups.
There is no demonstrated 50 ms pure-Dart implementation for this fixture.
Moving more of the full traversal into one isolate, using a compact parent/name
table, and constructing display objects lazily are reasonable further
experiments; they still need the live-source, access-scope, cancellation and
partial-result bridge that the simpler whole-worker probe omits.

## What FFI can realistically buy

The [native benchmark laboratory](../tool/benchmarks/native_scan_lab/README.md)
compares the original public CrispSorter kernel with richer Rust work and an
actual Dart FFI bridge. It pins the upstream source commit and hashes without
adding a native dependency to the application.

| Native/FFI experiment | Median, ms | Five-run range, ms |
| --- | ---: | ---: |
| Original CrispSorter Rust catalog kernel, jwalk | 51.528 | 47.636–53.261 |
| Serial Rust catalog with equivalent file-index shape | 45.808 | 45.607–47.024 |
| Rust tree, one no-follow metadata query | 83.229 | 81.971–88.081 |
| Rust tree with stricter type-change checks | 112.052 | 94.710–136.657 |
| Strict Rust tree through FFI into real Dart models, one isolate | **161.893** | **156.877–172.014** |

Serial Rust matches or exceeds the parallel catalog kernel here. More threads
therefore do not explain or automatically fix the much larger application gap
on this warm fixture. Device-specific parallelism still needs separate tests.

The FFI stopwatch includes native scanning, bounded binary packing, decoding,
path validation, `FileItem`/`StorageNode` construction, explicit frees, and
isolate handoff. The result retains all 24,000 file paths/sizes/microsecond
mtimes, 460 directories, empty folders, and every subtree total. The binary
payload is 1,564,858 bytes. Component medians for that series are about 93 ms
scanning, 2.5 ms packing, 49 ms Dart decoding/row construction, and 3.2 ms final
tree freezing. Separate-run component medians are not an exact sum of wall time.

This shows a credible native acceleration path, not a 49 ms complete analyzer.
It also shows why measuring only the native function is insufficient.

[`FileStat.statSync`](https://api.dart.dev/dart-io/FileStat/statSync.html)
already calls the operating system, but follows symbolic links. The Dart
reader therefore performs a separate no-follow type check. Rust's
[`symlink_metadata`](https://doc.rust-lang.org/std/fs/fn.symlink_metadata.html)
can return type, size and mtime without following the final link in one metadata
operation. API choice, marshaling, object creation and data layout all matter;
the advantage is not solely the language used for the loop. The strict Rust
comparison also retains additional checks, rather than treating fewer guards
as an equivalent performance optimization.

The promising FFI boundary is **one scan job with coarse metadata batches**.
The experiment uses pages of at most 500 records and 64 KiB, with parent IDs
and names instead of repeatedly encoding full paths. There is no per-file
JSON, callback or FFI crossing. A Dart traversal calling a native metadata
function for every file could improve API costs, but has not been measured
here and still retains traversal/model overhead on the Dart side.

## Recommended architecture and remaining work

Keep the optimized Dart implementation as the portable scan engine. For native
desktop acceleration, promote a richer Rust scanner behind a narrow C ABI only
after its application contract and platform builds are verified. Flutter's
[current FFI package/build-hook workflow](https://docs.flutter.dev/interop/bind-native-code)
can package such an isolated native component.

The intended flow is a per-scan handle, background scan, bounded parent/name
batches, validated Dart result, then the existing views and snapshot store.
The native scan can share algorithm and catalog data structures with
CrispSorter, while preserving empty directories, partial errors, unknown sizes,
and the richer analyzer model that the file-only catalog kernel lacks.

Before using the experimental library in the app, implement and verify:

- Platform access leases and source/generation checks through cancellation and
  completion, including Windows, macOS, Linux, iOS and Android builds as needed.
- Live cancellation/progress signaling. The native experiment has atomics but
  only tests pre-cancellation; it is not wired to the UI. A long scan must be
  a [non-leaf FFI call](https://api.dart.dev/dart-ffi/Native/isLeaf.html) in a
  worker, so it does not block the runtime's synchronization or UI event loop.
- Explicit one-shot buffer/handle ownership and cleanup after completion,
  before releasing access scopes. The present bounded pages publish a completed
  result; they are not a streaming queue with backpressure or a hard RSS bound.
- Metadata parity and adversarial cases. The prototype currently leaves
  pre-epoch mtimes unknown, and has not verified live replacement races,
  permission-denied behavior as a non-root user, maximal stress, or malformed
  native-memory fuzzing. Its deterministic POSIX checks cover links, FIFO,
  Unicode/hidden/empty entries, invalid roots, depth and diagnostic limits.

FFI accelerates native local scanning. Cloud listings and browser-granted file
handles still use their own APIs, so their latency needs provider-specific
work. The visualizations and saved snapshot format already consume a shared
tree and do not need separate implementations for each scan engine.

## Verification of this change

The final analyzer regression run passes **148 tests** across scanner,
native reader/worker, access scopes, pagination, both maps, saved snapshots,
widgets and original-source navigation. The 11 changed production/test Dart
files have clean targeted static analysis. The standalone Dart and native
benchmark packages also analyze and compile successfully; the relocated
baseline profiler passes its preparation-only compile check.

The app's release JavaScript web build passes with the current scanner code
(`dec6e90`, Flutter 3.47.8 / Dart 3.13.7). Native acceleration remains an
experiment: this validation does not claim signed native application startup,
live cloud-account testing, browser-native FFI support, or cross-platform
native-library release verification.
