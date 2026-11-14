# FAT and partition-image continuation

Baseline: `25061e2250f394c41690a70aa3ac56e136b5168e` on
`integration/storage-capabilities-20261114` (draft PR #101).
Before this continuation, all 11 published branch heads and 91 PR heads were
fetched and verified as ancestors. Main remained at `14e022eb`; no additional
merge was necessary. The exact refs are in
[`reconciliation-before-fat.json`](reconciliation-before-fat.json).

This is the implementation plan captured before qualification, not a claim
that the listed capabilities or checks have already passed.

## Scope

1. An original MIT Dart reader for a bounded FAT12/16/32 profile, reusing
   `koni.ByteSource`, `ViewerArchive`, existing extraction and safe-member
   policies. It will support listing, preview and extraction without mounting
   or writing the volume. No exFAT or repair claim is included.
2. A partition-image adapter over the existing GPT/primary-MBR inspector,
   validating unambiguous table geometry before exposing raw partition slices
   and supported FAT contents. Extended chains, dynamic storage and encryption
   remain outside the filesystem interpretation profile.
3. Shared dispatch, read-only capability policy, native positional viewer and
   workspace integration, plus FAT filesystems inside existing UDIF views.
   Partition inspection should lead to the established archive browsing flow
   while retaining the selected sector geometry and source identity.
4. Independent fixture generation/readback, adversarial service tests,
   integration and viewer tests, actual compiled-JavaScript acceptance,
   scoped analysis and a production web build at an explicit remote revision.

## Design constraints

- FAT kind comes from validated BPB geometry and cluster count, not the label.
- All source reads, metadata, chains, entries, directory depth, retained paths
  and caches need explicit bounds. Shared image budgets cover child volumes.
- LFN ordering/checksums/UTF-16 and safe path components must be validated;
  ambiguous names, allocation loops and cross-links must not become fabricated
  recovered files.
- FAT mirrors and active FAT selection have explicit behavior. FSInfo and dirty
  status are metadata, not authority to repair or replay the filesystem.
- Filesystem readers cannot grant writable archive eligibility. No existing
  ISO, DMG or archive writer profile is broadened by recognition alone.
- Whole images and raw partitions remain subject to the existing host input,
  preview and extraction limits; exact large-offset service fixtures do not
  establish physical large-image extraction qualification.
- The addition policy remains MIT/Apache/BSD/MPL or similar, without GPL/NC
  runtime additions. Reuse the existing runtime graph. Test-only writer/oracle
  tools and original fixture payloads must have explicit provenance.
- Root publishes incremental remote checkpoints with a branch-head lease;
  existing branches and earlier qualification receipts remain intact.

FAT is the first filesystem adapter in roadmap stage 5. ext/NTFS adapters,
broader VM/OCI semantics and later recovery/copy stages remain separate work.
