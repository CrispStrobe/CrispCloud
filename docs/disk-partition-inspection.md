# Read-only GPT and MBR inspection

Open a disk-image file in **F3 → Hex**, then choose **Inspect partitions**.
The report reads partition metadata through the viewer's existing positional
source. Expand a metadata group and select a field to return to Hex with the
field's exact bytes highlighted, including backup headers beyond the old
64 KiB binary-header prefix.

When the table satisfies the [disk-image browsing profile](archive-disk-image-profile.md),
**Browse image** opens its raw partitions and eligible FAT files in Archive
mode. The action retains the selected 512/4096-byte geometry, validates the
source again, and reinspects the table before publishing a listing. Switching
between Hex and Archive retains that choice for the same captured source;
reloading or replacing the source discards it. Damaged or ambiguous tables do
not receive the browse action.

The inspector is an original Dart implementation with an MIT notice in
[`disk_partition_inspector.dart`](../lib/services/disk_partition_inspector.dart).
It reuses the existing Apache-licensed binary field model. It imports no
partition-editor, recovery, filesystem, native, or executable dependency.

## Supported profiles

| Area | Behavior |
| --- | --- |
| Legacy MBR | Inspect the four primary records, types, starting LBA and length; report out-of-range and overlapping partitions. Extended containers are identified with an explicit notice that their EBR chains and logical partitions were not inspected. |
| GPT | Inspect revision 1.0 primary and physical-tail backup headers and their bounded entry arrays. Show GUIDs, names, attributes, geometry and exact metadata byte ranges. |
| Integrity | Calculate each header CRC32 and each entry-array CRC32 independently. Compare mirror geometry and array bytes. Report missing headers, unsupported revisions, reserved-field errors, duplicate GUIDs, out-of-range/overlapping spans and unsafe metadata placement. |
| Sector geometry | Automatically probe 512-byte and 4096-byte GPT layouts. Conflicting signatures require an explicit choice. MBR alone does not encode logical sector size; automatic MBR inspection assumes 512 and explains that assumption. The report offers an explicit 512/4096 override and reinspection. |
| Inconsistent copies | Keep primary and backup findings separate. Neither a matching CRC nor an available backup makes a table authoritative. A legacy MBR alongside an orphaned backup GPT is reported as potentially stale. |

CRC labels say **Matches**, **Does not match** or **Not checked** for the
specific header or array. The report does not collapse them into a whole-disk
validity result. A missing, unsupported or refused table remains unchecked.
Selecting a sector size changes only the interpretation; it does not modify
the input file.

## Bounded reading and lifecycle

- Each positional request is at most **64 KiB**. Each GPT array is limited to
  **1 MiB and 4,096 entries**. Total requested metadata is capped at
  **2 MiB + 16 KiB**, independent of image size.
- Automatic detection reads the MBR sector and fixed **8-byte signature
  probes**. A probe can coincide with ordinary data in a non-GPT image. Full
  header sectors are read only for recognized, selected candidates; safe
  declared entry arrays follow. The inspector does not scan filesystems or
  partition contents.
- Disk LBAs remain exact `BigInt` values until checked against the available
  image. A range must fit the source and JavaScript's exact integer range before
  it becomes a positional read or a selectable field.
- Overlap checks sort intervals. Findings are capped at **256**, including an
  explicit omission notice. Large entry groups build their field widgets only
  when expanded.
- Snapshot validation brackets inspection. The reader yields between bounded
  reads and during large table parsing so mode changes, viewer closure and
  source replacement can cancel it. The host checks the source again before
  applying a selection. The inspector never closes or replaces the viewer's
  source.

The byte totals describe requests made by the inspector. The native viewer may
cache its existing 256 KiB window, and web/remote inputs retain their existing
materialization and size policies. This feature does not create a new raw-device
permission or promise lazy network reads on every provider.

## Boundaries

The inspector itself reads table metadata. The separate image adapter now
browses supported FAT volumes; its listing is not an inference from a matching
table CRC. Neither feature traverses EBR chains, interprets ext/NTFS/APFS,
mounts partitions, recovers deleted files,
repair a CRC or rewrite a partition table. Structured writes require a separate
reviewed plan, backup and staged verification path. Existing Hex editing remains
a separate explicit workflow.

Recognized metadata can be damaged or contradictory. Header and array fields
are evidence from the available bytes; they do not authenticate a publisher or
establish that a filesystem is usable. Unsupported revisions and arrays above
the limits remain visible as findings rather than being treated as verified.

## Source references and qualification

The layout and checks follow
[UEFI 2.11, chapter 5](https://uefi.org/specs/UEFI/2.11/05_GUID_Partition_Table_Format.html).
The MBR extended-container identifiers are cross-checked against
[Microsoft's partition type definitions](https://learn.microsoft.com/en-us/windows/win32/api/vds/ns-vds-create_partition_parameters)
and [Red Hat's partition documentation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/managing_storage_devices/disk-partitions_managing-storage-devices).
These are format references; no implementation from a partition/recovery tool
was copied into the service.

`test/support/disk_partition_fixture.dart` independently constructs sparse
512/4096-byte-sector images and calculates fixture CRCs. Tests cover damaged
mirrors, huge unsigned LBAs, metadata caps, unsafe ranges, source changes,
cancellation and a synthetic **5 TiB** image. The sparse case exercises positional
access and large offsets; it is not a physical 5 TiB disk scan.

The SDK-only `test/support/disk_partition_web_acceptance.dart` runs the actual
service on Dart VM and compiled JavaScript. Viewer tests exercise exact Hex
highlighting, separate primary/backup CRC labels, sector-size reinspection,
cancellation, narrow layouts and translated controls. Executed commands,
source hashes and results are recorded in
[`evidence/storage-runtime-20261114`](evidence/storage-runtime-20261114).
The later Browse-image integration and FAT qualification have their own
[`storage-fat-20261114`](evidence/storage-fat-20261114) evidence.
Test source alone is not a validation result.
