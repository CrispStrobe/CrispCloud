## Why

CrispCloud needs to browse filesystem images through its existing archive, Hex and extraction workflows, inspect partition structures, and recover verified ZIP contents when a central directory is unusable. This PR adds bounded format profiles while retaining source identity, cancellation, read-only policy and staged publication.

## Changes

- **Read-only FAT12/16/32:** original MIT Dart reader for 512–4096-byte logical sectors, clusters through 32 KiB, checked long names and ASCII short names, fragmented live files, nested directories and empty members. Validate published chains, mirrors/active FAT selection, loops, cross-links and resource budgets before exposing a file tree.
- **MBR/GPT image browsing:** validated primary MBR or matching CRC-checked GPT mirrors expose deterministic raw partition entries and eligible FAT file trees. Unsupported partition types remain raw slices. Hex's **Inspect partitions → Browse image** retains the captured source and chosen 512/4096-byte geometry, then revalidates before browsing.
- **Shared integration:** archive registry/dispatch, native F3 and read-only native workspaces use the same image adapters. Actual FAT/disk-image content stays read-only even with a misleading archive filename. Existing buffered and native host ceilings remain in place.
- **FAT inside DMG:** supported UDIF partitions retain raw access and gain FAT file views. Forward child filesystem notices, retain provider/cancellation exception identity and close the root source once. Shared logical-metadata, backing-input and decompression-work limits bound compressed-block amplification. Skip FAT probing below its tight 2,048-byte minimum without weakening existing filesystem-sized codec checks.
- **LZFSE DMG reading:** bounded Dart port of Apple's pinned BSD-3-Clause decoder supports raw/LZVN/v1/v2 streams and validated table reuse. UDIF method `0x80000007` feeds existing filesystem/raw views.
- **Read-only UDF:** original MIT Dart support for revisions 1.02/1.50/2.00/2.01 with physical Type 1 maps, FE/EFE, embedded/short/long allocations, bounded continuations, ordered extents and sparse regular files. UDF-only/bridge images use their UDF namespace; recognized failures do not silently select ISO.
- **Recover ZIP to new file…:** native local ZIP/CBZ workflow captures an immutable snapshot, reviews verified stored/deflate local records, rebuilds selected entries and reopens through a separate reader. The shared Operations queue and destination/source proofs govern exclusive new-file installation and pause/resume checks.
- Extend regression coverage, independent references, actual JavaScript acceptance, format profiles and CI. No new Pub or native runtime dependency is added.

## Current FAT/image qualification

| Check | Result | Revision |
| --- | --- | --- |
| Broad native gate | **843 passed, 0 failed, 1 existing opt-in skip**, 29 files | `da5c8897` |
| Shared-fixture native follow-up | **229 passed, 0 failed, 0 skipped**, 9 affected files | `bcd44b86` |
| Final strict scoped analysis | **27 Dart files, no issues** | `bcd44b86` |
| Dart VM and actual dart2js JavaScript/Node | **15 groups / 1,276 checks per target**, all commands passed | `bcd44b86` |
| Independent extraction | **4 complete FAT images / 36 file payloads / 8 directory instances**, 7-Zip 26.06 | Pinned external FatFs references |
| Fixture reproduction | Generated reference Dart and manifest reproduced byte-for-byte | Pinned FatFs R0.16 |
| Production JavaScript release | **Passed**, original production manifests, version **1.2.9+22**, exact source stamp verified | `bcd44b86` |

The final source checkpoint is **`bcd44b86a410d4f52ca7a7cd694294dbef05c181`**. All **1,051 production source/manifest entries** are identical to the broad gate's **`da5c889795e5c5f684bd851dc0ffb6e272646122`**; the sole test-source change replaces unsupported Uint64 writes in the shared DMG fixture with two big-endian Uint32 writes. The broad gate is not relabeled as a later run. All **1,978 Dart/manifest paths** matched before and after the follow-up, portable run and release build. Counts overlap and are not additive.

Both portable targets pass all assertions and payload/raw-volume hashes. Raw JSON equality is **false** because the synthetic zlib UDIF is 8,026 bytes on the VM and 8,033 bytes on JavaScript, using the locked package's distinct encoders. The recorded semantic comparison excludes exactly `derived_udif_wrappers.synthetic-udif-zlib.udif_bytes` and requires every other field to match. Both complete outputs and the earlier failed attempts remain preserved.

The production `main.dart.js` is **27,656,008 bytes**, SHA-256 `c0bb7bd0e6ffd61a64f0c33be80c60e4daf02023285fd26d16a5a2b5f4a4de8c`. The compiled version, complete commit stamp and Apple LZFSE license asset are verified. Native host tests temporarily disable only the optional ebook conversion hook in an isolated validation checkout; production manifest and lock bytes are restored. The release uses the original production manifests.

## Earlier qualification retained

The UDF/ZIP evidence retains its own source revisions: the broad gate at `b07b7b73` passed 526 tests, and the targeted final gate at `20798b39` passed 96 tests. Final UDF portable acceptance has 26 groups / 500 checks per target; ZIP has 15 groups / 131 checks per target, with separate external descriptor/extraction and rebuilt-ZIP controls. The earlier production release remains attributed to `20798b39a0c792e533a5c785294417f26db03272`.

Earlier LZFSE and partition evidence retains its 418-pass archive gate, 82-pass DMG follow-up, 58-pass partition gate, compiled-JavaScript acceptance and Apple/Python controls. Those historical counts are not added to the current gates.

## Preservation and licensing

All **11 fetched remote branch heads and 91 PR heads** are reachable from the qualification source. Main remains included at `14e022eb51c417803a1913131e78912a8a19b3be`; all 20 remote tags are retained. Existing branches remain. Implementation, fixes and evidence are published in incremental checkpoints on `integration/storage-capabilities-20261114`.

New FAT, disk-image, UDF and recovery code is MIT; the LZFSE port retains Apple's BSD-3-Clause attribution. Existing locked permissive codecs/readers are reused. FatFs, genisoimage and 7-Zip are external qualification tools and are not bundled, linked or invoked by the app. No GPL/NC runtime addition is imported. Existing project licensing is unchanged.

## Profiles and limits

- FAT and partition-image browsing are read-only. No exFAT, OEM-only short-name decoding, undelete, allocation repair, formatting, EBR traversal, ext/NTFS/APFS interpretation or VM-container semantics are added.
- Native F3/workspace image inputs retain the **8 GiB** ceiling. Workspace aggregate accounting includes both raw entries and overlapping file views. Buffered members retain **64 MiB**; browser, remote and nested paths retain their separate bounds.
- UDF remains a 2048-byte physical-map profile. VAT/sparable/metadata maps, revisions 2.50/2.60 and reconstruction/repair are excluded.
- ZIP recovery retains separate 64 MiB source/member/expanded/output ceilings and a 4,096-record cap. ZIP64, encryption, recognized split sets, arbitrary prefixes/SFX and stored data descriptors are excluded. Initial publication is native local storage only.
- The skipped broad-gate test requires `CRISP_RUN_LARGE_ARCHIVE_TESTS=1` for a physical TGZ member above 2 GiB. The largest complete external FAT reference is 64 MiB; multi-terabyte positional cases are synthetic, not full physical extractions.
- No physical-device access, mounting, partition writing, general filesystem repair, encrypted DMG/APFS support, browser-engine acceptance, WebAssembly qualification or new native/device release packaging is claimed.
- GitHub-hosted checks remain unqualified. Queued and canceled checks are recorded separately from completed local results. This PR remains a draft.

## Evidence

- [Current FAT/image qualification, raw logs and source bindings](https://github.com/CrispStrobe/CrispCloud/tree/integration/storage-capabilities-20261114/docs/evidence/storage-fat-20261114)
- [FAT profile](https://github.com/CrispStrobe/CrispCloud/blob/integration/storage-capabilities-20261114/docs/archive-fat-profile.md)
- [Partition-image profile](https://github.com/CrispStrobe/CrispCloud/blob/integration/storage-capabilities-20261114/docs/archive-disk-image-profile.md)
- [UDF/ZIP qualification](https://github.com/CrispStrobe/CrispCloud/tree/integration/storage-capabilities-20261114/docs/evidence/storage-udf-zip-20261114)
- [Earlier LZFSE/GPT/MBR qualification](https://github.com/CrispStrobe/CrispCloud/tree/integration/storage-capabilities-20261114/docs/evidence/storage-runtime-20261114)
- [Format capability matrix](https://github.com/CrispStrobe/CrispCloud/blob/integration/storage-capabilities-20261114/docs/archive-format-coverage.md)
- [Roadmap and permitted-library assessment](https://github.com/CrispStrobe/CrispCloud/blob/integration/storage-capabilities-20261114/docs/storage-capabilities-20261114.md)
