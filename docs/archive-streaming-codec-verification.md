# Native streaming archive writer verification

Verification date: 2026-11-13 (Europe/Berlin).

## Result and scope

The native writer processed **2,147,483,665 bytes (2 GiB + 17)** through each of
ZIP, TGZ and 7z without collecting the source or complete archive in memory.
Python's ZIP/TAR readers and libarchive's 7z reader independently consumed the
complete outputs and checked the exact uncompressed length and zero content.
A second ZIP case processed **4,294,967,313 bytes (4 GiB + 17)**, exercising real
ZIP64 member sizes and the ZIP64 footer; Python `zipfile` read the complete
member and verified its CRC.

These are large **uncompressed member** tests. The deliberately compressible
fixtures have small physical archive sizes, recorded below. They do not prove
that a physical archive larger than 2 GiB can be uploaded or replaced by every
storage backend. The workspace had approximately 519 MiB of free disk at the
start of this verification. Tests exercised actual generated payload bytes,
not merely advertised sizes. No large binary fixture is checked into Git.

The writer has an explicit **8 GiB native resource limit**, including a total
expanded-content bound. It does not claim unlimited size. Publication, cloud
backend behavior, recovery and app interaction are separate integration layers.
The matching source-reader verification is documented in
[archive-streaming-reader-verification.md](archive-streaming-reader-verification.md).

## Implementation covered

- `lib/services/archive_streaming_writer.dart`: conditional native API and
  explicit capability query.
- `lib/services/archive_streaming_writer_io.dart`: bounded ZIP/ZIP64, TAR,
  TGZ/GZIP and 7z output with awaited sink backpressure and cancellation checks.
- `lib/services/archive_streaming_writer_stub.dart`: unsupported-platform
  response, allowing the existing bounded portable path to remain separate.
- `test/archive_streaming_writer_test.dart`: Flutter test registrations, including
  an opt-in large-payload case.
- `test/support/verify_archive_streaming_writer.dart`: the checks that were
  actually run directly on the local Dart VM.
- `test/support/check_archive_streaming_writer.py`: independent readers.

ZIP uses native raw DEFLATE, incremental CRC-32, data descriptors and a bounded
central-directory model. UTC modification seconds are emitted as ZIP extras
during writing, avoiding a second complete in-memory metadata rewrite. ZIP64
records cover large member sizes, offsets, central directories and entry counts.

TGZ streams TAR records through native raw DEFLATE and writes a gzip trailer.
A supplied validated gzip header is retained. The TAR writer's existing
preservation inspection remains authoritative for rewrites.

7z privately spools packed payloads because its leading signature header needs
the trailing header's final offset, size and CRC. Each nonempty file has its own
folder. Level 0 uses Copy; levels 1–3, 4–6 and 7–9 use independently reset LZMA2
blocks with 64 KiB, 256 KiB and 1 MiB dictionaries respectively. Provider chunks
are coalesced into these bounded blocks. These are bounded writer profiles, not
a promise of identical output or compression ratio to desktop 7-Zip presets.

An independent check caught a compatibility issue that a same-library round trip
missed: omitting empty `SubStreamsInfo` is accepted by the pinned Koni reader but
rejected by libarchive 3.7.4. The new writer emits the explicit empty structure.
Both Copy and LZMA2 output then passed the independent oracle.

## Reproduction

Run from the repository root after dependencies have already been resolved.
The actual SDK used here was:

```text
/home/agent/.codex/skills/remote-skills/office-recovery-0905ba96fd2d/flutter-3.47.8/bin/dart
```

The environment lacked `/tmp`, so these runs supplied a writable temporary
directory inside the workspace:

```bash
mkdir -p /workspace/scratch/4d61c38502be/native-test-temp
export TMPDIR=/workspace/scratch/4d61c38502be/native-test-temp
CRISP_DART=/home/agent/.codex/skills/remote-skills/office-recovery-0905ba96fd2d/flutter-3.47.8/bin/dart

"$CRISP_DART" --packages=.dart_tool/package_config.json \
  test/support/verify_archive_streaming_writer.dart --oracle

"$CRISP_DART" --packages=.dart_tool/package_config.json \
  test/support/verify_archive_streaming_writer.dart --oracle --large

"$CRISP_DART" --packages=.dart_tool/package_config.json \
  test/support/verify_archive_streaming_writer.dart --oracle --zip64-large

"$CRISP_DART" analyze \
  lib/services/archive_streaming_writer.dart \
  lib/services/archive_streaming_writer_io.dart \
  lib/services/archive_streaming_writer_stub.dart \
  test/archive_streaming_writer_test.dart \
  test/support/verify_archive_streaming_writer.dart
```

On another machine, use its resolved Dart executable and an existing writable
temporary directory. The standalone driver does not run `pub get` or use an
external archiver executable. Python and libarchive are verification tools,
not runtime dependencies of the writer. The first two large runs preceded the
final compression-tier refinement; the default 256 KiB profile and generated
large source block boundaries are unchanged. The final small oracle exercised
all three final LZMA2 tiers. The final header budget was aligned to the reader's
16 MiB budget; none of the fixtures approach it.

### Software observed

| Component | Version |
|---|---|
| Dart SDK | 3.13.7 stable, linux_x64; SDK build 2026-10-22 |
| Toolchain location | Flutter 3.47.8 bundle; the Flutter engine was not used for these checks |
| Python | 3.12.14 |
| Python zlib runtime | 1.3.2 |
| libarchive | 3.7.4 |
| Koni archive/codecs dependencies | 0.9.0, from resolved package configuration |
| Dart archive dependency | 4.6.0, from resolved package configuration |

The Python zlib version describes the independent oracle, not an assertion
about the Dart SDK's internally linked zlib version.

## Focused test results

The final standalone small run completed successfully with the following
independent results (each fixture contains 1,600,020 regular-file payload bytes):

```text
PASS independent deflated.zip
PASS independent stored.zip
PASS independent compressed.7z
PASS independent fast.7z
PASS independent maximum.7z
PASS independent stored.7z
PASS independent plain.tar
PASS independent compressed.tgz
PASS streamed ZIP/7z/TAR/TGZ/GZIP content and metadata round trips
PASS size/path/encryption/cancellation/backpressure guards
PASS ZIP64 65536 entries
PASS ZIP64 record/count and >4GiB member preflight
```

The checks cover a Unicode path, incompressible and repeated input across chunk
boundaries, an empty file, an empty directory, exact integral UTC modification
seconds, and POSIX modes. GZIP separately retained a supplied original filename,
comment, timestamp and OS header while decompressing to the expected payload.

Guards reject unsafe paths, logical and packed size excess, short/growing source
streams and a protected streaming profile. Cancellation stops and closes the
source iterator. A deliberately blocked sink prevents ZIP from consuming the
source ahead of its output. Every observed public output chunk was at most
256 KiB. ZIP64 was also checked independently using a 65,536-entry archive.

The focused Dart analyzer returned `No issues found!`.

## Large-payload measurements

All four cases contained one member, `large.bin`, with mode `0644` and UTC mtime
`2026-11-12T01:02:03Z`. The source generated zero bytes in bounded chunks.

| Format / profile | Actual uncompressed bytes | Physical output bytes | Writer duration | Sampled RSS increase | Largest public output chunk |
|---|---:|---:|---:|---:|---:|
| ZIP / DEFLATE | 2,147,483,665 | 2,087,412 | 13,141 ms | 7,393,280 bytes | 4,109 bytes |
| TGZ / DEFLATE | 2,147,483,665 | 2,087,347 | 13,381 ms | 63,127,552 bytes | 4,160 bytes |
| 7z / LZMA2, 256 KiB | 2,147,483,665 | 925,824 | 46,518 ms | 67,641,344 bytes | 262,144 bytes |
| ZIP64 / DEFLATE | 4,294,967,313 | 4,174,781 | 27,558 ms | 126,951,424 bytes | 4,109 bytes |

The driver sampled `ProcessInfo.currentRss` every 20 ms and reported the maximum
sample minus the per-case starting RSS. Absolute baseline and peak RSS values
were not retained by this writer run; the table preserves exactly the reported
deltas. The values include VM/JIT and allocator behavior and can miss peaks
between samples. These runs followed smaller checks in the same VM. They are
evidence against whole-payload buffering, not a stable performance benchmark or
a complete memory profile of the app. The driver's regression bound was an
increase below 384 MiB for each large writer case.

Independent final results:

```text
PASS independent large.zip: 2147483665 payload bytes
PASS independent large.tgz: 2147483665 payload bytes
PASS independent large.7z: 2147483665 payload bytes
PASS independent large.zip: 4294967313 payload bytes
```

### Fixture identities

The 2 GiB + 17 zero-byte payload has SHA-256:

```text
d9378e43c0e666027848e63668ba0a821b4726843e366626946e3823b477299e
```

The independent readers verified every byte as zero and the exact length; this
payload digest was separately calculated from the same specified zero sequence.

The 4 GiB + 17 ZIP64 member's independent SHA-256 output was:

```text
0a05f7ccc43a8e6c830fd3b8ad9dfc0129ce8f65fd6cc96be998988a1871fe21
```

Packed fixture SHA-256 values retained for the three 2 GiB member archives:

| Archive | SHA-256 of packed archive |
|---|---|
| `large.zip` | `1f9378c0e9174ba4035fbac29d2df69762353e069290ff3f30405816a38d438d` |
| `large.tgz` | `0bd1354a50fd31be4b249ff8ca0d35e47cc53ae9521ac21f990549247bf0883b` |
| `large.7z` | `547028ffb419c92de617c08163e47012f73e498154db823569dd9112e126bfbc` |

The ZIP64 run cleaned its temporary packed output after the independent check;
its packed-file digest was not retained. The reproducible test remains in source.

## Limits and untested integration surfaces

- Native payload and output limit: 8 GiB. Tested actual payload sizes are those
  in the table; the full 8 GiB endpoint was not stress-tested.
- Member names and metadata remain bounded: at most 200,000 entries, 4,096 UTF-8
  bytes per path, 200 path components, 8 MiB aggregate UTF-8 path bytes, and
  16 MiB for a generated 7z header. These resource bounds are intentional.
- ZIP timestamp output retains the existing supported precision profile:
  integral UTC seconds using the extended timestamp field, or a representable
  DOS timestamp. It rejects an unrepresentable/subsecond timestamp instead of
  silently rounding it. 7z writes supported FILETIME modification values and
  POSIX modes; arbitrary opaque archive metadata is not synthesized.
- Large encrypted streaming writes are explicitly unsupported by this API.
  Existing bounded encrypted writers remain a separate path. Split-volume
  creation and arbitrary nested-container write-back are not implemented here.
- Physical multi-gigabyte archive copying, storage-provider publication,
  replacement/recovery, and the graphical app are not established by these
  codec checks.
- The Flutter test launcher was blocked by automatic approval review in this
  environment; the review reported a possible cloud-metadata request. The
  blocked launcher was not overridden. The directly executed Dart verification
  and static analysis described above are the available evidence, and are not
  represented as Flutter widget or app-runtime test results.

Machine-readable measurements and identities are in
[`evidence/archive-streaming-codec-verification.json`](evidence/archive-streaming-codec-verification.json).
