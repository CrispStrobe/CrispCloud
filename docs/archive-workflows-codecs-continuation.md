# Archive workflows and compression continuation

Date: 12 November 2026. Baseline: `e103d8c6fd6dc8c8c3d73467a8a1eb15fb8471d4`.
Branch: `feature/archive-workflows-codecs-20261112`, stacked on the package-reader
work in PR #90. Implementation is saved in [draft PR #92](https://github.com/CrispStrobe/CrispCloud/pull/92).
The completed capabilities and observed gates are recorded here and in the
[verification record](archive-workflows-codecs-verification.md).

## Delivered

1. Reviewed archive-to-archive **copy** uses independently captured source
   and destination workspaces. Preserve ordinary content, empty directories,
   supported times and permissions. Revalidate the source before destination
   publication and reject two routes to the same physical outer container.
   Protection follows the destination; source archives are never modified.
   Pane F5/context Copy and clean workspace Copy out open the reviewed workflow.
   Archive-to-archive move needs a separate two-container recovery transaction.
2. A cancellable archive integrity/readability check provides progress, per-member
   results and SHA-256 digests. Report failures, skipped entries and cancellation
   explicitly. Passing means the tested regular members decoded and passed the
   checks their readers provide, not that a publisher was authenticated or every
   format carries stored payload checksums. F3's archive listing exposes **Test
   archive**, and the result dialog can copy the complete report. Existing
   resource limits apply.
3. Bounded LZ4 frames and LZMA-alone support reading, creation and eligible
   rewriting, including wrapped TAR. These four new creation options bring
   the picker to **28 choices**, from 24. Independent reference decoders check
   fresh output. A single-payload writer requires the immediate decoded payload;
   recursive views, multi-frame collections and opaque extensions cannot be
   flattened during save. Compression controls match each codec's real options.
4. CPIO reading includes the modern binary little- and big-endian layouts,
   with independent reference fixtures, bounded metadata and ordinary-member
   extraction. Ambiguous historical PWB structures and unsupported members
   remain unavailable. Existing newc/CRC writer eligibility stays separate,
   including supported mixed newc/CRC records.
5. Lzip v1 and UNIX compress `.Z`, including `.tar.lz`, `.tar.Z` and `.taz`,
   add read-only access. Lzip validates CRC32 and exact member lengths. UNIX
   compress has no stored checksum or decoded length; valid-code truncation
   and some bit changes cannot be detected by decoding alone.

Copy and integrity dialogs, plus new creation guidance, include English and all
eight existing translations. Tests exercise narrow translated layouts.

Readers, creation and mutation are distinct capabilities. Retain 64 MiB bounded
member/decoded-stream limits and the existing 256 MiB interactive workspace
limit; this increment does not make background/resumable jobs or remote
publication contracts available by raising caps.

## Independent feature inspiration

The user identified [VaultExplorer](https://github.com/R0b0To/VaultExplorer),
which is GPL-licensed, as an ideas-only reference. Review was limited to its
[README](https://github.com/R0b0To/VaultExplorer/blob/main/README.md) (blob
`d6163ed35c683016772f5d5c25b9786755364ad9`), release descriptions and high-level
documentation. No implementation source, tests, assets or dependencies were
read, copied or imported.

Useful product ideas include explicit verification, reviewed folder comparison
and synchronization, and consistent file operations inside containers. Its
generic check/repair feature does not establish archive repair support, and its
README does not expressly claim direct archive-to-archive transfer. CrispCloud's
new copy and integrity workflows are independent adaptations to its existing
transaction and reader architecture. Split/join, nested archives and many
viewers already exist in CrispCloud and should not be duplicated.

VHD/VHDX, encrypted block devices and additional filesystems require separate
block mapping, filesystem and credential designs. They are not advertised as
small extensions to an archive codec.

## Verification scope

- Successful cross-format copying, recursive and empty directories, independent
  passwords, conflicts and supported metadata; stale/changed/same-container
  source rejection; publication failure must preserve the source.
- Integrity reports for correct and corrupt data, unsafe/special entries,
  limits, password failures, cancellation and closed/stale viewer handles.
- Primary format specifications and independent liblz4/liblzma/libarchive
  readback/fixtures; malformed length, checksum, dictionary and framing tests.
- Focused service/widget tests, relevant archive/viewer regressions, fatal-info
  static analysis and standard release web compilation.
- Incremental fast-forward remote commits, no force push or main-branch merge.

## Checkpoints

Each implementation checkpoint was saved to the remote branch before the next
integration stage. Baseline work remains preserved in PR #90 and its own branch.

| Commit | Checkpoint |
| --- | --- |
| `32647c66` | Scope and ideas-only provenance |
| `b750414f` | Bounded LZ4 codec and independent reference checks |
| `17cfdfd1` | Strict LZMA-alone codec and independent reference checks |
| `f43540b4` | Integrity service, F3 action and translated report UI |
| `dad00149` | Captured archive copy and source publication guards |
| `6afe320d` | Reviewed copy in pane, context and workspace actions |
| `5b815e91` | Read-only Lzip v1 with CRC and exact boundaries |
| `b15260c1` | Read-only UNIX compress, width/reset fixtures and JS checks |
| `f2732501` | Shared routing/writers, 28 creation choices, binary CPIO and preservation regressions |

The final documentation checkpoint records **1,636 passing tests across 66
files**, **55 changed Dart files clean with fatal infos**, independent codec
checks and the release web result. The verification record distinguishes these
observed gates from native/live acceptance that remains outstanding.

## Remaining boundaries

Archive-to-archive moves, grouped changes inside the same physical container,
directory synchronization (G19), durable/background packing jobs (G21), and
backend-specific remote/browser publication remain separate work. No new
filesystem mounting, encrypted block-device handling, package installation,
archive repair or publisher-signature authentication is introduced. RAR writing,
CAB LZX/Quantum/spanning, APFS/UDF, VHD/VHDX, and signed-package mutation remain
outside the supported writer profiles. See the [format matrix](archive-format-coverage.md)
and [endpoint policy](archive-endpoints.md) for the exact per-format rules.
