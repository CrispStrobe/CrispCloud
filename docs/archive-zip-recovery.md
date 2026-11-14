# ZIP recovery to a new archive

The first ZIP recovery profile restores verified local records when a central
directory is missing or unusable. It captures the selected input, produces a
review report, rebuilds selected entries into a private candidate, and reopens
that candidate before the operation host can publish a new file. It never
rewrites the damaged source.

The reader/rebuilder is
[`archive_zip_recovery_service.dart`](../lib/services/archive_zip_recovery_service.dart).
The operation host provides source validation, destination checks, staging,
readback and exclusive publication. Recovery is a separate action from normal
ZIP browsing, testing and editing; successful ordinary opening does not invoke
recovery automatically.

## Using the recovery workflow

Select one native local `.zip` or `.cbz` file and choose **Recover ZIP to new
file…** from the context menu, Tools menu or command palette. Scanning creates
no output. Review the stop reason, exclusions and selected records, choose a
new `.zip` filename, and press **Recover selected**. The destination is captured
from the original selected file's directory; later pane navigation does not
redirect the operation.

Once admitted, the existing Operations queue owns recovery, verification and
publication. Pause and Stop remain available there, and closing the dialog
detaches its observer. The original file is checked against its captured
metadata and complete SHA-256 before publication. The staged ZIP is read back
and hashed before its exclusive new-file install; both proofs repeat after a
pause. An existing destination or a source change stops publication. Stop or an
observer failure after a completed install retains the successful result and
any completion warning.

The durable job recipe records the captured source identity, SHA-256, selected
local-header offsets and output receipts. Source bytes and decoded payloads
are not journaled. Restart requires a fresh scan and explicit review; this
first profile does not automatically resume a saved salvage snapshot. Saved
job details keep its digests and output path available for comparison.

The portable scanner and rebuilder also run as compiled JavaScript. The first
publication UI is native local storage only, using the existing verified
staging contract; browser and cloud publication are not enabled by it.

## Supported input

| Record or property | Recovery behavior |
| --- | --- |
| Ordinary ZIP local headers beginning at byte zero | Walk records in physical order; do not search for signatures inside payloads. |
| Stored members, method 0 | Require matching stored/decoded sizes and CRC-32. |
| Deflated members, method 8 | Require a complete DEFLATE stream, exact consumed input, decoded size and CRC-32. |
| Deflate with a 32-bit data descriptor | Measure the DEFLATE end and consumed bytes, including reclaimed codec lookahead. Accept a signed or unsigned descriptor only when its CRC and both sizes match measured data. |
| ASCII local names and explicitly UTF-8 names | Decode strictly. Unsafe paths are excluded without renaming or sanitizing them into another path. |
| Empty regular members and explicit empty directories | Retain their type. Directories must have no data. |
| Missing central directory or truncation after valid records | Offer the verified prefix. The report identifies where the scan stopped. |
| Present central directory | Stop local-record discovery there. Its directory, comments and extra metadata are not used to fill gaps or overrule verified payloads. |

The supported version-needed fields are 1.0 and 2.0. Deflate compression-level
flag bits and the UTF-8 flag are understood. Bit 3 is supported only for deflate.
The local CRC/size fields for a descriptor member may be zero or agree with the
measured values; conflicting nonzero values reject the record.

Recovered regular members become ordinary files in the new archive. Recovery
does not restore symbolic links, devices, ACLs, ownership, executable modes,
archive comments, package signatures, alternate Unicode-path extra fields or
other central-directory metadata. Valid local DOS timestamps are retained;
unusable timestamps receive the deterministic 1980 fallback.

## Stop and exclusion rules

An invalid checksum, incomplete stream, unproven boundary, unsupported method,
encryption, unknown flag, ZIP64 declaration or malformed extra-field envelope
stops discovery. Earlier verified records remain reviewable. The scanner does
not skip to a plausible `PK` sequence after an error: such bytes can belong to
compressed content or to a nested archive.

Stored members with data descriptors are outside this profile because their
payload has no independent end marker. Encrypted records, self-extractors,
arbitrary prefixes and ZIP64 are also outside it. Recognized split-volume
markers, `.zNN`/`.zip.NNN` source suffixes, or a complete end record identifying
multiple disks refuse recovery of that input. A source with a missing end
record cannot establish that the original archive or volume set was complete;
the report claims only the records it verified.

Names are checked with the shared archive-writer path policy. All encountered
duplicates, including case-only differences, are excluded. A file occupying a
directory prefix excludes both that file and its encountered descendants.
Unsupported name encodings and unsafe names can be omitted while discovery
continues only when the record's payload boundary has independently passed
its data checks. Selection uses local-header offsets, not ambiguous names.

## Bounds and ownership

| Resource | Hard ceiling |
| --- | --- |
| Captured source | 64 MiB |
| One decoded member | 64 MiB, reducible by the caller |
| Aggregate decoded bytes during scanning | 64 MiB, including rejected names |
| New ZIP output, including headers and directory | 64 MiB |
| Local records | 4,096 |
| One encoded local filename | 4,096 bytes |
| Aggregate encoded names | 1 MiB |
| Source-capture request | 64 KiB |
| Compressed input supplied per codec turn | 8 KiB |
| Codec output callback | At most 64 KiB, checked before retention |

These are separate bounds, not a claim that the operation uses only 64 MiB of
memory in total. The immutable review report retains a private source snapshot;
recovery also needs decoded content and a candidate buffer. The output sink
caps allocated capacity as well as written length. This portable first profile
does not claim large-file streaming recovery.

The source stays caller-owned: scan neither writes nor closes it. Optional
source-validation callbacks run around capture; the report stores the captured
SHA-256. Caller-owned mutable buffers and selection sets are copied. Recovery
uses the private snapshot after review and freezes the selected offsets before
its first asynchronous checkpoint.

Pause/cancellation checkpoints surround capture reads, record processing,
codec input and verification. A pending arbitrary `ByteSource.read` still
depends on its provider completing; the operation host owns interruptible
provider capture. No cancelled or failed candidate receives publication
authority from this service.

## Rebuilding and verification

The selected members are decoded and checked again against their captured CRC,
size and SHA-256. The existing `archive` encoder writes a new stored ZIP through
the bounded output sink. The separate Koni ZIP reader then reopens it and checks
the exact entry sequence, path, type, size, protection flags and every regular
member's bytes through streamed SHA-256 comparisons. The result contains
immutable candidate bytes and their digest. No output is returned if readback
fails or the operation is cancelled.

The host must still validate the original source and staged destination before
exclusive publication. Candidate verification establishes content recovery,
not publisher authenticity or preservation of omitted metadata.

## Source and license

The recovery service and its unit-fixture builder are original MIT-licensed
code. They use existing locked MIT dependencies: `archive` 4.6.0 for CRC and
ZIP encoding, `koni_codecs` 0.9.0 for resumable raw DEFLATE, and `koni_archive`
0.9.0 for independent candidate reading. No Pub, native, GPL or NC dependency
was added. Existing project licensing remains unchanged.

Format references were consulted rather than copied into the repository:

- [PKWARE APPNOTE 6.3.10](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT),
  local headers, flags, data descriptors and end records.
- [RFC 1951](https://www.rfc-editor.org/rfc/rfc1951), DEFLATE completion and framing.
- [archive package](https://github.com/brendan-duncan/archive), locked version 4.6.0.
- [Koni archive/codecs](https://github.com/zenbaku/koni_archive), locked version 0.9.0.

## Validation sources

Unit regressions are in
[`archive_zip_recovery_service_test.dart`](../test/archive_zip_recovery_service_test.dart).
Independent Python `zipfile` inputs and their payload digests are recorded in
[`zip-recovery-reference-manifest.json`](../test/fixtures/archives/zip-recovery-reference-manifest.json)
and reproduced by
[`generate_zip_recovery_reference.py`](../test/support/generate_zip_recovery_reference.py).
These inputs include both descriptor layouts, missing directories, truncated
members, bad CRCs, duplicate and unsafe names, and explicit unsupported forms.
