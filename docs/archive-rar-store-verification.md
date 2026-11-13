# RAR5 Store reader and writer verification

Verification date: 2026-11-13 (UTC).

## Profile and scope

The new implementation creates and rewrites **plain RAR5 Store archives**:
documented method 0, with no compression of member data. It supports ordinary
files and directories, UTF-8 names, nested paths, empty entries, Unix permission
bits, Windows attributes, and the understood timestamp representations.
Creation and rewrites use bounded streams, awaited output backpressure, CRC-32,
SHA-256, and an explicit **8 GiB** resource limit. This is a native writable RAR
profile; it does not implement the proprietary RAR compression algorithms.

The format implementation was written from the public
[RAR 5.0 archive format specification](https://www.rarlab.com/technote.htm).
It contains no code from UnRAR or 7-Zip's RAR engine and does not invoke an
external archiver. The RAR/WinRAR executable and UnRAR source have separate
license conditions; see the [RAR/WinRAR license](https://www.rarlab.com/license.htm)
and [UnRAR license text](https://spdx.org/licenses/UnRAR.html). Neither executable
is bundled by this change.

Compressed, encrypted, solid and split RAR archives are outside the writable
Store profile. The new reader explicitly defers these to the existing reader.
Unknown metadata, service records, recovery records, archive locks, links,
special filesystem entries and trailing data make a source ineligible for
rewriting. A source inspection must establish preservation before mutation.

The checks below exercise the codec directly on the Dart VM. They do not claim
that the Flutter UI, native context menu, remote storage publication or every
existing RAR variant was exercised. The application workflow and GitHub Actions
runtime gate are tracked separately in
[archive-containers-runtime-verification.md](archive-containers-runtime-verification.md).

## Implementation and checks

| File | Responsibility |
|---|---|
| `lib/services/archive_rar_stored_format.dart` | Public format fields, bounded integers, CRC-protected headers, exact time records and strict paths |
| `lib/services/archive_rar_stored_reader.dart` | Positional indexing, borrowed-source rewrite inspection, owned-source streaming reader and payload CRC validation |
| `lib/services/archive_rar_stored_writer.dart` | Preflight, two-pass Store writer and metadata-only preservation verification |
| `test/archive_rar_stored_test.dart` | Flutter test registrations, including an opt-in large case |
| `test/support/verify_archive_rar_stored.dart` | Direct Dart verification driver used for the results below |
| `test/support/check_archive_rar_stored.py` | Independent libarchive content reader and Python public-spec metadata parser |

The writer reads each regular member exactly twice, including an empty regular
file. The first pass computes CRC-32 and SHA-256; the second emits the header and
payload while independently recomputing both. A changed, short or growing
captured stream fails. Directories cause no source reads. Callers own the
unpublished output and its staged publication; a failed write can leave a partial
candidate, never a valid final archive with a success result.

`verifyStoredRarPreservation` performs no payload reads. It derives the expected
metadata through the same validated plan as the writer and compares every
supported per-member field after the candidate has been reopened. This includes
host OS, raw attributes, compression information, CRC-presence flag, directory
trailing slash, basic modification time and the complete time extra. Namespace
order and the original source path are intentionally excluded from this metadata
comparison so that renaming and rearranging entries remain possible. Ordinary
size, type and content verification remain the publication layer's responsibility.

### Resource bounds

| Resource | Bound |
|---|---:|
| Packed source/output | 8,589,934,592 bytes, or a lower caller limit |
| Total expanded payload | 8,589,934,592 bytes |
| Regular payload input/output chunk | 262,144 bytes |
| Single parsed header | 2,097,151 bytes |
| Total parsed/written metadata | 16 MiB |
| Member count | 200,000 |
| Combined UTF-8 member names | 8 MiB |
| One UTF-8 name / path depth | 4,096 bytes / 200 components |
| Default in-memory member preview | 64 MiB |

Header overhead consumes part of the packed-output allowance, so a single member
cannot use all 8 GiB in an archive whose total output is limited to 8 GiB. The
8 GiB limit is an implemented guard, not a claim that every size up to that limit
was measured in this verification.

## Reproduction

Run from the repository root with dependencies already resolved. The actual
commands used the restored SDK and the existing offline package configuration:

```bash
export TMPDIR=/workspace/scratch/4d61c38502be/native-test-temp
CRISP_DART=/workspace/scratch/4d61c38502be/toolchain/flutter/bin/cache/dart-sdk/bin/dart

"$CRISP_DART" analyze \
  lib/services/archive_rar_stored_format.dart \
  lib/services/archive_rar_stored_reader.dart \
  lib/services/archive_rar_stored_writer.dart \
  test/support/verify_archive_rar_stored.dart \
  test/archive_rar_stored_test.dart

"$CRISP_DART" --packages=.dart_tool/package_config.json \
  test/support/verify_archive_rar_stored.dart --oracle

"$CRISP_DART" --packages=.dart_tool/package_config.json \
  test/support/verify_archive_rar_stored.dart --oracle --large
```

The driver creates temporary fixtures and deletes them in `finally`; no large
binary fixture belongs in Git. Python and libarchive are test dependencies,
not application runtime dependencies. No `pub get`, Flutter engine or external
RAR packer is launched by these commands.

| Component | Observed version |
|---|---|
| Dart | 3.13.7 stable, linux_x64; SDK build 2026-10-22 |
| Python | 3.12.14 |
| Python zlib runtime | 1.3.2 |
| libarchive | 3.7.4 |
| Dart `archive` | 4.6.0 |
| Dart `crypto` | 3.0.7 |
| `koni_archive` byte-source abstraction | 0.9.0 |

## Focused results

The focused analyzer reported **No issues found!**. The direct small driver
completed with exit code 0, including these result groups:

```text
PASS RAR5 Store creation, rename/add/replace/delete, Unicode, empty entries, exact modes/times
PASS RAR5 exact timestamp/Windows attribute preservation, metadata-only verifier and explicit edits
PASS RAR5 fallback, metadata/path refusal, corruption, bounds, changed source, cancellation/backpressure
```

Independent libarchive reads passed for a 700,288-byte newly created archive and
its 700,229-byte rewritten archive. The main 700,003-byte member follows the
pattern `(index * 37) % 251`; its SHA-256 is
`66902429e05b30b428c3be08bd662e6352202f51ccc29aeff37813e8b19a7638`.
The cases also contain `docs/Grüße 🚀.txt`, a literal filename containing `$`,
parentheses, a semicolon, apostrophes and brackets, an empty file, an empty
directory, and a fractional historical timestamp in 1900. Rewriting deletes,
renames, replaces and adds members, changes a mode and creates a directory.

Metadata fixtures independently encode both Unix seconds with nanosecond extras
and Windows FILETIME with 100 ns ticks. They include modification, creation and
access times with precision finer than Dart `DateTime` can expose. A rename and
payload replacement retain those exact raw values, even when the same modified
instant is represented by a local `DateTime`. An explicit mtime edit preserves
the unrelated ctime/atime values. A representation change that would discard
nanoseconds fails. A Windows file retains its raw `0x21` attributes.

The preservation-verifier tests deliberately alter each of the supported header
properties, a creation-time value, and the container profile. Every alteration
is rejected; verification uses a source stream that throws if it is opened, so
these checks also prove the helper performs no payload reads.

Guard checks cover header CRC corruption, payload CRC corruption at natural EOF,
a truncated end marker, size preflight before any sink/source I/O, short/growing
sources, changed content on the second source pass, cancellation with iterator
cleanup, borrowed-source cancellation without closure, unsupported-profile
ownership cleanup and awaited sink backpressure. Known unsupported metadata
is refused before any output is emitted.

### Independent timestamp precision

The installed libarchive 3.7.4 RAR5 reader reports whole seconds for the
FILETIME/nanosecond extras in these fixtures. The oracle therefore uses
libarchive to validate names, modes, entry types, lengths, full payloads and CRCs,
and compares its timestamp seconds. A separate small Python parser, written from
the public format description, validates header CRCs and exact timestamp fields,
including raw ctime/atime values and submicrosecond precision. It imports no app
code or RAR compression engine. If libarchive reports nonzero nanoseconds, the
oracle also requires that reported precision to agree. The archive output is
not rounded to accommodate this reader limitation.

## Large physical archive

The large test writes an actual dense file through `RandomAccessFile.writeFrom`.
Its first member is **2,147,483,665 bytes (2 GiB + 17)**: byte 0 is `0x43`, the last
byte is `0xa5`, and every intervening byte is zero. A second member `tail.txt`
contains `0x55, 0xaa`, so both its header and payload start beyond the signed
32-bit offset boundary. Both members have mode `0644` and modified time
`2026-11-13T01:02:03.123456Z`.

The large command completed with **exit code 0**. The new reader consumed the
entire member with CRC/SHA validation and then read the following member.
libarchive independently consumed both complete payloads; Python additionally
checked the first/last sentinel and every intervening zero byte. Both readers
returned the same SHA-256:

```text
large.bin: b5c0eee7c54826eeb55e9625703f26d88693a678318e5a8534bfc570de17d5af
tail.txt:  648aac5c6332f3a60b0850b160ea3b28c292c1c552f7e13b4319c21e20a8f89b
```

| Measurement | Observed result |
|---|---:|
| Main member bytes | 2,147,483,665 |
| Packed archive length | 2,147,483,788 bytes |
| Allocated file storage (`st_blocks * 512`) | 2,147,491,840 bytes |
| Writer, including both input passes and flush | 73,714 ms |
| Reader, including indexing, full main member and tail | 34,551 ms |
| Dart process baseline RSS | 341,999,616 bytes |
| Maximum of baseline and sampled RSS | 341,999,616 bytes |
| Sampled rise above baseline | 0 bytes |
| Timer heartbeat ticks | 4,544 |
| Largest writer output chunk | 262,144 bytes |

The physical allocation confirms this was a real container larger than 2 GiB,
not a sparse hole or a small compressed archive with a large declared size.
The ordinary 64 MiB in-memory preview still refused the large member; explicitly
streaming it succeeded.

The driver samples `ProcessInfo.currentRss` every 20 ms, with the peak initialized
to the starting RSS. The large case follows the small cases in the same VM, so
the baseline already includes a warmed JIT and allocated heap capacity. No
observed sample exceeded that baseline. **A zero increase does not mean zero
allocation or zero memory use.** Sampling can miss shorter peaks, and the
independent Python child process is outside the Dart process RSS. These results
are evidence against whole-payload buffering, not a Flutter memory benchmark.
The regression assertion permits less than 512 MiB of growth.

The machine-readable receipt is
[archive-rar-store-verification.json](evidence/archive-rar-store-verification.json).
These results cover codec behavior; staged app publication is a separate test.
