# Read-only partitioned disk-image browsing

CrispCloud can expose a validated MBR or GPT disk image through the existing
Archive listing, preview and streamed extraction interfaces. The adapter is
original MIT-licensed Dart code. It reuses the app's partition inspector,
bounded byte-source slices and FAT/ext readers; it introduces no runtime dependency.

This is a browsing profile for an image file already supplied to the app. It
does not open physical devices, mount a filesystem, alter partition tables,
repair a filesystem, recover deleted entries or authenticate an image.

## Visible layout

Each admitted table entry has a deterministic directory based on its original
one-based table index:

| Entry | Meaning |
| --- | --- |
| `partition-001/` | First populated table entry's directory. Gaps in table indices remain gaps in these identifiers. |
| `partition-001/raw.img` | Exact bounded bytes of that partition, including its filesystem metadata and unused space. |
| `partition-001/files/` | Added only after a supported FAT/ext filesystem has been validated completely. |
| `partition-001/files/HELLO.TXT` | A filesystem member, read lazily from its verified allocation extents. |

Names from the GPT table and filesystem volume labels never determine these
synthetic directory names. Child paths must be relative, contain no backslash,
and contain no empty, `.` or `..` component. The child reader applies its own
name validation before the composite listing is created.

The raw image and its filesystem entries describe overlapping bytes. Extracting
both copies that content twice; the listing includes this notice. Raw entries
remain subject to the operation's size allowance. A large raw partition may be
listed even when the selected preview or extraction operation cannot read it.

## Partition-table admission

Recognition and admission are separate. Recognition performs bounded probes at
the MBR prefix and fixed primary/physical-tail GPT positions. A standalone FAT/ext
volume takes precedence over plausible partition records in its boot code. A
`55 AA` trailer with no plausible nonempty MBR record is not sufficient for
disk-image recognition. Recognition does not confer table authority.

Actual browsing reinspects the source and requires the following profile:

| Layout | Admission rule |
| --- | --- |
| Primary MBR | Valid signature, boot indicators and bounded, nonoverlapping primary records; at least one nonempty record. The first profile follows no extended partition chain. |
| GPT | Exactly one unambiguous supported geometry, protective MBR, primary header at LBA 1 and backup at the physical last sector, valid header and table CRCs in both copies, matching header geometry and full table contents, valid usable ranges and metadata placement, and no structural finding from the inspector. |
| Sector units | GPT can identify 512 or 4096 bytes. MBR has no self-describing logical-sector unit: absent an explicit selection, 512 bytes is assumed and disclosed. An explicit 4096-byte choice is supported. |
| Damaged or conflicting metadata | Refused as a disk listing. A valid surviving GPT mirror is evidence for inspection, not permission to reconstruct the other copy or choose an authority. |
| Empty GPT | A fully valid mirrored table with no populated entries produces an empty listing with a read-only notice. |

The inspector intentionally retains records from both GPT mirrors for its
report. The archive adapter publishes records from the primary array only after
both copies have passed admission, so the backup does not duplicate partitions
in the listing. The inspector's only permitted MBR findings are the disclosed
512-byte assumption and the fact that an extended chain was not inspected.

All partition start/end products are checked with `BigInt` before conversion to
positional integer offsets. Images must fit the exact JavaScript integer range,
at most `2^53 - 1` bytes. Partition ranges must remain within the actual source.
No invalid or guessed partition range is turned into a raw member.

The direct reader's positional range is wider than the current host profile.
Native F3 and streamed workspace opens retain the existing 8 GiB input-image
ceiling for this increment. Sparse multi-terabyte service tests establish exact
offset handling; they do not qualify native F3 browsing of multi-terabyte image
files. Buffered and browser workflows retain their existing smaller input and
preview limits.

The native archive workspace also retains its existing 8 GiB aggregate member
size allowance. It counts the visible raw partition entries and filesystem
files, including their overlapping content. A disk image below the input-size
ceiling can therefore exceed the workspace's aggregate allowance. Direct
service/F3 browsing and individual extraction have their own operation limits.

The non-owning `diskImageAnalysisSupportsBrowsing` helper uses these same
admission rules with the default 32-partition ceiling. It performs no payload
read. A positive inspection result is not an identity lock: the Archive open
must revalidate and reinspect the source after a UI mode change.

## Which partitions receive filesystem browsing

Payload recognition occurs only for these table types:

| Table | Eligible types |
| --- | --- |
| MBR FAT | `01`, `04`, `06`, `0B`, `0C`, `0E`, and `EF` (FAT variants or EFI system). |
| MBR ext | `83` (Linux filesystem); only the supported ext profile is attempted. |
| GPT FAT | EFI system `C12A7328-F81F-11D2-BA4B-00A0C93EC93B` and Microsoft basic data `EBD0A0A2-B9E5-4433-87C0-68B6B72699C7`. |
| GPT ext | Linux filesystem-data `0FC63DAF-8483-4772-8E79-3D69D8477DE4`. |

An eligible type does not establish its filesystem. The type-specific FAT/ext
probe and complete bounded reader must also succeed. FAT12, FAT16 and FAT32 have the
separate [FAT reader profile](archive-fat-profile.md), including mirror and chain
validation and supported name encodings. Linux ext partitions use the separate
[ext reader profile](archive-ext-profile.md), including allocation and metadata
checksum validation. A Linux type never authorizes interpretation as FAT, and
a FAT type never authorizes interpretation as ext.

Unknown, recovery, extended, dynamic-disk and other non-allowlisted types
are exposed as raw partitions with an explicit notice. Their payloads are not
searched for embedded filesystem signatures. Extended/EBR traversal, Windows
dynamic disks, APFS, NTFS, exFAT and encrypted volumes have no filesystem
interpretation in this adapter. An eligible basic-data partition containing
such a format also remains raw when the FAT probe does not recognize it.

A FAT/ext format error, unsupported profile, or child traversal/entry limit
produces a raw-only partition and a refusal notice. A child is published only
after its complete listing has succeeded. Source errors, revocation, incomplete
reads, changed source identity or length, and cancellation propagate out of
the operation; they are not turned into a successful raw-only listing.

## Bounds and resource ownership

All optional ceilings are positive and can only lower these defaults:

| Resource | Disk-wide ceiling / behavior |
| --- | --- |
| Populated partition records | 32; checked before filesystem payload probes. |
| Composite listing entries | 100,000, including synthetic directories and raw entries. |
| Metadata source bytes requested during open | 64 MiB, shared across inspection, probes and every child volume; each requested read is charged before awaiting I/O. Failed attempts retain their debit. |
| Retained path text | 16 MiB measured as UTF-16 code units × 2, counting both child-relative paths and composite prefixed paths across all children. Each composite path is at most 4096 code units. |
| FAT cluster/ext block visits | 1,048,576 combined across both kinds of attempted child listings. Failed child work consumes the shared allowance. |
| FAT/ext extents created | 100,000 combined across both kinds of attempted child listings, including fixed FAT12/16 root extents. Failed child work consumes the shared allowance. |
| Individual underlying read | At most 64 KiB. There is no full-image materialization. |
| Buffered member read | At most 64 MiB and the caller's smaller allowance, checked before allocation. |
| Streamed member read | At most the supplied allowance, itself no greater than the existing 8 GiB archive streaming ceiling. Returned chunks are at most 64 KiB. |
| Notices | At most 128 notices, each at most 1024 code units, including a final omission count when needed. |

The child FAT reader retains its own stricter local ceilings, including bounded
directory bytes, depth and decoded name work. Its transient FAT page cache and
cross-link set are cleared after a successful listing; immutable member extents
remain for lazy reads. The shared metadata budget and shared traversal budget
prevent multiplying per-child work by the number of partitions.

The returned `ViewerArchive` owns the original source. Success, failed opens,
invalid arguments and cancellation all close that root source exactly once.
Child readers receive bounded slices that do not own the parent. Closing or
rejecting one child cannot close another child's source. Stopping one member
stream stops further scheduled reads from that stream without closing the
archive, so other members can still be previewed.

The adapter checks source length and cancellation at read/loop boundaries and
supports an optional `validateUnchanged` callback before and after underlying
reads and around listing publication. Length alone cannot detect a same-length
replacement; callers with source identity/revision information should provide
their existing validation hook. Event-loop checkpoints let cancellation and
revocation become visible during metadata work. An underlying provider read
already in flight is awaited; the adapter cannot abort a provider that exposes
no cancellation primitive.

## Validation surfaces

`test/archive_disk_image_reader_test.dart` exercises mirrored-table admission,
512/4096-byte geometry, sparse multi-terabyte offsets, deterministic names,
exact member/raw bytes, unsupported table types, damaged mirrors and ranges,
resource sharing, cancellation, source failures and close ownership. Its
`DiskImageFixture` wrapper composes independently supplied sparse byte sources;
it is not tied to the production FAT implementation.

`test/support/archive_fat_web_acceptance.dart` also wraps the independent FatFs
reference corpus in MBR/GPT layouts for the VM and compiled JavaScript
acceptance runs. Qualification receipts state which commands and revisions
passed; these test descriptions alone are not a claim that a particular build
has been qualified.

## Primary format references and licensing

- [UEFI 2.11, GPT disk layout](https://uefi.org/specs/UEFI/2.11/05_GUID_Partition_Table_Format.html): protective MBR, primary/backup placement, usable ranges, table/header CRCs and mirror requirements.
- [UEFI 2.11 specification PDF](https://uefi.org/sites/default/files/resources/UEFI_Spec_Final_2.11.pdf): published specification for the same layout and required validation.
- [Microsoft `CREATE_PARTITION_PARAMETERS`](https://learn.microsoft.com/en-us/windows/win32/api/vds/ns-vds-create_partition_parameters): MBR and GPT partition-type constants, including FAT, EFI and LDM classifications.
- [Microsoft `PARTITION_INFORMATION_GPT`](https://learn.microsoft.com/en-us/windows/win32/api/winioctl/ns-winioctl-partition_information_gpt): EFI/basic-data and other GPT type identifiers.

These references describe the format; no third-party parser implementation was
copied into the adapter. The reader and sparse wrapper carry MIT identifiers.
Existing dependencies retain their own attribution. The external FatFs fixture
generator and source corpus have their separate recorded provenance; no GPL,
AGPL, noncommercial or field-of-use-restricted runtime dependency is added.
