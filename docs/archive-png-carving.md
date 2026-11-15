# PNG recovery to a new ZIP

The first carving profile searches a bounded captured file for complete,
contiguous PNG images. It is separate from ZIP salvage and ordinary archive
browsing. A signature occurrence is a candidate, not proof of recoverability.

## Use

Select one native local regular file of at most 64 MiB, then choose **Recover
PNG images to ZIP…** from the context menu, Tools menu or command palette. The
source may have any extension. Review each candidate's byte range, dimensions,
validation finding and selection state. Choose a new `.zip` name and select
**Recover selected**. The new ZIP is created beside the captured source; later
pane navigation does not redirect it. The original file remains intact.

The ZIP contains only selected validated images and `recovery-report.json`.
Names such as `png-0000065533.png` identify the zero-based source byte offset;
they do not claim to restore original filenames. The JSON report includes the
source length and SHA-256, every encountered candidate's classification,
exclusive end offsets, selected output names and hashes, unscanned and
unclaimed ranges, and the profile's limitations. A rejected candidate's end
is only an inspected boundary. Only `rangeValidated: true` establishes a
complete accepted range.

No output is written during scanning or review. Once admitted, the shared
Operations queue owns the job. Closing the dialog detaches its observer;
Pause and Stop remain available through the queue. Source bytes and decoded
contents are never saved in the journal. Restart requires a fresh source scan
and candidate review; saved source/output digests remain visible.

## Accepted PNG profile

The original positional Dart scanner accepts noninterlaced 8-bit grayscale,
RGB, grayscale with alpha, and RGBA PNGs. It requires all of the following:

- Correct PNG signature, bounded chunk lengths, valid chunk names/reserved bit,
  an initial single IHDR, consecutive IDAT chunks and a final empty IEND.
- Matching CRC-32 for every inspected chunk, with legal ordering and supported
  structural values for admitted ancillary chunks.
- Complete zlib/DEFLATE data, matching Adler-32, exact consumption of the IDAT
  payload, the exact scanline length implied by the dimensions and color type,
  and a filter byte from 0 through 4 for each row.

Indexed-color, interlaced, non-8-bit and animated PNGs are explicit unsupported
candidates. Compression must advertise the 32 KiB zlib window; smaller-window
streams are outside the decoder contract of this initial profile. Compressed
metadata, unknown critical or ancillary chunks and unsupported methods decline.
The admitted ancillary set is `PLTE`, `gAMA`, `cHRM`, `sRGB`, `sBIT`, `pHYs`,
`bKGD`, `tRNS`, `tIME` and `tEXt`, with bounded structural checks. This is not a
claim of complete color-management or ancillary-semantic validation.

A corrupt or unsupported candidate does not prevent discovery of later
signatures, unless a shared work limit is reached. A signature within an
already validated PNG is reported as overlapping and cannot be selected.
Signatures that cross source-read boundaries are included. Unreadable or short
capture reads abort the operation; the scanner does not fill gaps with zeros.
All reported readable bytes come from the complete owned capture. Unclaimed
bytes are not automatically classified as missing files or damaged sectors.

## Publication and ownership

The service retains a private capture and exposes immutable candidates. A
selection is copied before its first asynchronous checkpoint. The builder
rehashes selected ranges, creates a new stored ZIP and reopens it with the
separate Koni ZIP reader to verify its exact entry inventory and file hashes.
This produces candidate bytes, not destination authority.

The host requires guarded native staging and an exclusive new-file install.
It validates the captured source/backend identity, complete source SHA-256,
destination parents, candidate length and complete staged SHA-256. Proofs run
after the durable committing checkpoint and repeat after any pause, including
a pause and resume that both occur during the final asynchronous path check.
A synchronous final guard checks backend identity and cancellation immediately
before invoking the native exclusive rename. An existing destination is never
replaced. Once installation has occurred, a later Stop or completion-observer
failure retains the successful install and any completion warning.

This protects participating in-process operations. It does not establish an
atomic snapshot or compare-and-swap against arbitrary external writers between
content verification and the native rename. Native exclusive rename guarantees
no replacement at the destination; it does not authenticate content or recover
filesystem metadata.

## Bounds

| Resource | Maximum |
| --- | --- |
| Captured source | 64 MiB |
| One PNG range / its decoded scanlines | 64 MiB each |
| Aggregate decoded scanlines during scan | 64 MiB |
| ZIP including JSON report and headers | 64 MiB |
| Signature candidates | 1,024 |
| Chunks per candidate / across scan | 4,096 / 32,768 |
| Charged CRC/codec validation bytes | 128 MiB |
| Positional capture read | 64 KiB |
| Compressed input per codec turn | 8 KiB |
| Codec output callback | At most 64 KiB |
| Host capture/verification stream | 262,144 chunks; 2 minutes elapsed including time paused within a read; 30 seconds between chunks |

Limits are independently enforced and cannot be raised through the public
scanner API. These are not a 64 MiB total resident-memory claim: snapshot,
compressed candidate, ZIP buffer and readback can coexist. A work-limit stop
retains the verified candidates already found and marks the remaining search
range explicitly. Source capture errors produce no exportable report.

## Source, tests and qualification

The scanner is
[`archive_png_carving_service.dart`](../lib/services/archive_png_carving_service.dart);
publication is
[`archive_png_carving_workflow.dart`](../lib/services/archive_png_carving_workflow.dart).
Both are original MIT-licensed code using the already locked `archive`,
`crypto`, `koni_archive` and `koni_codecs` dependencies. No runtime package,
external recovery executable or new cryptographic algorithm is added.

Python/Pillow generates independent images and deliberately damaged regions.
The portable Dart driver checks their recorded offsets, boundaries, hashes and
classifications on VM and compiled JavaScript. Python `zipfile` and Pillow
independently read the actual generated ZIPs, check source hashes and compare
decoded pixels with the independent manifest. A negative control rejects a
changed expected image hash. Workflow, queue, native-boundary and widget tests
cover source replacement, collision, cancellation, pause, restart and review.

Exact source revisions, raw results and limitations are recorded in
[`storage-carving-20261115`](evidence/storage-carving-20261115/PROGRESS.md).
Earlier interrupted-turn test totals are not evidence for this implementation.
The portable core does not enable browser/cloud publication. Other operating
systems, mobile execution, physical-device access, large-file carving, JPEG,
PDF, arbitrary fragments and FAT/NTFS undelete remain separate qualifications
or future profiles.

### Current qualification status

Current source identities, local qualification commands, raw results and remaining
gates are maintained in the
[latest continuation record](evidence/storage-carving-20261115/local-resume-20261115T1150/README.md).
The integration preserves main through `4933ffc2`, the later ODF branch, the
worksheet and document-workspace work, and all parallel qualification receipts.

Earlier attempts and their failures remain attached to their original source
revisions. A historical pass is not substituted for a current gate. Native
Linux tests and portable VM/JavaScript checks have separate acceptance scopes.

Format references consulted:

- [W3C PNG Third Edition](https://www.w3.org/TR/2025/REC-png-3-20250624/).
- [RFC 1950: zlib framing](https://www.rfc-editor.org/rfc/rfc1950).
- [RFC 1951: DEFLATE](https://www.rfc-editor.org/rfc/rfc1951).
