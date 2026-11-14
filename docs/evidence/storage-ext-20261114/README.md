# Read-only ext filesystem qualification

The bounded Linux ext filesystem increment is implemented and locally qualified
at **`8bbdc25c7eca7598215bdc1053e8558ef3f5d643`**. Later commits on
`integration/storage-ext-20261114` add documentation and evidence without
changing that source. Review is tracked in
[PR #102](https://github.com/CrispStrobe/CrispCloud/pull/102).

The earlier FAT work was already saved and merged through
[PR #101](https://github.com/CrispStrobe/CrispCloud/pull/101). This continuation
starts from main `a34f7fcab53441da7d1d6c96e9d9e5ba25111907`, preserving its
later catalogue, release and DOC changes. Historical FAT results remain under
[`../storage-fat-20261114/`](../storage-fat-20261114/) with their original pins.

## Final results

| Gate | Observed result | Record |
| --- | --- | --- |
| Native regression | **1,007 passed, 0 failed, 1 expected opt-in skip**, across 37 files | [Native summary](ext-final-native-summary.json), [receipt](ext-final-native-receipt.json) |
| Dart VM acceptance | **19 groups / 3,360 checks passed** | [VM output](ext-final-portable-vm.json) |
| Actual dart2js / Node acceptance | **19 groups / 3,360 checks passed**; complete JSON and serialized stdout exactly equal to VM, with no excluded fields | [Portable receipt](ext-final-portable-receipt.json), [JS output](ext-final-portable-js.json) |
| Strict scoped analysis | **30 changed Dart files, no issues**, using `dart analyze --fatal-infos` | [Analysis receipt](ext-final-analysis-receipt.json), [log](ext-final-analysis.log) |
| Production JavaScript release | **Passed**, version **1.3.0+23**, original production manifests; full source revision and version stamps verified | [Build receipt](ext-final-web-receipt.json), [native/web summary](native-and-web-validation.json) |
| Independent fixture reproduction | **Five complete images and 48 regular-file instances** reproduced exactly; all five `e2fsck -fn` checks passed, payloads independently extracted with `debugfs` | [Reproduction receipt](external-fixture-reproduction.json) |

The machine-readable roll-up is [final-validation.json](final-validation.json).
These runs overlap; their counts must not be summed into a larger test total.
The independent fixture result is bound to the generator, generated data and
manifest bytes; it is not represented as a full application test run.

Native tests cover all seven ext suites, FAT and partition-image readers,
ISO/HFS/UDF/DMG regressions, shared extraction and workspace behavior,
registry/dispatch controls, and archive/partition viewer widgets. The sole
skip is the existing physical TGZ member larger than 2 GiB, which requires
`CRISP_RUN_LARGE_ARCHIVE_TESTS=1` and was not enabled.

The native host profile disables only the optional ebook conversion hook in
an isolated copy. The original catalogue native hook compiled with the real
Rust toolchain. Production manifests were restored byte-for-byte afterward,
and the original lockfile remained unchanged during tests. The production web
build used a separate immutable copy with the original production manifest
graph throughout. These are host tests and a JavaScript release build;
native/device release packaging, browser interaction and WebAssembly are not
qualified by these results.

## Source and artifact binding

Native tests, strict analysis and the release build each checked **8,075
tracked non-document source and asset paths** against the saved source
revision before and after execution. No source drift was found. Portable
acceptance independently bound **5,032 selected source/configuration/fixture
paths**, including 4,975 Dart files, and hashed all **605 actual compiler
inputs** plus the package map and Dart/Node executables before and after.
The inventories have different purposes and their counts are not additive.

| Production artifact | Value |
| --- | --- |
| `main.dart.js` size | 27,764,490 bytes |
| `main.dart.js` SHA-256 | `28974f2dc299f2d246bfc537e0b41d178d552eeb322bb4be13f8db53fb36e37d` |
| Version stamp | `1.3.0+23` |
| Revision stamp | `8bbdc25c7eca7598215bdc1053e8558ef3f5d643` |
| Apple LZFSE license asset | Present and hashed in the build receipt |

Tool versions and actual native-library hashes are in
[validation-host-environment.json](validation-host-environment.json): Flutter
3.47.8, Dart 3.13.7, Rust 1.100.0 and Clang 19.1.7. Portable JavaScript ran
under Node v24.22.1. Exact commands, times, exit codes, tool and input hashes,
and unedited outputs are retained in the receipts and associated logs.

[native-web-evidence-index.json](native-web-evidence-index.json) maps original
native/web artifact names to their stored files. Large records use lossless,
deterministic gzip with original and stored hashes recorded. The index also
preserves the validation helpers. Portable receipt source and dependency
inventories are stored in full, and its receipt embeds the runner source.
[final-evidence-index.json](final-evidence-index.json) inventories the complete
evidence directory except itself, including otherwise ignored plain logs.

## Capability and boundaries

The original MIT Dart reader adds standalone ext volumes and admitted Linux
MBR/GPT partitions to Archive listing, F3 preview, read-only workspaces and
extraction. Regular hard links, sparse/unwritten data, direct/indirect maps,
extent trees, UTF-8 names and supported metadata checksums are covered.
The existing **Hex → Inspect partitions → Browse image** route uses the same
validated adapter. Raw partition access is retained alongside filesystem
files. No new runtime dependency is introduced.

Important integration fixes in the qualified source include full namespace
validation before removing special metadata from selectable entries, shared
handling in direct whole-image extraction, and explicit GPT signature
precedence over an ext marker that can occur in a valid GPT partition name.
Source failures, cancellation and cleanup ownership remain explicit.

This is a bounded read-only profile, with a 64 MiB buffered-member ceiling
and existing 8 GiB native source/streamed-member ceilings. Actual indexed
directory inodes, external xattr blocks, journal/orphan recovery,
`orphan_file`, unknown features and other excluded layouts are refused.
Links and special files appear only as disabled metadata and are never
followed or extracted. There is no mounting, device access, repair or
filesystem writing. Ext files inside DMG/VM containers are not newly
interpreted. The complete contract and budgets are documented in the
[ext profile](../../archive-ext-profile.md) and
[disk-image profile](../../archive-disk-image-profile.md).

The independently mastered corpus uses test-only e2fsprogs 1.47.2 and covers
ext2, clean ext3, ext4 UUID/explicit-seed CRC32c and legacy group CRC16
profiles at 1/2/4 KiB block sizes. Its largest complete image is 32 MiB.
Native positional UI checks use padded 80 MiB sources. Multi-TiB offsets,
partition wrappers and corrupt mutations are synthetic/derived controls,
not additional externally mastered large disks. External tools are not
shipped, linked or invoked by the app.

## Hosted CI and preserved history

Local qualification is complete. Hosted qualification has **not** completed:
the separate [hosted status snapshot](hosted-ci-status.json) records queued
and cancelled checks at the qualification source. The draft PR remains open;
these records do not claim a merge, deployment or successful hosted release.

Prior PR #101 hosted runs passed their test stages before an external FatFs
download failure and a formatting gate failure. This increment bounds and
hash-checks the external download, makes generated fixtures formatter-stable,
and registers ext native/portable coverage in the storage workflow. Earlier
hosted counts belong to their original checkout and are not attributed here.

Intermediate failures and fixes remain visible in [PROGRESS.md](PROGRESS.md),
[intermediate-evidence-index.json](intermediate-evidence-index.json) and
[intermediate/host-and-extraction-attempts.json](intermediate/host-and-extraction-attempts.json).
They include an incorrect test fixture selection, special-entry integration
failures, native widget readiness timing and rejected upstream download
bytes. A separate portable preflight bookkeeping attempt stopped before
tests while resolving Dart SDK dependency URIs. None is hidden or counted as
a final pass; the final receipts above are authoritative for the saved source.

Reference snapshots are in [reconciliation-start.json](reconciliation-start.json)
and [reconciliation-final.json](reconciliation-final.json). The latter records
12 branch heads, 92 PR heads and 21 tags at its stated timestamp, with all
branch/PR heads ancestors of the qualification source. These are snapshots,
not a claim that remote references cannot advance later. Incremental commits
preserve the earlier history without force-pushing it.
