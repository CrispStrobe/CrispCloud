# FAT and partition-image qualification — 2026-11-14

## Qualified source revisions

The broad native regression gate is bound to production runtime commit `da5c889795e5c5f684bd851dc0ffb6e272646122`. It completed **843 passing tests, no failures, and one explicit existing opt-in skip across 29 files**. Its original receipts have not been relabeled or replaced.

The final portable acceptance and fixture follow-up use `bcd44b86a410d4f52ca7a7cd694294dbef05c181`. The only change under `lib/`, `test/`, or the production manifests between those revisions is `test/support/dmg_fixture.dart`: nine synthetic UDIF Uint64 writes were replaced with two big-endian Uint32 writes using exact division and remainder. This enables the same fixture constructor to run in dart2js; it does not change a production reader. All **1,051 production `lib/` paths and manifest entries** have identical Git blob identities between the two revisions. See [the source-transition receipt](fat-test-fixture-source-transition.json).

The follow-up native gate passed **229 tests across nine affected files, with no failures or skips**. These results overlap the broad gate and must not be added to its count. All **1,978 Dart source/test files and production manifests** matched the pinned follow-up revision before and after the native run. The broad gate has its own source binding to its own runtime revision.

| Gate | Source | Completed result | Evidence |
| --- | --- | --- | --- |
| Broad native regression | `da5c8897` | 843 passed, 0 failed, 1 explicit skip; 29 files | [Summary](fat-final-gate-summary.json), [receipt](fat-final-gate-receipt.json), [source binding](fat-final-gate-source-binding.json), [raw events](fat-final-gate.jsonl) |
| Strict scoped analysis | `da5c8897` | No issues in 26 changed Dart files | [Log](fat-final-analysis.log), [receipt](fat-final-analysis-receipt.json) |
| Fixture compatibility follow-up | `bcd44b86` | 229 passed, 0 failed, 0 skipped; nine affected files | [Summary](fat-fixture-followup-gate-summary.json), [receipt](fat-fixture-followup-gate-receipt.json), [source binding](fat-fixture-followup-source-binding.json), [raw events](fat-fixture-followup-gate.jsonl) |
| Strict follow-up analysis including the shared fixture | `bcd44b86` | No issues in 27 Dart files | [Log](fat-fixture-followup-analysis.log), [receipt](fat-fixture-followup-analysis-receipt.json) |
| Portable VM and actual compiled JavaScript | `bcd44b86` | 15 groups and 1,276 checks on each runtime; all commands exit 0; matching semantic results | [Receipt](fat-final-portable-receipt.json), [VM output](fat-final-portable-vm.log), [compiler log](fat-final-portable-js-compile.log), [Node output](fat-final-portable-js.log) |
| Production JavaScript release | `bcd44b86` | Passed with original manifests, version `1.2.9+22` and exact revision stamp | [Build log](fat-final-web-release.log), [receipt](fat-final-web-release-receipt.json), [final source verification](fat-final-source-verification.json) |
| External FAT fixture generation | Unchanged pinned fixture sources | All four images and generated data reproduce byte-for-byte | [Reproduction receipt](fixture-reproduction-receipt.json), [raw log](fixture-reproduction.log) |
| Independent FAT extraction | Unchanged pinned fixture sources | Four complete physical volumes; exact 36 file and eight directory instances | [7-Zip oracle receipt](fat-sevenzip-oracle.json) |

## Native environment and source preservation

The host used Flutter 3.47.8 and Dart 3.13.7. Native Flutter tests used the established isolated profile that disables only the optional native ebook-conversion build hook. Dependency versions and app sources were not substituted. Each native test/analysis receipt records the temporary manifest hash and verifies that both production manifests were restored byte-for-byte. The lockfile stayed unchanged during the runs.

The production manifest hashes are:

- `pubspec.yaml`: `f10ba24448b047cf379dac0efeb11f8f60d9ae089022a831b12a6b32b8fa564f`
- `pubspec.lock`: `2a0b95288cf41be9087af0c01ea57afcc4a2f138876d15709bff2f866060ccb4`

The one broad-gate skip is the existing physical extraction case for a `2 GiB + 17` byte image in `archive_streamed_workspace_test.dart`; `CRISP_RUN_LARGE_ARCHIVE_TESTS` was not enabled. The native suite otherwise covers the new FAT and partition readers, dispatch and ownership, bounded DMG composition, native workspaces, and the changed F3/partition-dialog workflows. The new native FAT/GPT widget and workspace paths use physical inputs larger than the former 64 MiB buffered boundary. They retain the existing **8 GiB native F3/workspace input-image cap**.

The follow-up files are listed in [fat-fixture-followup-files.json](fat-fixture-followup-files.json). They cover DMG reading, rewriting and workspace use; disk-image writer/verification fixtures; FAT and UDF integration; DMG provider failures; and the portable-reference review test. This is the affected scope for the test-only Uint64 compatibility change, not a second claim that every broad-gate test ran at the follow-up revision.

## Production JavaScript release and final binding

The standard production JavaScript release completed successfully in 146.5 seconds with the original production manifest, version `1.2.9+22`, and `GIT_HASH=bcd44b86a410d4f52ca7a7cd694294dbef05c181` embedded in `main.dart.js`. No optional native ebook-hook profile was used for this build. The command disables the optional WebAssembly dry run and therefore makes no WebAssembly qualification claim.

The emitted `main.dart.js` is **27,656,008 bytes**, SHA256 `c0bb7bd0e6ffd61a64f0c33be80c60e4daf02023285fd26d16a5a2b5f4a4de8c`. The release receipt also records hashes for the bootstrap script, HTML entry point and bundled `apple_lzfse` license asset. Both production manifests remained byte-for-byte unchanged; the version and exact commit stamp were verified in the compiled JavaScript.

The [final source-verification receipt](fat-final-source-verification.json) checks the source after all follow-up tests, portable execution and release compilation. All 1,978 Dart/test/manifest hashes still match the pre-run binding. All 1,051 production `lib/` and manifest entries in both checkouts match their pinned Git blob identities; this includes the nine non-Dart production files outside the Dart binding. The transition receipt proves those production entries are identical to the broad-gate runtime. The 23 portable revision-bound inputs, saved/executed evidence helper, raw portable log hashes, fixture generator/checker inputs, and rehashed build outputs all still match their receipts.

## Portable execution and the exact semantic comparison

The portable driver runs with Dart VM and is then compiled by `dart compile js -O2`; the emitted JavaScript executes under Node 24.22.1. This is actual JavaScript execution, not a VM run labeled as web. It does not qualify a browser engine, WebAssembly, or a native/device release build.

The [saved helper](run_fat_portable.py) recursively binds all in-repository Dart imports, exports and parts used by the acceptance driver. Its final receipt records **23 revision-verified input paths**, including the production manifests and fixture manifest, plus the separately versioned evidence helper. The helper bytes saved beside the receipt exactly match the executed helper. Every bound source remained unchanged through acceptance.

Each runtime executes these 15 groups:

- The four independently mastered FAT volumes, verifying every file by buffered and streamed SHA256 extraction, exact directory inventory, and bounded metadata access.
- Borrowed/nonzero-offset input views, input preservation, streamed cancellation and resume.
- Five explicit corruptions derived from reference volumes, provider-failure identity, opening cancellation, and empty-member cancellation.
- Four synthetic partition wrappers around unchanged external FAT volumes: MBR FAT12, explicit 4096-byte-sector MBR FAT16, mirrored GPT FAT32, and GPT FAT12 at an exact byte offset above 2 TiB.
- Three synthetic UDIF wrappers around unchanged external FAT12 data: raw, zlib, and LZFSE raw-block framing. Every file is verified buffered and streamed; each wrapper also verifies the complete raw FAT12 volume hash and retained child geometry notices.

The raw JSON outputs are **not identical**. The sole differing diagnostic is `derived_udif_wrappers.synthetic-udif-zlib.udif_bytes`: **8,026 bytes on the VM and 8,033 bytes on JavaScript**. The locked `archive` 4.6.0 encoder selects native `dart:io` zlib on the VM and its Dart Deflate implementation on JavaScript. Both compressed encodings decode to the same independently hashed complete FAT12 bytes and the same exact file payloads. The [platform-encoder source note](fat-portable-zlib-platform-note.json) pins the locked package checksum and the exact supporting implementation files.

The helper explicitly removes **only that one byte-length diagnostic** from deep copies of the two result objects, then requires every remaining field to compare exactly. It preserves both original outputs, records `vm_js_results_identical: false`, records the two excluded values and their reason, and records `vm_js_semantic_results_identical: true`. No payload, hash, group, assertion count, failure control, input-preservation check, or other diagnostic is excluded or weakened.

## Independent references and derived cases

The four reference volumes were fully formatted and populated by the independently implemented **ChaN FatFs R0.16** writer through its public API. An original MIT-licensed host shim supplies deterministic block I/O and payloads. The writer uses its own allocation and directory algorithms; no image bytes were patched after the writer finished. Alternating 512-byte appends to two files create real fragmentation through the writer. The committed sparse gzip representation reconstructs each complete physical image without changing bytes.

| Reference | Physical bytes | FAT | Sector bytes |
| --- | ---: | ---: | ---: |
| `fat12` | 1,474,560 | 12 | 512 |
| `fat16` | 8,388,608 | 16 | 512 |
| `fat32` | 67,108,864 | 32 | 512 |
| `fat16-sector4096` | 33,554,432 | 16 | 4,096 |

Every volume contains nine original files and two directories. Cases include nested and empty directories, an empty file, ASCII names, multiple-entry long names, accented and CJK characters, an emoji surrogate pair, an exact thirteen-character long name, and fragmented files. The manifest retains exact image and payload hashes, geometry, allocation evidence, external source pins, and complete provenance. [Independent-fixtures documentation](independent-fixtures.md) describes regeneration and external verification.

The external **7-Zip 26.06** oracle reconstructs the images from the committed Dart data, extracts each physical image in full, and checks exact paths, sizes, hashes, directory inventory, and unchanged image hashes. Its successful result covers all four physical images, 36 file instances and eight directory instances. These are full extractions of the stated small reference volumes.

The GPT/MBR and UDIF envelopes, damaged-image controls, sparse large-offset cases, and amplification controls are explicitly **synthetic or derived**. They are not independent whole-disk specimens. In particular, the FAT12 GPT case at byte offset `2,199,023,266,304` verifies exact positional arithmetic and bounded reads through a sparse source; it is not a physical multi-terabyte extraction and does not enlarge the app input cap. Only the designated raw views are fully hashed; other large raw-view cases read bounded prefixes.

FatFs has its permissive BSD-style license notice retained in the provenance documentation. The formatter and 7-Zip executable are external validation tools and are not bundled with CrispCloud. This increment adds no GPL/NC runtime source, binary, or dependency. The production dependency manifests are unchanged.

## Failure discovery and retained attempts

The evidence retains failing intermediate attempts rather than replacing them with passing totals:

- The first broad gate found ten existing DMG compatibility regressions: an eager FAT recognition attempt decoded tiny compressed raw partitions during open. The correction only attempts FAT recognition when a partition can hold the supported minimum FAT12 layout, four 512-byte allocation sectors. Existing HFS/UDF/ISO recognition thresholds and failure behavior remain intact. A positive 2,048-byte FAT12-in-DMG control proves the boundary still admits the smallest supported volume. Provider errors and short reads retain their original failure identity. The final broad gate includes these corrections.
- An interim broad fallback swallowed established large-image decode errors; that approach was replaced by the precise minimum-size guard. Both attempts remain distinctly named in the evidence directory.
- The first final portable JavaScript attempt failed in the shared synthetic UDIF fixture's unsupported Uint64 accessor, before the production DMG reader was called. The bcd test-only correction and transition receipt account for the fix. Its original logs and receipt remain under `fat-portable-fixture-uint64-first-*`.
- The next attempt completed every VM/JS assertion but failed raw JSON equality because of the zlib length diagnostic. Exact original files remain under `fat-portable-zlib-metadata-first-*`, with a preservation receipt mapping original log names and hashes. The final helper's explicit semantic comparison records this difference rather than claiming byte-identical raw output.

## Qualification limits

These are read-only FAT and validated-partition browsing/extraction profiles. The evidence does not qualify filesystem repair, deleted-file recovery, mounting, partition-table writes, FAT mutation, full extended/logical MBR discovery, exFAT/NTFS/APFS support, or preservation of every historical FAT OEM code page. Supported Unicode long names are distinguished from unsupported legacy aliases in the profile.

The DMG budget controls exercise the actual shared 64 MiB logical FAT metadata, 64 MiB compressed backing-input, and 256 MiB decoded-work ceilings with synthetic cache-miss amplification fixtures. They verify that later partitions remain raw/unprobed after the allowance is exhausted and that under-limit cache reuse succeeds. FAT metadata requests are at most 64 KiB; compressed DMG chunks retain their separate existing chunk limit, so this is not a claim that every underlying DMG read is 64 KiB.

GitHub-hosted CI status and branch/PR preservation are recorded separately by the integration owner. Local qualification does not imply hosted checks have passed.
