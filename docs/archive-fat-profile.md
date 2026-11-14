# Read-only FAT12, FAT16 and FAT32 profile

`lib/services/archive_fat_reader.dart` supplies an original MIT-licensed Dart
reader for FAT volumes through the existing `koni.ByteSource` and
`ViewerArchive` contracts. It lists safe files and directories, previews bounded
members, and streams file contents from validated allocation extents. It does
not mount a filesystem, execute boot code, write sectors, repair allocations or
recover deleted files. There is no new native bridge or runtime dependency.

This document describes the reader's admitted profile. A successful listing is
evidence that the referenced metadata satisfies these checks. It is not a full
filesystem consistency check, an authentication of file contents, or a grant to
edit the source image.

## Volume recognition and geometry

The non-owning `hasFatVolumeRecognition` probe reads at most the first 512
bytes. It requires a supported boot jump and the signature at byte offsets 510
and 511, rejects the exFAT identifier, then recognizes either an explicit FAT
label or a plausible BPB layout. An explicit FAT label still recognizes a
malformed BPB so opening can report a FAT-specific error. The probe never closes
its input and does not establish validity.

Opening validates the BPB and chooses FAT12, FAT16 or FAT32 from the calculated
data-cluster count, using the specification's 4,085 and 65,525 boundaries. The
human-readable FAT label never selects the variant. The supported geometry is:

| Field | Admitted values and checks |
| --- | --- |
| Logical sector size | 512, 1,024, 2,048 or 4,096 bytes; boot signature remains at offsets 510–511. |
| Cluster size | Power-of-two sectors per cluster, with a maximum allocation unit of 32 KiB. |
| Reserved area | Nonempty; FAT32 advisory pointers must stay inside it. |
| Total sectors | Exactly one of the 16-bit and 32-bit counts is nonzero. The declared volume must fit the source. Extra source bytes are ignored with a visible notice. |
| FAT copies | One or two. The table must have enough bytes to address every declared data cluster. |
| FAT12/16 root | Nonempty, fixed root-entry area whose size is a whole number of logical sectors. |
| FAT32 root | A valid allocated cluster chain; FAT16-size and fixed-root fields must be zero; filesystem version must be 0.0. |
| Data references | Cluster indices must be within the data region and outside free, reserved, bad and end-marker ranges. FAT32 geometries reaching reserved cluster indices are outside this profile. |

Sector addressing uses exact Dart integers within the shared JavaScript-safe
integer range. The core opens a volume whose BPB is at source offset zero;
partition and DMG adapters supply bounded views for embedded volumes. The BPB's
hidden-sector field is not added a second time to a view-relative offset.

## Allocation validation and payload reading

Every visible regular-file chain and directory chain is validated before the
reader returns any listing. A regular file must allocate exactly the number of
clusters required by its declared length and end in a valid end-of-chain marker.
The final allocation unit's slack is excluded from extraction. Empty regular
files must have no starting cluster. Directory chains are fully checked even
when an early directory end marker means later allocation units need not be
parsed as records.

The traversal rejects loops, cross-links between different live members,
references into directory storage, insufficient allocation, allocation beyond
the declared file length, and free, bad, reserved or out-of-range references.
It does not scan unrelated FAT entries or infer a replacement chain. Deleted
records, unused allocation units and lost chains are omitted.

Successive physically adjacent allocations are coalesced into immutable
extents. Fragmented, reversed and separated allocations retain logical chain
order. Reads and streams use those extents without consulting mutable FAT pages
again. The source must continue to satisfy its provider's snapshot and
revocation contract; this reader does not hash the entire volume or copy it into
memory. Filesystem metadata does not authenticate payload contents.

Payload requests are at most 64 KiB each. Buffered reads keep the application's
64 MiB ceiling even if a caller authorizes a larger streamed member. Streaming
also enforces the opening caller's `maxMemberBytes`; the FAT file-size field is
itself limited to an unsigned 32-bit byte count. Listing an oversized file does
not authorize reading it beyond the caller's allowance.

## FAT copies, dirty state and FAT32 advisory sectors

When mirroring is enabled, both FAT copies must agree for the reserved header
entries and every allocation entry traversed by the listing. Unreferenced
entries are not compared. FAT32 allocation values ignore the reserved upper
four bits, including during mirror comparisons.

When FAT32 mirroring is disabled, only the BPB-selected active table is
authoritative. The reader validates the index, reports which table is used and
never falls back to an inactive copy. Unknown extended flags and filesystem
versions are explicit unsupported-profile errors.

FAT16 and FAT32 reserved entry 1 is checked for its required fixed bits. A
cleared clean-shutdown flag produces a visible dirty-volume notice. A cleared
no-error flag produces a visible historical disk-I/O-error notice. These flags
do not trigger repair or assert that readable files are intact.

FAT32 FSInfo is advisory. The reader checks its signatures and the range of its
free-cluster and next-allocation hints, accepts the documented unknown values,
and ignores invalid hints with a notice. No file chain is derived from a free
space hint. Absent FSInfo is also reported. Present backup boot metadata is
compared with the primary BPB and its signature; differences are visible, while
the validated primary remains authoritative. There is no reconstruction from a
backup, no writeback of corrected hints, and no claim that backup FSInfo or
boot-code sectors were fully verified.

## Names, paths and directory records

ASCII 8.3 names support embedded spaces, trimmed padding and the NT lowercase
flags for the base and extension. Unknown case-flag bits are outside the profile.
Without a valid long name, a non-ASCII OEM short name is explicitly unsupported:
the image does not supply a trustworthy universal OEM code-page selection.

VFAT long names require a complete, correctly ordered sequence of at most 20
records, a matching raw-short-name checksum, valid type and reserved fields,
canonical NUL/`FFFF` padding where needed, and a name of 1–255 UTF-16 code units.
Exactly full 13-unit records do not need a terminator. Valid surrogate pairs are
preserved; unpaired surrogates and reserved Unicode units are rejected. Orphan,
overlapping, incomplete or malformed active long-name records fail the volume
opening. They never silently downgrade a member to its short alias. Deleted
long-name records are skipped like other deleted records.

If a valid Unicode long name exists, a non-ASCII OEM alias remains an opaque
checksum and identity value. Its code-page-specific bytes are not used as a
path, decoded with a guessed code page or folded as ASCII. This matters for
DBCS aliases: a trailing byte can coincide with an ASCII backslash or lowercase
letter. Structural controls remain rejected; exact duplicate raw aliases are
detected. The reader does not claim OEM code-page collation or lookup through
these aliases.

Exposed names must be safe single components. Separators, parent traversal,
controls, colon and other forbidden extraction punctuation, leading or trailing
spaces, trailing dots and reserved DOS device stems are rejected or explicitly
unsupported. The reader preserves an admitted name; it does not sanitize an
unsafe name into a different one. Per-directory checks reject duplicate exposed
names and conflicts with decoded ASCII aliases using both uppercase and
lowercase forms. This conservative collision check is not an implementation of
every host filesystem's Unicode normalization or collation rule; destination
creation retains its own collision checks.

Subdirectories require valid `.` and `..` records in their first two slots,
including correct self and parent references. A child of the root uses zero for
its parent reference, including FAT32. Directory size fields must be zero. One
well-formed root volume-label record is allowed and omitted from members.
Unsupported attribute bits and ambiguous record types fail explicitly. The
directory end marker terminates the logical namespace; stale records after it
are not resurrected.

FAT last-modification fields are represented as local wall-clock `DateTime`
values because the stored fields carry no time-zone offset. Invalid or locally
unrepresentable fields are omitted with a notice. The reader does not synthesize
POSIX permissions, preserve access-control lists or extended attributes, or
claim time-zone-independent timestamp restoration.

## Resource bounds and composition

Opening limits may be lowered by a caller. Values above the hard ceilings are
rejected rather than silently widening the profile. Each budget has a separate
purpose:

| Resource | Default and hard ceiling | Accounting |
| --- | --- | --- |
| Listed entries | 100,000 | Files and directories, excluding dot records and the volume label. |
| Directory depth | 64 | Root is depth zero. |
| Directory allocation | 32 MiB | Fixed root bytes and every allocated directory cluster, including allocation after a logical end marker. |
| Actual metadata reads | 64 MiB | Boot/advisory sectors, FAT cache misses and directory reads; repeated cache misses count again. Payload reads are separate. |
| Decoded component text | 16 MiB | Two bytes per retained UTF-16 code unit. |
| Retained full-path text | 16 MiB | Two bytes per code unit, including repeated parent prefixes. An individual path is limited to 4,096 units. |
| Cluster visits | 1,048,576 | Every attempted live-chain traversal, including work before a failure. |
| Allocation extents | 100,000 | Newly created coalesced runs for files/directories and the fixed root. |
| FAT cache | 1 MiB | At most 256 pages of 4 KiB; the final FAT page may be shorter. |
| Single source request | 64 KiB | Both metadata and member payload requests. |

The exported `ArchiveFatTraversalBudget` shares cluster and extent allowances
across the FAT volumes of one disk image. Failed attempts consume allowance;
they do not refund work before another volume is tried. Its public counters are
`clustersVisited`, `extentsCreated`, `remainingClusters` and `remainingExtents`.
It retains only integers.

Adapters must also compose their aggregate listing I/O, entry counts and
retained full-path text. A child's relative paths and an adapter's prefixed
display paths are separate retained allocations. Per-volume limits alone are
insufficient when several volumes stay open. The FAT page cache and global
claimed-cluster set are released immediately after a successful traversal, so
each open child retains only its listing and immutable payload extents, rather
than one cache and allocation ownership map per volume.

## Ownership, cancellation and failure types

`openFatArchive` takes ownership of the supplied source as soon as it is called.
Every opening failure, including an invalid caller limit, attempts to close the
source without replacing the original error. A successful archive closes the
source through the shared idempotent `ViewerArchive.close` lifecycle. An adapter
that retains ownership of a whole disk supplies a borrowed slice whose close
does not close the parent disk.

Optional `isCancelled` checks run before and after I/O and at parsing and chain
checkpoints. Cached loops yield to the event loop periodically, so a large
cached chain or directory containing empty files cannot indefinitely postpone
revocation. `ArchiveFatCancelledException` is a distinct
`ArchiveViewException` subtype and must propagate through adapters. It is not a
reason to downgrade the volume to an unsupported-filesystem fallback. An
exception thrown by the source or cancellation callback also propagates as the
original object.

Format failures use `ArchiveMessageCode.corrupt`, supported-format boundaries
use `ArchiveMessageCode.unsupported`, and resource bounds use `archiveLimit` or
`entryLimit`. Opening is atomic: no partial FAT listing is returned on a failed
chain, invalid name or exceeded resource bound. A disk adapter may retain an
explicit raw partition view for a failed filesystem profile, but must keep the
failure visible and must not swallow cancellation, transport or revocation.

## Verification and source attribution

The synthetic assembler in `test/support/archive_fat_fixture.dart` is original
test code, independent of the reader. Core tests cover the three cluster-count
variants and boundaries, sector sizes through 4 KiB, packed FAT12 page crossings,
fragmentation, exact lengths, Unicode names and malformed controls, parent
records, mirrored and selected FATs, FAT32 high bits, state flags, advisory
sectors, resource composition, cancellation, source ownership and sparse large
physical offsets.

Separate external reference images are mastered by ChaN FatFs R0.16 and
cross-read by 7-Zip; see the reference fixture provenance and acceptance evidence
alongside the storage-capabilities integration documentation. These external
tools are test oracles, not shipped application dependencies. Validation claims
and exact run counts belong to the dated evidence record rather than this
format contract. A sparse large-offset fixture is not a full physical
multi-gigabyte extraction test.

The implementation is based on published structure facts, with original control
flow, bounds and tests. It incorporates no filesystem implementation, copied
specification text, GPL/AGPL code, noncommercial code, or new third-party runtime
library. Primary references consulted on 2026-11-14:

- Microsoft's *FAT32 File System Specification, FAT: General Overview of
  On-Disk Format*, version 1.03, 2000-12-06, for BPB geometry, cluster-count type
  selection, FAT entries, allocation markers, directory records, VFAT sequences,
  FAT32 state flags and advisory structures. The
  [Microsoft Download Center record](https://www.microsoft.com/en-ie/download/details.aspx?id=53426)
  identifies `fatgen103.doc`; a readable copy of the Microsoft-authored document
  is [preserved by PCjs](https://www.pcjs.org/documents/papers/microsoft/MS_FAT_OVERVIEW_103-2000-12-06.pdf).
- [UEFI 2.11, Media Access, section 13.3](https://uefi.org/specs/UEFI/2.11/13_Protocols_Media_Access.html),
  for the FAT filesystem context and distinction between short-name and Unicode
  naming. This reader does not claim implementation of UEFI protocols or its
  complete collation rules.
- Microsoft Learn,
  [Double-byte Character Sets](https://learn.microsoft.com/en-us/windows/win32/intl/double-byte-character-sets)
  and [FsRtlIsFatDbcsLegal](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ntifs/nf-ntifs-_fsrtl_advanced_fcb_header-fsrtlisfatdbcslegal),
  for the code-page-dependent interpretation of OEM/DBCS aliases and why raw
  trail bytes must not be treated as standalone ASCII separators.
- Microsoft Learn,
  [Naming Files, Paths, and Namespaces](https://learn.microsoft.com/en-gb/windows/win32/fileio/naming-a-file),
  for long-name preservation and destination naming constraints.

Specification copyright and any patent terms are separate from the MIT license
of this original reader. The application does not redistribute the Microsoft
document or claim that consulting it grants unrestricted rights to every FAT
implementation or write profile.
