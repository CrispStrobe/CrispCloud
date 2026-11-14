# FAT and partition-image qualification

This continuation implements the first filesystem adapter in roadmap stage 5:
read-only FAT12/16/32 and validated MBR/GPT image browsing, integrated with
CrispCloud's archive viewer, workspace and existing extraction contracts.
The work is on `integration/storage-capabilities-20261114`, reviewed in
[draft PR #101](https://github.com/CrispStrobe/CrispCloud/pull/101).

## Implemented behavior

| Area | Result |
| --- | --- |
| Standalone volumes | FAT12/16/32 with 512–4096-byte logical sectors, clusters through 32 KiB, fragmented live files, checked UTF-16 long names, safe ASCII short names, nested directories and empty files. |
| Partitioned images | Validated primary MBR or matching, CRC-checked GPT mirrors; deterministic `partition-<table-index>/raw.img` entries and eligible FAT `files/` trees. |
| Hex integration | **Inspect partitions → Browse image** retains the chosen 512/4096-byte geometry for the captured source and revalidates it before opening. Invalid or ambiguous tables do not receive browsing authority. |
| Viewer and workspace | Shared recognition and explicit read-only policies; native positional F3 preview and read-only native workspace extraction, including images above the buffered 64 MiB limit. |
| DMG composition | Supported FAT volumes inside UDIF retain their raw view and forward filesystem notices. HFS/UDF notices are also forwarded. Separate logical, backing-input and decompression-work budgets account for compressed-block amplification. |

The reader derives the FAT variant from the validated cluster count, not the
filesystem label. It checks every published live chain before returning a
listing, rejects loops/cross-links and malformed long names, compares traversed
mirrored FAT entries, and respects the selected active FAT when mirroring is
disabled. Payload reads follow immutable coalesced extents. Dirty/error flags
and advisory metadata remain notices; listing does not perform repair.

Unknown or ineligible partition types remain exact raw slices. Unsupported or
corrupt FAT children do not expose a partial file tree. Transport, revocation
and cancellation failures stop opening and retain the original failure, even
when an exception resembles a format error or cleanup also fails. The public
viewer dispatch has one source owner across its nested failure-cleanup layers.

The [FAT profile](../../archive-fat-profile.md),
[partition-image profile](../../archive-disk-image-profile.md),
[partition inspection guide](../../disk-partition-inspection.md) and
[format matrix](../../archive-format-coverage.md) define the exact operation
and format boundaries.

## Independent inputs and readback

ChaN FatFs R0.16 independently formatted and populated four complete physical
reference images. The corpus includes FAT12, FAT16, FAT32 and FAT16 with
4096-byte sectors. Nine original files and two directories per volume cover
Unicode, an emoji surrogate pair, an exact 13-unit name, a long multi-record
name, nested/empty entries and fragmentation created by interleaved writes.

The committed sparse representation reconstructs each entire image exactly,
including its full SHA-256. The fixture generator pins the upstream archive,
individual source files, configuration and original host shim. Reproduction
compares the generated Dart and manifest byte-for-byte. An external 7-Zip
26.06 independently extracts all **four images and 36 files**, verifying every
name, length and payload hash while leaving each input unchanged.

See [independent-fixtures.md](independent-fixtures.md), the
[fixture manifest](../../../test/fixtures/archives/fat-reference-manifest.json),
[reproduction receipt](fixture-reproduction-receipt.json) and
[independent extraction receipt](fat-sevenzip-oracle.json). The largest fully
mastered physical reference is 64 MiB. MBR/GPT wrappers, corrupt mutations and
multi-terabyte offsets are separately identified as derived or synthetic.

## Qualification records

The full native regression gate passed at
`da5c889795e5c5f684bd851dc0ffb6e272646122`: **843 passed, zero failures and
one existing opt-in skip across 29 files**. All 1,978 checked Dart and production
manifest paths matched that exact commit and the primary checkout before and
after execution. Strict analysis at that revision found no issues in the
26 changed Dart files.

The later checkpoint `bcd44b86a410d4f52ca7a7cd694294dbef05c181` changes only the
shared DMG test image writer, plus already saved evidence. Its app sources and
production manifests are identical to the 843-pass revision. Follow-up records
identify their own exact source revision; the full native run is not relabeled.

| Check | Result | Source and receipt |
| --- | --- | --- |
| Full native regression gate | **843 passed, 0 failed, 1 existing opt-in skip**, 29 files | `da5c8897`; [summary](fat-final-gate-summary.json), [source binding](fat-final-gate-source-binding.json) |
| Fixture-dependent native follow-up | **229 passed, 0 failed, 0 skipped**, 9 files | `bcd44b86`; [summary](fat-fixture-followup-gate-summary.json), [source binding](fat-fixture-followup-source-binding.json) |
| Final strict scoped analysis | **27 Dart files, no issues** | `bcd44b86`; [receipt](fat-fixture-followup-analysis-receipt.json) |
| Final VM and actual compiled JavaScript/Node | **15 groups and 1,276 checks per target**, all commands successful; matching semantic results | `bcd44b86`; [receipt](fat-final-portable-receipt.json) |
| Independent complete extraction | **4 images, 36 exact file payloads and 8 directory instances** | [7-Zip receipt](fat-sevenzip-oracle.json) |
| Fixture reproduction | Generated reference Dart and manifest reproduced byte-for-byte | [receipt](fixture-reproduction-receipt.json) |
| Production JavaScript release | **Passed**, unchanged production manifests, version `1.2.9+22`, exact `bcd44b86` stamp verified | [build receipt](fat-final-web-release-receipt.json), [final source verification](fat-final-source-verification.json) |

The [source transition receipt](fat-test-fixture-source-transition.json) verifies
all **1,051 production source/manifest paths** are identical between the broad
gate and the fixture-only checkpoint. The 229-test follow-up checks the nine
native files that depend on the shared DMG fixture. Its input and output
bindings again verify all 1,978 Dart/manifest paths. The skipped broad-gate case
is the pre-existing physical TGZ member above 2 GiB; it requires
`CRISP_RUN_LARGE_ARCHIVE_TESTS=1` and was not enabled for this run.

The production `main.dart.js` contains 27,656,008 bytes with SHA-256
`c0bb7bd0e6ffd61a64f0c33be80c60e4daf02023285fd26d16a5a2b5f4a4de8c`.
The compiled version and complete source stamp are present, and the release
includes the Apple LZFSE license asset. Final verification rechecks the source,
portable inputs/helper/logs, fixture sources and compiled output hashes after
the build.

The completed source-bound gate, actual compiled-JavaScript acceptance,
production release build and their limits are summarized in
[final-validation.json](final-validation.json). Raw logs and source hashes stay
beside their receipts. Intermediate runs remain preserved and are not relabeled
as tests of a later revision. Counts from overlapping runs are not additive.

The first integration run recorded 122 passes and four test failures. Two
workspace assertions incorrectly expected an initial revision of zero; they
now capture the revision after opening and verify that rejected mutations do
not change it. Two UI assertions waited for unbuilt rows in a lazy list; they
now wait for the loaded archive heading and scroll to the member before
checking and previewing it. The subsequent focused run passed 167 tests.

The first broad run recorded 824 passes, ten DMG control errors and one
existing opt-in skip. The FAT recognition probe was decoding tiny 1024-byte
raw payloads during opening, changing an existing deferred-extraction
contract. FAT probing now begins only at the tight 2048-byte minimum volume
size, and a positive boundary fixture proves that a valid minimum FAT12 volume
still opens. Fatal codec checks on filesystem-sized probes remain intact.
Additional first-probe and short-read controls verify that source failures
cannot become a successful raw-only listing. Intermediate attempts are retained
separately from final qualification.

The first expanded portable run passed 1,276 checks on the VM, compiled to
JavaScript, then stopped while constructing its first synthetic DMG: dart2js
does not implement `ByteData.setUint64`. The shared fixture writer now emits
the same big-endian bytes using two 32-bit writes. The failure occurred before
the DMG reader was called; the production FAT, partition and DMG readers already
use supported field accessors. This failed attempt is retained separately from
the final VM/JavaScript results.

The final portable receipt preserves both complete outputs. Their sole
difference is the synthetic zlib UDIF's encoded length: **8,026 bytes on the VM
and 8,033 bytes on JavaScript**, because the locked archive package selects
different encoders. Both valid wrappers produce identical payload hashes and
the same complete raw FAT-volume hash. Raw JSON equality is explicitly false;
semantic equality excludes only
`derived_udif_wrappers.synthetic-udif-zlib.udif_bytes` and requires every other
field to match exactly. The earlier comparison that rejected this diagnostic
difference is retained as a separate intermediate attempt. The
[encoder source note](fat-portable-zlib-platform-note.json) binds the conditional
exports and both encoder implementations to their actual package-file hashes.

Review also found and fixed a real DMG composition issue: many small FAT-page
requests could repeatedly expand much larger compressed blocks. FAT listing
now shares 64 MiB logical metadata, 64 MiB backing-input and 256 MiB cache-miss
expansion allowances. The regression performs real repeated decompression,
verifies refusal before the next disallowed read, and confirms that raw
partition access survives. Separate controls cover callback/provider identity,
throwing cleanup, cached reads and final listing cancellation checkpoints.

Local native tests use an isolated validation checkout with only the optional
ebook conversion hook temporarily disabled. Production `pubspec.yaml` and
`pubspec.lock` are restored byte-for-byte. The production JavaScript build uses
the unchanged production manifests. Native host tests and a web compilation
do not establish device/native release packaging or browser interaction.

## Preservation and licensing

Before this continuation, all **11 remote branch heads and 91 PR heads** were
fetched and verified as ancestors of `25061e2250f394c41690a70aa3ac56e136b5168e`.
Main remained at `14e022eb51c417803a1913131e78912a8a19b3be`; no additional merge
was required. The [initial reconciliation receipt](reconciliation-before-fat.json)
records the exact references. Earlier LZFSE, UDF and ZIP recovery work remains
in this branch with its original evidence directories and qualified revisions.
Implementation, fixes and validation are saved in incremental remote commits.
The [final reference check](reconciliation-final.json) repeats the branch/PR
ancestry check at the qualification source and confirms all 20 remote tags are
retained. One historical archive tag has a target outside that branch ancestry;
the tag remains preserved. The [checkpoint record](remote-checkpoints.json)
lists the ten incremental remote checkpoints through the final source revision;
subsequent commits contain documentation and evidence only.

Both new filesystem/image readers are original MIT Dart implementations of
published on-disk structures. This increment changes no Pub or native runtime
dependency. FatFs is an external BSD-style fixture writer; 7-Zip is an external
test oracle. Neither is shipped, linked or invoked by the app. No GPL/NC
runtime addition is imported. Existing project licensing is unchanged.

## Practical boundaries

- FAT is read-only. exFAT, OEM-only short-name decoding, deleted-file recovery,
  allocation repair, formatting and filesystem writes are outside this profile.
- Partition browsing admits primary MBR or fully validated mirrored GPT.
  EBR chains, dynamic storage, encrypted volumes, ext/NTFS/APFS and VM-container
  semantics remain outside this adapter. Raw access does not imply filesystem
  interpretation.
- Native F3/workspace input images retain the **8 GiB** host ceiling. A native
  workspace also counts the sum of raw entries and their overlapping file views
  against its aggregate 8 GiB content ceiling. Buffered members retain 64 MiB;
  remote, browser and nested paths retain their existing smaller bounds.
- Exact synthetic multi-terabyte positional tests do not qualify a complete
  physical multi-terabyte extraction. Existing physical archive tests above
  2 GiB remain opt-in and are identified separately in the gate summary.
- No new mounting, physical-device access, partition editing, general recovery,
  filesystem consistency guarantee or publisher authentication is claimed.
- Hosted GitHub checks are reported separately from completed local tests.
  JavaScript/Node acceptance is not WebAssembly or browser-engine acceptance.

At the [latest recorded hosted check](hosted-ci-qualification.json), the
qualified source had 35 canceled jobs and four queued jobs; the later evidence
checkpoint had 34 queued jobs. Neither canceled nor queued jobs is a passing
hosted qualification. Draft PR #101 remains open for review.

The remaining roadmap continues with separately reviewed ext/NTFS profiles,
broader containers, binary comparison, carving/rescue and transfer improvements.
