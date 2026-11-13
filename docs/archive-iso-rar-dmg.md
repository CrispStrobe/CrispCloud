# Writable ISO, RAR and DMG containers

Date: 13 November 2026. Branch: `feature/archive-iso-rar-dmg-20261113`.
Baseline: `794bde82693e07a6e04ed1490bfa228f154e6e5c`, which already retains the
previous streamed ZIP/7z/TGZ archive implementation.

## Delivered scope

The native local file manager now connects data ISO, RAR5 Store/CBR and fully
verified HFSX data-volume DMG profiles to the existing archive workspace. It
supports adding and replacing files, creating folders, moving/renaming members,
deleting members, preparing a concrete review, publishing it and reopening the
result. The same capture, source-change, staged-readback and publication-recovery
checks used by the common archive formats remain in force.

| Format | Creation | Existing-container editing | Native size budget |
| --- | --- | --- | --- |
| ISO | Data ISO with Rock Ridge and Joliet | Inspected data-only ISO profiles, preserving understood volume/root/member metadata | 8 GiB image; each single-extent file at most 4,294,967,295 bytes; 100,000 entries |
| RAR / CBR | RAR5 Store, without compression | Inspected unencrypted, nonsolid, single-volume Store profiles with ordinary files/directories and understood metadata | 8 GiB packed/expanded; 200,000 entries; 16 MiB bounded metadata |
| DMG | Unsigned, unencrypted, case-sensitive HFSX data volume in raw/zlib/zero-run UDIF | Fully inspected canonical CrispCloud data-volume profiles | 8 GiB packed and decoded; 100,000 entries; bounded 1 MiB UDIF chunks |
| Raw HFSX | Fresh data image | Existing raw HFS images remain read-only | Native creation within an 8 GiB image budget |

These are resource budgets, including format overhead, rather than guarantees
that an exactly 8 GiB source file fits into an 8 GiB output. They do not promise
unlimited archives. Names, depth, metadata, free space and format field bounds
also apply. The implementation uses file snapshots and bounded streams; it does
not allocate an entire large image or member in memory. Temporary snapshots,
decoded volumes, candidates, staging and retained backups require disk space.

The creation dialog has 35 choices, including explicit **RAR5 Store** and
**CBR (RAR5 Store)** entries. It displays the applicable native image budget and
ISO member bound. Unsupported password/compression controls are cleared when
switching formats. New labels and guidance are translated into the existing
eight non-English UI locales. The English, German and French offline guides
describe the same scope and limitations.

RAR5 Store workspaces use the exact metadata reader in both native streaming
and bounded buffered/nested routes, so a rename does not round a retained
subsecond modification time. DMG workspace paths use the same frozen HFS
Unicode normalization as the image writer, including accented-name lookups and
canonical-equivalent collision checks.
Folder comparison and import previews use those same destination keys while
retaining the exact physical source paths for verification and move cleanup.

## Commander comparison

The comparison distinguishes an application's archive interface from the
capabilities of its selected plugin or external archiver. Sources checked on
13 November 2026:

| Area | Double Commander | Total Commander | CrispCloud continuation |
| --- | --- | --- | --- |
| ISO browsing | Its SevenZip plugin lists ISO; the underlying 7-Zip engine lists ISO as unpacking-only | Official plugin catalog lists the ISO reader, including large images | Existing ISO browsing retained; eligible data images gain streamed writes |
| ISO creation | The documented SevenZip backend does not provide ISO packing | TotalISO is a front end for separately installed mkisofs/cdimage | Built-in data-ISO creation and inspected rewrites; bootable/hybrid/UDF layouts remain read-only |
| RAR packing | The UnRAR plugin can pack when configured with WinRAR.exe or the rar utility | The packing FAQ identifies RAR as an external packer integration | Independent built-in RAR5 Store creation and editing; proprietary compression and external RAR engine integration remain open |
| DMG browsing | SevenZip plugin lists DMG; 7-Zip lists it as unpacking-only | Total7zip catalog entry lists DMG among readable formats | Existing supported UDIF partition/filesystem browsing retained |
| DMG writing | Not provided by the documented 7-Zip backend | The cited Total7zip entry does not claim DMG creation/editing | Built-in verified HFSX data-volume creation and canonical data-profile rewrites |

Primary references:

- [Double Commander bundled plugin documentation](https://doublecmd.github.io/doc/en/plugins.html).
- [7-Zip's supported packing and unpacking formats](https://www.7-zip.org/).
- [Total Commander official plugin catalog](https://www.ghisler.com/plugins.htm).
- [Total Commander packing FAQ](https://www.ghisler.com/efaqpack.htm).
- [RARLAB's public RAR5 container specification](https://www.rarlab.com/technote.htm).

This closes specific native folder-operation and data-image gaps. It is not a
claim of parity with every commander plugin or external packer. Compressed RAR
writing, large protected/nested writes, split-volume creation, external/WCX
engines and durable background packing remain separate work. The broader
[commander comparison](archive-parity-large-continuation.md) records those gaps.

## Preservation decisions

### ISO

`inspectIsoRewriteSource` borrows a captured byte source, reads bounded
descriptors, directory records, continuation data and path tables, and checks
every unclaimed range and trailing byte. It skips the payload extents of regular
files. Boot records, nonzero system areas, hybrid/UDF bridges, extra sessions,
unknown application metadata, links and unsupported extent layouts cannot
silently disappear during a rewrite.

Read-only ISO viewing indexes the directories without performing this full
write-preservation scan. Its reader handle carries a read-only policy; opening
a writable workspace and verifying a replacement still run the complete scan.

After the candidate is opened and inspected again,
`verifyIsoRewritePreservation` compares the planned primary/Joliet descriptors,
root and member metadata with the actual candidate. It accounts for intentional
name, mode and modification-time edits while preserving understood UID/GID,
Rock Ridge time records, identifiers, serials and link-count semantics.

### RAR5 Store

The new codec is independently written from the public RAR5 container note. It
contains no proprietary compression algorithm or code copied from the UnRAR or
7-Zip RAR engines and requires no external executable. Store means file data is
not compressed; the picker states that explicitly.

The writer reads every captured regular file twice. The first pass obtains the
CRC needed before its payload; the second emits bounded chunks and compares both
CRC-32 and SHA-256 with the first pass. It rejects changed, short or growing
sources and observes sink backpressure. Header CRCs, UTF-8 names, variable-length
integers, declared sizes and payload CRCs are checked by the reader.

The inspector preserves understood Windows attributes or Unix modes, directory
markers, basic modification time and exact retained FILETIME/Unix time records.
`verifyStoredRarPreservation` compares those auxiliary fields after candidate
inspection, without reading file data again. Compressed, encrypted, solid,
split, recovery, links, owner records and unknown extensions remain read-only.
Existing compressed/password RAR browsing continues through its prior reader
and existing limits.

### DMG and HFSX

A creator marker is not sufficient permission to rewrite a disk image. The
native writable reader first checks the exact supported UDIF trailer, XML,
block table, packed CRC, expanded CRC and compressed-block termination. It then
reconstructs the HFSX metadata plan and compares every nonpayload byte: primary
and alternate volume headers, allocation bitmap, complete B-trees, reserved
areas, file slack and unused blocks. Unknown filesystem information is refused.

Only a successful inspection can issue the opaque preservation object accepted
by the writer. The writable view exposes filesystem paths directly, while the
ordinary read-only DMG reader retains its partition/file view for other images.
Rewrites preserve the volume name and dates, root mode/dates, member modes,
modification times and auxiliary dates. Candidate verification checks those
values again. Resource forks, extended attributes, signatures, APFS and other
filesystem/partition layouts are not reconstructed from a partial file listing.

UDIF zero runs can make even a Store image physically small when its filesystem
contains mostly zero bytes. The hosted large DMG fixture therefore supplies
deterministic high-entropy blocks, larger than zlib's window, and requires both
the original and the edited, published outer container to exceed 2 GiB.

## Verification and evidence

The previous ZIP/7z/TGZ hosted gate is complete: at commit
`80fbf6f2978accc3521b06ee6449d4c52c814b90`, the archive regression suite passed
1,769 tests, and all five explicitly enabled cases above 2 GiB passed without
skips. Those cases cover ZIP, 7z and TGZ creation, TGZ workspace publication and
the combined common-format writer test. See the exact jobs and receipts in
[hosted runtime verification](archive-containers-runtime-verification.md).

Completed direct checks for the new formats:

- **ISO:** created and rewrote a 2,147,483,665-byte member; the replacement image
  is 2,147,547,136 bytes. Both the production reader and independent libarchive
  read the complete payload. The exported fixture is logically large and sparse;
  allocated storage is reported separately in
  [the ISO receipt](archive-iso-streaming-verification.md).
- **RAR5 Store:** a dense 2,147,483,788-byte archive contains a
  2,147,483,665-byte member plus a following member beyond the 2 GiB offset. Both
  CrispCloud and libarchive consumed all payload data. A separate Python parser
  checks exact public-format time records, since libarchive 3.7.4 reports
  FILETIME only to whole seconds. See the
  [RAR receipt](archive-rar-store-verification.md) and
  [machine-readable measurements](evidence/archive-rar-store-verification.json).
- **DMG:** 29 direct checks passed, including full 65 MiB member hashing,
  add/delete/rename, metadata preservation, 14 hidden-filesystem mutations with
  recomputed CRCs, forged markers, unknown UDIF information, extra partitions,
  ignored compressed suffixes, checksum corruption, cancellation and ownership.
  A further direct probe created a **2,148,753,423-byte DMG**, rewrote it to a
  **2,147,601,376-byte candidate**, and verified the full **2,147,487,745-byte
  member**, both CRC layers, metadata and cleanup. See the
  [large DMG receipt and reproducer](archive-dmg-streaming-verification.md).
- **Integration routing:** the direct native viewer-file probe passed ISO,
  RAR, CBR and DMG reading, misleading filename fallbacks, existing protected
  ZIP fallback and cancellation cleanup.
- **Portable codecs:** the three data codecs compiled to JavaScript and ran
  under Node, comparing every byte of each small decoded payload. This protects
  browser compilation; it does not enable native publication in the browser.

The integrated hosted workflow has a normal archive regression/analysis gate
and nine explicit large cases. The new tests cover native creation, edits,
review, cancellation without mutation, verified publication, reopen, bounded
chunks, full payload hashes, source retention and cleanup for ISO/RAR/DMG. A
receipt is green only when its exact selected large test completes with zero
skips. At commit `f1a03e807b1261361a17f66a37fa94858481e1e7`, the normal hosted
suite completed with **1,856 passed, zero failed and ten opt-in cases skipped**;
help validation, archive analysis and the portable codec checks also passed.
The **ISO, RAR5 Store and DMG large integrated jobs also passed**, including
creation, folder edits, review, cancellation without mutation, publication,
reopening and full payload hashing, with one passed test and no failures or skips
in each job. Both the initial and edited, published outer containers exceeded
2 GiB in each format. The separate RAR5 Store creation case and all five
common-format large cases passed on this same candidate as well. The completed
workflow therefore has **ten successful jobs: the normal suite and nine
explicit large cases**, each large case with one passed test and zero failures
or skips. After attempt 1 was canceled, attempt 2 completed the unfinished jobs
on the unchanged source revision; the overall run concluded successfully at
`2026-11-13T06:03:13Z`.
The additional standalone RAR codec opt-in has the separate direct evidence
above. Exact jobs, artifact hashes and durable receipts are in
[runtime verification](archive-containers-runtime-verification.md).
No local Flutter runtime was used.

The configured 8 GiB ceiling and all supported operating systems are not fully
qualified by a 2 GiB Linux fixture. No macOS mounting, application-bundle
preservation, signed-image verification or physical-disk operation is claimed.
