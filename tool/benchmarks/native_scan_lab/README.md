# Native scan benchmark laboratory

This is a reproducible **benchmark-only experiment**, not an app dependency or
a shipping storage engine. CrispCloud does not load this library. It compares
the small Rust Cathy-catalog kernel with a richer tree scan, then measures the
cost of returning that tree through Dart FFI and constructing CrispCloud's
actual `FileItem`, `StorageNode`, and `StorageScanResult` objects.

The useful result is the complete bridge measurement, not a promise that a
49–52 ms catalog kernel becomes a 49–52 ms application scan. Source binding,
permission acquisition, app lifecycle, widgets, and persistence are outside
this experiment.

## Files and upstream reference

* `src/lib.rs`: serial catalog comparison, tree scanner, bounded binary packing,
  explicitly owned C ABI, cancellation/progress atomics.
* `src/main.rs`: native benchmark and independent manifest validation.
* `dart/ffi_bench.dart`: Dart bridge, defensive decoding, actual app models,
  synchronous CLI and one-whole-scan-isolate variants.
* `prepare_reference.py`: fetches only two exact upstream reference files, or
  copies them from an explicit local checkout, and checks their SHA-256 hashes.
* `create_oracle.py`: Python filesystem oracle including every file's path,
  logical size, microsecond mtime, every directory, and every subtree total.
* `verify_ffi_contract.py`: small deterministic POSIX contract checks.
* `results/`: unedited five-sample measurement outputs and contract check output.

The reference is CrispSorter commit
[`a36afdffac7092de69a6120b6b3ec2edee35ecbe`](https://github.com/CrispStrobe/CrispSorter/tree/a36afdffac7092de69a6120b6b3ec2edee35ecbe):

| Reference input | SHA-256 |
| --- | --- |
| `crates/crispcat/src/index.rs` | `1886c3e00b060ff8fc502be3f8ae9f79de089b6201e5a2d5c751b0e9b8063cb5` |
| `crates/crispcat/src/scan.rs` | `13ac4d0421d33f4aab320150bdadfe08abe89b279b873b4779c5bf6d77db211f` |

`reference/` is a generated, ignored build input. Consult upstream licensing
notices there; the upstream crate manifest declares MIT, while its repository
has a separate AGPLv3 license with an additional marketplace permission. This
package does not copy those reference sources into the CrispCloud repository.
The fetched reference unit tests are not enabled; contract verification below
tests this experimental bridge separately.

## Reproduce on Linux

Run from the CrispCloud checkout. Prerequisites are Python 3, a Rust toolchain
and platform linker, and Dart. Recorded versions were Python 3.12.14, Rust
1.99.1, and Dart 3.13.7 from Flutter 3.47.8. There is no Flutter application
build, plugin, or new root-pubspec dependency in this procedure.

```sh
cd tool/benchmarks/native_scan_lab
python3 prepare_reference.py
cargo build --release --locked
dart pub get --enforce-lockfile
mkdir -p build
dart compile exe dart/ffi_bench.dart -o build/ffi-bench
```

An already available CrispSorter checkout can replace the network fetch:

```sh
python3 prepare_reference.py --source-checkout /path/to/CrispSorter
```

The same SHA-256 checks apply, so a different local scanner cannot silently
change the reference. Cargo.lock and pubspec.lock pin dependency resolution.
An initial online fetch may be needed; use Cargo/Pub offline modes only when
the pinned inputs already exist in their caches.

Create a fresh synthetic fixture. The shared generator rejects an existing
destination and creates sparse files; it does not read user documents. Keep
all output files outside the scan root.

```sh
python3 ../../create_storage_scan_fixture.py "$PWD/build/fixture"
python3 create_oracle.py "$PWD/build/fixture" "$PWD/build/expected.json"

target/release/scanner-native-lab \
  "$PWD/build/fixture" "$PWD/build/expected.json" 5 \
  > build/rust-results.jsonl

build/ffi-bench \
  "$PWD/target/release/libscanner_native_lab.so" \
  "$PWD/build/fixture" "$PWD/build/expected.json" 5 \
  > build/ffi-default-results.jsonl

SCANNER_FFI_FAST_NAMES=1 build/ffi-bench \
  "$PWD/target/release/libscanner_native_lab.so" \
  "$PWD/build/fixture" "$PWD/build/expected.json" 5 \
  > build/ffi-component-results.jsonl

python3 verify_ffi_contract.py \
  "$PWD/target/release/libscanner_native_lab.so"
```

On macOS the library filename is `libscanner_native_lab.dylib`, and signing
requirements apply. On Windows it is `scanner_native_lab.dll`; the POSIX FIFO
contract checker does not run there. Only Linux x86_64 was built and measured
for this experiment. Other platforms require their own compiler, ABI, path,
permission, and performance verification before interpreting their results.

Do not run competing compilers or scan benchmarks during measurement. The
program runs one warmup followed by five timed repetitions per variant.
Compilation, startup, manifest reading, result printing, and oracle comparison
are excluded. Rust kernel timings stop before validation and final result
destruction. The FFI outer stopwatch includes root encoding, native scan,
packing, decoding, actual Dart model construction, explicit native frees, and
the worker's handoff when the isolate variant is selected.

## Recorded workload and results

Measurements were made on 2026-11-07 in a Linux x86_64 container, kernel
6.18.57, reporting nine logical CPUs and AMD EPYC 9V74. This is a shared
virtualized host, not a controlled hardware performance guarantee. Runs were
serialized with other team benchmarks. The filesystem cache was warm; no
cold-cache, rotating disk, removable drive, network share, mobile device, or
cloud-provider measurements were made.

The common synthetic tree has **24,000 files, 460 descendant directories
(including 20 empty directories), and 359,116,800 logical bytes**. Names are
ASCII; normal timed runs contain no links or errors. Files are sparse, use
five sizes including zero, and are not opened for content hashing. The oracle
checks microsecond mtimes for the richer tree. The original catalog has only
second-resolution timestamps and file entries, so its oracle checks every
file path/size/second timestamp, not directory metadata.

The recorded oracle's file/path/size/mtime SHA-256 was
`95be37ac32d86031340e23be1ce52f590df954f35a57a367a7d1fa36827e0f0e`.
Regenerating the fixture creates new mtimes and therefore a new digest;
generate a new oracle immediately afterward. Absolute path length and tree
location may also affect performance.

| Variant | Median, ms | Five-run range, ms | Output work |
| --- | ---: | ---: | --- |
| Original Rust catalog with jwalk | 51.528 | 47.636–53.261 | File index and size buckets |
| Serial Rust catalog, one metadata query | 45.808 | 45.607–47.024 | Same file index shape |
| Serial Rust tree, one no-follow metadata query | 83.229 | 81.971–88.081 | Directories, diagnostics, bounds, aggregation, sorting |
| Serial Rust tree, strict type checks | 112.052 | 94.710–136.657 | Additional before/after checks |
| Strict Rust tree plus binary packing | 109.259 | 99.822–120.349 | Same tree and 1,564,858-byte wire payload |
| FFI, default path decoder, synchronous CLI | 165.291 | 155.063–185.228 | Complete native-to-Dart model pipeline |
| FFI, default path decoder, one isolate | 206.269 | 191.509–206.683 | Same plus isolate lifecycle/handoff |
| FFI, component decoder, synchronous CLI | 165.021 | 159.459–172.292 | Validated parent/name construction |
| FFI, component decoder, one isolate | 161.893 | 156.877–172.014 | Full isolated bridge with actual models |

Raw samples are retained, including the overlap and variability: packing
does not make scanning faster, and the isolate is not intrinsically faster
than the synchronous path. Do not subtract medians from separate runs as
precise additive costs. For the component/isolate run, component medians were
93.263 ms native scan, 2.511 ms packing, 49.433 ms Dart decoding/validation/model
row creation, and 3.187 ms final immutable tree construction. The outer wall
time also includes allocation/free, lookup, scheduling, and transfer.

Serial Rust matched or exceeded the original parallel catalog kernel on this
fixture. Therefore thread parallelism does not explain a much larger gap
between that kernel and a full application pipeline here. This does not
establish that serial enumeration is best on a different storage device.

## What the richer scanner and bridge preserve

The tree retains directories, including empty directories, and known names
whose metadata is unavailable. Failed/unsupported metadata becomes an unknown
size and a diagnostic; it never becomes a zero-byte success. Links are counted
separately and are not traversed. Ancestors receive partial status and bottom-up
known-byte/file/folder/unknown/link totals. Children are sorted once natively.

The strict variant starts with the no-follow type from directory enumeration,
reads metadata, and checks the no-follow type again. It also checks directories
before and after their listings and performs the extra pre-descent work used
in the comparison. These are type-change guards, not an atomic filesystem
snapshot or proof against adversarial path replacement between system calls.

The C ABI publishes immutable binary pages with at most **500 records and
64 KiB each**, up to 2,048 pages and 128 MiB of packed output. The scan has
200,000-descendant, 200-depth, 1,000-diagnostic, and exact-integer byte limits.
Its retained-metadata budget is an estimate, not a hard process-RSS limit.
The native tree and decoded Dart objects can coexist, so peak memory is larger
than the wire payload. This is bounded complete-result publication, not a
streaming queue with backpressure.

There is no per-file JSON, callback, or FFI crossing. A page contains a compact
parent index, filename, type/known/complete flags, size, microsecond mtime, and
subtree counts. Root ownership remains explicit. Native views are only read
after `cc_run` returns, decoded into owned Dart strings/objects, then released
in `finally`. No typed view or raw pointer escapes into a result model.

The faster decoder preserves these checks:

* Recognized wire version and type, valid row and byte lengths, bounded counts,
  and agreement between batch counts and native summary metrics.
* Exactly one root. Every other node has an earlier parent which is a real
  directory and not a link, preventing parent cycles.
* A nonempty, valid UTF-8 child component without a platform separator, NUL,
  `.` or `..`; Windows additionally rejects alternate `/` and `:`.
* A full path formed from that known parent and that one child, with duplicate
  full paths rejected. This replaces repeatedly normalizing a full path, not
  the containment invariant.
* Exact integer bounds for sizes/subtree bytes, issue limits, and no leftover
  bytes at the end of a page.

Both decoders pass the same independent per-path/size/microsecond-mtime oracle
and every directory total. The separate POSIX ABI checker passed six scenarios:
links/FIFO/hidden/Unicode/backslash/empty folders, linked root, missing root,
pre-cancelled job, depth cap, and bounded diagnostics with suppression counts.
Permission denial while running as root, concurrent replacement races, maximal
entry/memory stress, malformed-memory fuzzing, and all other platforms remain
unverified. The timestamp helper currently leaves pre-epoch mtimes unknown;
the synthetic fixture has modern timestamps. It is not a drop-in replacement
for the app's full metadata contract.

## What app integration would still require

An application implementation should keep the platform access lease active
until native work has acknowledged completion or cancellation, and reject a
result if its bound source/generation changed. The prototype deliberately does
not acquire grants or implement those app gates.

A whole-scan worker should perform the blocking call. `cc_run` must not be a
leaf FFI function. Expose a per-scan handle to the owner, use atomic cancellation
and coarse progress reporting, then wait for completion before freeing buffers
or releasing a security scope. Never destroy a running job, rerun a job while
borrowed pages exist, or retain a page after destruction. The prototype has a
native cancellation flag and tests pre-cancellation; it does not wire live UI
cancellation or progress. A shipping API should enforce one-shot ownership and
add a finalizer as a fallback to explicit close, not as its normal lifecycle.

The native advantage can come from metadata API choice and representation,
not merely using another language. `FileStat.statSync` follows links, so Dart's
separate no-follow checks add work. Rust can obtain no-follow type, size, and
mtime together. On Windows, `DirEntry.metadata()` can reuse directory-entry
information without a further system call; that advantage was not measured
on this Linux host. A native implementation could also use directory-handle
relative traversal for stronger replacement guarantees.

Current Flutter supports an isolated `package_ffi` with build hooks, but that
still needs compiler/ABI packaging and testing for each shipped OS and
architecture. Browser builds cannot use this `dart:ffi` library and must retain
their provider-specific backend. This experiment does not accelerate cloud
pagination or browser file-handle APIs.

Primary documentation supporting the integration constraints:

* [Flutter native bindings and package_ffi/build hooks](https://docs.flutter.dev/interop/bind-native-code)
* [Dart native C interop and macOS library signing](https://dart.dev/interop/c-interop)
* [Build hooks for C or Rust assets](https://dart.dev/tools/hooks)
* [Long/blocking calls must not be leaf FFI calls](https://api.dart.dev/dart-ffi/DynamicLibraryExtension/lookupFunction.html)
* [Native memory view lifetime](https://api.dart.dev/dart-ffi/Uint8Pointer/asTypedList.html)
* [NativeFinalizer lifecycle](https://api.dart.dev/dart-ffi/NativeFinalizer-class.html)
* [Asynchronous native callback ownership and threading](https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.listener.html)
* [Dart FileStat follows symbolic links](https://api.dart.dev/dart-io/FileStat/statSync.html)
* [Rust symlink_metadata](https://doc.rust-lang.org/std/fs/fn.symlink_metadata.html)
* [Rust directory-entry metadata and platform costs](https://doc.rust-lang.org/std/fs/struct.DirEntry.html#method.metadata)
