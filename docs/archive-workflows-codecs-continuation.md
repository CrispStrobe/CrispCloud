# Archive workflows and compression continuation

Date: 12 November 2026. Baseline: `e103d8c6fd6dc8c8c3d73467a8a1eb15fb8471d4`.
Branch: `feature/archive-workflows-codecs-20261112`, stacked on the package-reader
work in PR #90. This is an implementation plan, not a support claim; completed
checkpoints and observed validation are recorded below as they become available.

## Goals and ownership

1. Add reviewed archive-to-archive **copy** using independently captured source
   and destination workspaces. Preserve ordinary content, empty directories,
   supported times and permissions. Revalidate the source before destination
   publication and reject two routes to the same physical outer container.
   Protection follows the destination; source archives are never modified.
   Archive-to-archive move needs a separate two-container recovery transaction.
2. Add a cancellable archive integrity/readability check with progress, per-member
   results and SHA-256 digests. Report failures, skipped entries and cancellation
   explicitly. Passing means the tested regular members decoded and passed the
   checks their readers provide, not that a publisher was authenticated or every
   format carries stored payload checksums. Existing resource limits apply.
3. Extend portable compression support with bounded LZ4 frames and LZMA-alone
   where the independent format/reference checks establish safe support. Add
   creation and wrapped TAR choices only after verified independent readback.
   Existing-stream editing requires a complete preservation/boundary contract.
4. Extend CPIO reading to the modern binary little- and big-endian layouts,
   with independent reference fixtures, bounded metadata and ordinary-member
   extraction. Ambiguous historical PWB structures and unsupported members
   remain unavailable. Existing newc/CRC writer eligibility stays separate.

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

## Acceptance

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

- Scope recorded before implementation. Baseline work remains preserved in
  PR #90 and its own branch.
