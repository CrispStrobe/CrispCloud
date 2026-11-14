# Read-only NTFS filesystem images

CrispCloud exposes a bounded NTFS profile through Archive listing, F3 preview,
read-only workspaces and extraction. The reader is original MIT Dart and adds
no runtime dependency. Open a standalone `.ntfs` volume, a recognized raw image,
or an admitted Windows data partition in an MBR/GPT image.

The implementation is tracked in
[PR #103](https://github.com/CrispStrobe/CrispCloud/pull/103), stacked on the
ext continuation. [Qualification records](evidence/storage-ntfs-20261114)
state the actual tested revisions and distinguish preliminary checks from
final results. This reader does not mount images, open physical devices,
write filesystems, replay journals, repair allocations or recover deleted files.

## Admitted profile

Recognition checks the eight-byte NTFS OEM field at byte three. A recognized
NTFS volume owns both buffered and native streamed dispatch even under a
misleading `.zip`, `.7z`, `.iso` or other archive suffix. Corruption after that
recognition is not converted into another format attempt. The native viewer's
11-byte signature hint preserves the same choice and streaming allowance.

| Area | Behavior |
| --- | --- |
| Filesystem version | NTFS 3.0 or 3.1 with a clean volume-information flag field. The independently mastered corpus covers 3.1; no authentic external 3.0 image is claimed. |
| Geometry | Power-of-two logical sectors from 512 through 4096 bytes, ordinary power-of-two clusters through 64 KiB, and FILE/index records from 512 bytes through 64 KiB. All products must fit exact positional integers. |
| Boot metadata | Validate the NTFS geometry and require the complete primary/backup logical boot sectors to agree, including the bytes beyond the first 512 on larger-sector volumes. The declared volume bounds determine the backup position; trailing source padding is permitted. |
| FILE and INDX records | Validate signatures, record bounds and every update-sequence fixup using the fixed 512-byte stride, including on 4096-byte-sector images. |
| Master file table | Validate the bootstrap record against its own data mapping, referenced MFT allocation bits, record identities and sequence numbers, and the admitted MFT mirror prefix. Extension records and attribute lists are refused. |
| Ordinary data | Resident data and uncompressed nonresident mappings with ordered logical ranges and signed physical offsets. Every referenced physical allocation is checked before publishing the listing. |
| Sparse and initialized data | Holes and bytes beyond valid initialized data read as zero. Extraction emits correct logical bytes; it does not promise sparse destination allocation. |
| Directory indexes | Resident `$I30` roots and bounded nonresident INDX trees with index-allocation bitmaps, unique live child blocks, parent/sequence references and matching FILE-name attributes. Cycles, missing live blocks and conflicting namespace records are refused. |
| Names and hard links | Strict UTF-16, including valid surrogate pairs; relative safe path components. Primary filename paths are retained. DOS aliases must have a primary indexed name and are not emitted as duplicate files. Regular hard links share validated record data; extraction creates ordinary file copies. |
| Alternate DATA streams | Exact original names, owning paths and logical sizes appear in bounded metadata notices. They are not flattened into ordinary file bytes or fabricated colon-containing member paths. |
| System metadata | Reserved system records and `$Extend` descendants are omitted from selectable files with an explicit notice. Required system record kinds/root links and their reachable mappings remain validated so omission cannot conceal referenced metadata allocations. |
| File times | Modified timestamps are exposed in UTC at millisecond precision, without forming an inexact 64-bit FILETIME value in JavaScript. ACLs, ownership, security descriptors, DOS aliases and host hard-link identity are not restored. |

Alternate-stream content is outside preview, integrity payload checking and
extraction in this profile. Resident stream bytes necessarily occur within
their containing FILE metadata record; nonresident stream payloads are not
fetched merely to list them. Their storage mappings still receive allocation
validation. Integrity reports retain the stream notices so an ordinary-file
pass does not imply verification of alternate-stream content.

The profile explicitly refuses attribute-list/extension-record layouts,
compressed or encrypted attributes/files, reparse points, logged utility
streams, property sets, unknown FILE/attribute flags and other unsupported
metadata forms. Volumes with dirty or maintenance-required flags are refused.
The default all-hole system `$BadClus:$Bad` mapping is admitted; actual declared
bad-cluster allocations are outside this first profile. A clean flag alone
does not establish consistency: the reader validates the metadata and
allocations that its published namespace depends on.

Directory checks establish the bounded rooted structure and filename identities;
they do not verify Windows collation order or the semantic contents of `$UpCase`.

## Partition and application integration

| Source | Result |
| --- | --- |
| Standalone recognized NTFS | Regular files and directories appear directly in the archive namespace. System metadata is omitted and alternate streams remain notices. |
| Primary MBR type `07` | Preserve `partition-NNN/raw.img`; add `partition-NNN/files/` only after the NTFS reader succeeds. The type alone does not establish NTFS or enable exFAT. |
| GPT Microsoft Basic Data `EBD0A0A2-B9E5-4433-87C0-68B6B72699C7` | Admit an NTFS probe before the existing FAT probe. A recognized NTFS failure cannot fall through to FAT. Both GPT mirrors must satisfy the existing table/CRC profile. |
| EFI, Linux or unknown partition types | Retain their existing type-specific behavior. They do not gain NTFS scanning merely because a payload contains its signature. |
| Native F3 and workspace | Positional reads retain the existing 8 GiB input and streamed-member ceilings. A large image is not buffered in full. |
| Buffered, browser, remote or nested paths | Retain their existing separate source and buffered limits. This increment adds no physical-device capability or new ext/NTFS interpretation inside DMG/VM containers. |

The existing **Hex → Inspect partitions → Browse image** action uses this shared
adapter and revalidates the image/table after the mode change. The independent
512/4096-byte GPT wrapper tests vary partition-table sector units; those units
do not automatically change the contained NTFS filesystem's own sector size.

Unsupported or corrupt filesystem children retain raw partition access and an
explicit refusal notice; partial filesystem trees are never published. Source
failures, short reads, revocation and cancellation fail the whole opening and
retain the original failure. Raw and filesystem views overlap, so extracting
both copies content twice and counts both toward the existing workspace or
operation aggregate allowance.

## Resource limits

Caller limits can only lower the fixed profile ceilings. Large regular members
remain listed as metadata; the relevant buffered/streamed read checks its
allowance before fetching payload bytes. The workspace's separate aggregate
content limit still applies when opening a whole workspace.

| Resource | Default ceiling |
| --- | --- |
| Published members | 100,000 by default, lowerable through the caller's entry allowance. |
| Scanned filename-index entries | Fixed 200,064 per reader, including system entries and DOS aliases; this separate traversal ceiling is not lowered by the public member allowance. |
| Directory depth | 64. |
| Metadata source bytes requested | 64 MiB. |
| Directory metadata bytes | 32 MiB. |
| Retained paths and alternate-stream notices | 16 MiB measured as UTF-16 code units × 2; each published full path is at most 4096 code units. |
| Allocated clusters traversed | 1,048,576, including referenced system metadata and named-stream allocations. |
| Mapping extents created | 100,000, including sparse mappings. |
| Traversal/read checkpoints | 4,194,304 per reader, with cancellation checks and event-loop yields. |
| Individual source read | At most 64 KiB. |
| Buffered member | At most 64 MiB and the caller's smaller allowance. |
| Streamed member | At most 8 GiB and the caller's smaller allowance. |
| Positional arithmetic | Exact through `2^53 - 1`; this does not raise native image-size limits. |

FAT, ext and NTFS children share one disk-wide cluster/block and extent
allowance, including failed attempts. Metadata source bytes, entry counts and
retained composite paths also use the existing shared disk budgets. Exact
NTFS child notices are retained within the disk's 128-notice allowance, with
8192 code units per exact notice; exhaustion is refused instead of silently
shortening or omitting an alternate-stream name. Other filesystem notices
retain their existing bounded omission reporting.

The reader copies borrowed source buffers, captures source length, validates
mapping ranges before retaining them, and follows immutable mappings for
payload reads. Its owned source closes once on failure or disposal. Same-length
source replacement still needs the caller's existing identity/revision checks;
format validation does not establish image authenticity or payload integrity.
Unreferenced FILE records, historical journals and unused space are not fully
checked by this browsing profile.

## Independent qualification inputs

The test-only producer uses externally supplied ntfs-3g 2022.10.3 tools and an
original small fixture helper. It creates complete images without raw
filesystem-byte patches. Fixed clocks, serials, inputs and tool/compiler hashes
make the images, generated Dart data and JSON manifest reproducible.

| Fixture | Size | Sector / cluster / FILE record | Unnamed file paths | Expected reader outcome |
| --- | --- | --- | --- | --- |
| `ntfs31` | 16 MiB | 512 / 4096 / 1024 bytes | 61 | Supported |
| `ntfs31-small` | 16 MiB | 512 / 512 / 1024 bytes | 61 | Supported |
| `ntfs31-4k` | 32 MiB | 4096 / 4096 / 4096 bytes | 21 | Supported |
| `ntfs31-4k-attrlist` | 32 MiB | 4096 / 4096 / 4096 bytes | 61 | Authentic unsupported attribute-list control |

The three positive images contain **143 regular unnamed path instances**.
Across all four images, independent `ntfscat` extraction verifies 204 unnamed
path instances and eight named streams. Hard-link paths count as separate path
instances, not unique payloads. Read-only `ntfsfix -n`,
`ntfsresize --info --no-action`, recursive `ntfsls` and `ntfsinfo` checks preserve
the source-image hashes. The unsupported image is not counted as successful
application extraction.

The external `ntfsinfo` inspection of `$Secure` reports a `$SDS` diagnostic even
with a zero exit status; security-descriptor content inspection is therefore
incomplete. The same diagnostic occurs on an untouched `mkntfs` control, and
`ntfscat` can read matching `$SDS` bytes from the control and populated image.
The preserved receipts distinguish these observations from the successful
read-only volume checks and user-payload comparisons. Neither the external
checks nor this reader claim filesystem-wide consistency or ACL validation.

The corpus includes real sparse and fragmented mappings, nested/empty
directories, Unicode and supplementary-plane filenames, hard links, resident
and nonresident indexes, and both resident/nonresident alternate streams.
`hello.txt` has named streams `notes-雪` (34 bytes) and `binary-😀` (16,387 bytes).
Partition wrappers, very large offsets and malformed mutations remain
explicitly derived/synthetic controls. The largest complete external image is
32 MiB; native UI checks use padded 80 MiB inputs.

See the [manifest](../test/fixtures/archives/ntfs-reference-manifest.json),
[generator](../test/support/generate_ntfs_reference.py),
[portable acceptance](../test/support/archive_ntfs_web_acceptance.dart) and
[qualification records](evidence/storage-ntfs-20261114). External tools and
libraries are used only for test production/verification. Their implementation
code is not imported, linked, shipped or invoked by the app.

Primary on-disk references include Microsoft's
[FILE record header](https://learn.microsoft.com/en-us/windows/win32/devnotes/file-record-segment-header),
[attribute record header](https://learn.microsoft.com/en-us/windows/win32/devnotes/attribute-record-header),
[multisector fixups](https://learn.microsoft.com/en-us/windows/win32/devnotes/multi-sector-header),
[attribute types](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-fscc/a82e9105-2405-4e37-b2c3-28c773902d85)
and [file streams](https://learn.microsoft.com/en-us/windows/win32/fileio/file-streams).
These supply format facts; specification text and third-party parser source
are not incorporated into the original MIT reader.
