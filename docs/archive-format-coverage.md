# Archive and disk-image coverage

CrispCloud uses one format registry for pane navigation, preview, search and
extraction. A filename suggests a reader; the reader validates the actual
container. Content signatures win over misleading suffixes.

**Readable does not mean writable.** The full per-format profile is preserved in
the [archive details](archive-format-details.md).

## Capability summary

| Family | Browse / extract | Create | Edit existing |
| --- | --- | --- | --- |
| ZIP / CBZ | Yes | Yes | Eligible unencrypted profiles |
| 7z / CB7 | Yes | Yes | Eligible unencrypted profiles |
| TAR / compressed TAR | Yes | Yes | Inspected regular-file profiles |
| Single compressed files | gzip, bzip2, XZ, Zstandard, LZ4, LZMA, `.Z` | One file | Replace one ordinary payload |
| RAR / CBR | Existing reader; RAR5 Store stream | RAR5 Store | Inspected RAR5 Store only |
| ISO 9660 | Data ISO, Joliet, Rock Ridge subset | Data ISO | Inspected data-only profiles |
| DMG | UDIF codecs and supported filesystems | HFSX data DMG | Verified canonical HFSX profiles |
| HFS+ / HFSX | Regular data forks | Fresh HFSX | No |
| UDF | Bounded physical Type 1 | No | No |
| FAT | FAT12/16/32 | No | No |
| ext2/3/4 | Bounded classic/extent profiles | No | No |
| NTFS | Bounded clean 3.0/3.1 | No | No |
| Raw disk image | MBR/GPT slices and supported filesystems | No | No |

## Packages and special containers

- **JAR/WAR/EAR** — unsigned archives only; signing metadata blocks rewriting.
- **KMZ** — KML must remain at the top level.
- **AR/CPIO** — inspected regular-file profiles only.
- **RPM/CAB/XAR** — read-only in the supported profiles.
- **DEB/UDEB** — coordinated prebuilt control/data replacement only.
- **PE self-extracting archives** — checked overlays; the stub is never
  executed or silently discarded.
- **ZIP-based app packages** — APK, IPA, XPI, NuGet, VSIX, APPX/MSIX and similar
  formats need package-specific rebuild/signing workflows.
- **CRX/PKG/XIP/PBZX** — bounded payload inspection; signing/package metadata
  is not authenticated.

## Create and edit

**Create** writes a separate verified output. It opens the result, compares the
namespace and streamed file hashes, rechecks source versions and publishes only
after verification.

**Edit** stages member changes, repacks the whole container, verifies it and
publishes through the recovery journal. Unsupported structures produce a
read-only reason.

What callers should expect:

- ordinary permission bits are preserved only when the source backend provides
  them;
- ownership, ACLs, resource forks and extended attributes are not copied;
- setuid/setgid inputs are refused;
- source files are retained;
- no archive action installs a package, executes a member, mounts an image or
  writes a physical disk.

## Recovery

Select a local ZIP/CBZ and choose **Recover ZIP to new file…**. The report lists
verified stored/deflated records and explains exclusions. The rebuild is opened
by a separate reader and verified before exclusive publication. Existing files
are never replaced.

Recovery supports measured deflate data descriptors. Stored descriptors,
encryption, ZIP64, self-extractors and split sets are outside that recovery
profile. A verified prefix does not prove a truncated archive is complete.

## Bounds

- Native archive creation/editing and eligible extraction use an 8 GiB budget.
- Browser and buffered paths have smaller limits.
- Numbered 7z sets are bounded by part count and aggregate size.
- Decompressed TAR limits differ between streaming and buffered paths.
- Filesystem readers enforce block, cluster and directory bounds.
- Every successful read reports only its inspected profile; unknown structures
  remain unavailable rather than interpreted loosely.

## Related

- [Archive operations](archive-commander-workflows.md)
- [ZIP recovery](archive-zip-recovery.md)
- [DMG profiles](archive-dmg-codecs.md)
- [Partition inspection](disk-partition-inspection.md)
- [Full coverage archive](archive-format-details.md)
