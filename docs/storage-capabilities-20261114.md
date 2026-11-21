# Storage, archive and filesystem workbench

This is the current architecture summary for archive, container and disk-image
support. The original source assessment, candidate-library review and
per-increment evidence are preserved in the
[storage capability archive](storage-capabilities-details.md).

## Design

CrispCloud extends the existing byte-source, archive and operation contracts;
it does not add a second file-manager stack.

```text
pane / F3 / search / operations
            │
      format registry
            │
  archive reader/writer profiles
            │
  raw source, disk image or filesystem reader
```

Every operation declares its own read, create or edit capability. A reader
never implies a writer. Content signatures take priority over file suffixes.

## Implemented profiles

| Area | Current support |
| --- | --- |
| ZIP / 7z / TAR | Browse, extract, eligible creation and editing |
| Compressed TAR/files | gzip, bzip2, XZ, Zstandard, LZ4, LZMA, `.Z` |
| RAR | Existing reader plus native RAR5 Store creation/editing |
| ISO 9660 | Data ISO, Joliet and Rock Ridge subset; inspected data-image writer |
| DMG | UDIF raw/zero/ADC/zlib/bzip2/LZFSE/XZ-LZMA; HFSX data-image writer |
| HFS+ / HFSX | Read regular data forks; fresh HFSX creation |
| UDF | Bounded UDF 1.02–2.01 physical Type 1 reading |
| FAT | FAT12/16/32 read-only |
| ext2/3/4 | Bounded classic/extent read-only profile |
| NTFS | Bounded clean NTFS 3.0/3.1 read-only profile |
| MBR/GPT images | Partition inspection and supported filesystem browsing |

Also supported: ZIP recovery to a new file, DMG codec profiles, package payload
inspection and raw partition slices.

## Rules

- Read-only means read-only. Unsupported metadata blocks rewriting instead of
  producing an approximate container.
- Writers verify the complete output with an independent reader before
  publication.
- Source files are retained.
- Ownership, ACLs, resource forks and extended attributes are not invented.
- Setuid/setgid inputs are refused when ownership cannot be preserved.
- No package is installed, no member is executed and no image is mounted or
  written to a physical disk.

## Recovery is separate

Recovery tools create a new output. They do not patch the damaged source in
place.

- ZIP salvage verifies stored/deflated records and publishes exclusively.
- Filesystem readers report validated structures only; they are not repair
  engines.
- A verified prefix does not prove a truncated container is complete.
- Binary comparison is a separate bounded read, not a recovery claim.

## Licensing

The addition policy accepts MIT, Apache-2.0, BSD, MPL and comparable terms.
GPL/LGPL-backed engines are not introduced through a permissive wrapper.

This is an addition policy, not a relicensing of CrispCloud. CrispCloud remains
AGPL-3.0; existing packages retain their own notices.

## Remaining gaps

- VM/container image semantics beyond raw partitions and supported filesystems.
- APFS file views.
- exFAT and deleted-file recovery.
- Filesystem repair or journal replay.
- Signed package rebuilds (APK/IPA/MSIX and similar).
- Broader compressed RAR creation without an external engine.
- Power-loss durability and browser quota acceptance for caches.

## Related

- [Archive coverage](archive-format-coverage.md)
- [ZIP recovery](archive-zip-recovery.md)
- [DMG codecs](archive-dmg-codecs.md)
- [Partition inspection](disk-partition-inspection.md)
- [Binary comparison](binary-comparison-profile.md)
- [Original assessment archive](storage-capabilities-details.md)
