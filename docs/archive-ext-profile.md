# Read-only Linux ext filesystem images

CrispCloud exposes a bounded ext2/ext3/ext4 profile through its existing Archive
listing, F3 preview and extraction interfaces. This is an original MIT Dart
reader with no new runtime dependency. It uses positional reads and validates
the complete visible namespace before returning it.

Open a standalone `.ext`, `.ext2`, `.ext3`, `.ext4` or recognized raw image, or
browse an admitted Linux partition in an MBR/GPT image. Content recognition
also handles a misleading archive suffix without granting write permissions.
The [implementation review](https://github.com/CrispStrobe/CrispCloud/pull/102)
and [qualification records](evidence/storage-ext-20261114) track this increment.
The image stays read-only: there is no mounting, journal replay, undelete,
filesystem repair or filesystem writer.

## Admitted profile

The filename does not select a filesystem implementation or bypass validation.
The reader checks the superblock, revision, feature flags, geometry and all
metadata needed for the published members.

| Area | Supported behavior |
| --- | --- |
| Filesystem revision | Linux original/dynamic ext inode layouts, revision 0 or 1. A clean filesystem state is required. |
| Block/inode geometry | 1024, 2048 or 4096-byte blocks; power-of-two inode records from 128 bytes through one block; 32-byte or 64-byte group descriptors. |
| ext2/ext3 allocation | Direct, single, double and triple indirect block addressing within work and extent limits. Clean internal journals are reserved, not replayed. |
| ext4 allocation | Ordered extent trees through depth 5, bounded physical blocks and exact logical ranges; 64bit block fields and flex_bg metadata placement are admitted. |
| Sparse regular files | Holes and unwritten extents read as zero bytes. Unwritten blocks still receive allocation validation. Extraction creates the correct logical bytes; it does not promise a sparse destination file. |
| Directories and names | Linear directory records, validated self/parent entries, strict UTF-8 components, unique paths, bounded recursion. The compatible `dir_index` capability flag may be present, but an actual indexed-directory inode is refused. |
| Hard links | Multiple regular-file paths may share one validated inode and its immutable allocation map. Extraction emits ordinary file contents; it does not recreate host hard links. |
| Links and special files | Retained as disabled metadata entries in F3. The pane/workspace/extraction index contains regular files and directories only, after validating the complete namespace. Links cannot be previewed/extracted as ordinary files and are never followed. |
| Metadata checksums | CRC32c for the primary superblock, group descriptors, referenced bitmaps/inodes, traversed directory blocks and external extent-tree blocks when `metadata_csum` is present. UUID-derived and explicit `metadata_csum_seed` variants are supported. Legacy `gdt_csum` group descriptors use CRC16. |
| File metadata | POSIX mode and UTC modification timestamps at millisecond precision are exposed. Ownership, ACLs, xattrs and link identity are not restored. |

Allowed compatible features are `has_journal`, `ext_attr`, `resize_inode` and
`dir_index`. Allowed incompatible features are `filetype`, `extents`, `64bit`,
`flex_bg` and `csum_seed`. Allowed read-only-compatible features are
`sparse_super`, `large_file`, `huge_file`, `gdt_csum`, `dir_nlink`,
`extra_isize` and `metadata_csum`. Contradictory combinations still fail.
These are capability flags, not permission to accept every inode layout they
can describe. Unknown flags in any of the three feature sets are refused.

Actual indexed directories, external xattr blocks, external journals,
`needs_recovery`, orphan recovery, `orphan_file`, `meta_bg`, `bigalloc`,
inline data, encryption, case folding, compression, verity, snapshots and
other excluded data features are outside this profile. A clean flag does not
establish that an arbitrary image is consistent; the reader independently
checks the allocations and metadata it uses.

## Partition, viewer and workspace integration

| Source | Behavior |
| --- | --- |
| Standalone recognized ext volume | Files appear directly in the archive namespace. Recognition probes the magic at byte 1080, then the complete reader validates the volume. |
| Primary MBR Linux type `83` | Expose `partition-NNN/raw.img`; add `partition-NNN/files/` only after the ext reader succeeds. |
| GPT Linux filesystem-data type `0FC63DAF-8483-4772-8E79-3D69D8477DE4` | The same raw/file layout after both GPT mirrors pass the existing table/CRC checks. 512-byte and 4096-byte logical sectors remain supported. |
| Other table types | Existing FAT type handling remains; unknown or incompatible types retain raw access. The adapter does not scan arbitrary partitions for ext signatures. |
| Native F3/workspace | Positional viewing and read-only workspace extraction within the existing 8 GiB source/member ceilings. Image input above 64 MiB is not buffered in full. |
| Browser, nested or remote paths | Retain their existing source and buffered limits; this reader adds no physical-device or mounting access. |

The Hex partition inspector's existing **Browse image** action uses the shared
adapter and retains the selected geometry. It revalidates the source and table
when opening. Raw partition bytes and file views overlap, so extracting both
copies that content twice. The workspace counts both against its existing
aggregate content allowance.

Unsupported or corrupt ext children retain the raw partition and a refusal
notice. A partially built filesystem tree is never published. Source-access
failures, short reads, revocation and cancellation fail the whole opening and
preserve the original failure; they cannot become a successful raw-only open.
Reader handles own their sources and close them on failure and final disposal.

Ext files inside DMG/VM containers are not newly interpreted by this increment.
The existing FAT/HFS/UDF/ISO DMG profiles remain separate.

## Resource limits

| Resource | Default ceiling |
| --- | --- |
| Listed entries | 100,000, including directories and special metadata entries. |
| Directory depth | 64. |
| Block groups | 8,192. |
| Metadata requested during listing | 64 MiB. |
| Directory bytes | 32 MiB. |
| Retained complete paths | 16 MiB measured as UTF-16 code units times two; each path is at most 4096 code units. |
| Allocated blocks traversed | 1,048,576, including allocation-tree blocks, internal-journal allocations and resize-inode external index blocks. Fixed group-descriptor metadata is bounded through the metadata/work limits. |
| Created allocation spans | 100,000, accounting for intermediate and retained spans. |
| Traversal checkpoints | 4,194,304; cancellation is checked throughout traversal and streaming. |
| Individual source reads | At most 64 KiB. |
| Positional offsets | Exact within `2^53 - 1`; geometry is checked before multiplication into byte offsets. |
| Buffered member | Existing 64 MiB ceiling, further reduced by the caller's allowance. |
| Streamed member | Existing maximum 8 GiB, further reduced by the caller's allowance. |

Caller-supplied limits can only lower the profile ceilings. Multiple ext
children share traversal allowances. Mixed FAT/ext disks spend one combined
cluster/block and extent allowance; failed child attempts retain their debit.
The disk adapter additionally shares source-byte, entry and path budgets.

Allocation validation rejects references to free blocks/inodes, out-of-range
metadata, repeated/cross-linked blocks, cycles, overlapping metadata, invalid
record lengths, conflicting file types and unsafe names. Payload reads follow
the immutable allocation decisions made while opening. No full-filesystem
consistency, payload checksum or image authenticity claim follows from these
checks. Unreferenced data, historical journal contents and extended attributes
are not independently verified.

## Qualification and provenance

The new corpus is independently mastered by external e2fsprogs 1.47.2 tools.
Five complete images cover ext2 at 1 KiB, clean ext3 at 2 KiB, modern ext4 at
4 KiB with an explicit checksum seed, and ext4 at 1 KiB with a UUID-derived
seed, plus a legacy CRC16 group-checksum ext4 image. The corpus contains 48
regular file payloads across images, Unicode,
hard links, nested/empty entries, indirect addressing, a non-root extent tree,
sparse/unwritten ranges and 15 special entries. `e2fsck -fn` and `debugfs`
provide external consistency and extraction controls. Fixed inputs reproduce
the generated Dart data and manifest exactly.

See the [fixture manifest](../test/fixtures/archives/ext-reference-manifest.json),
[generator](../test/support/generate_ext_reference.py),
[portable acceptance](../test/support/archive_ext_web_acceptance.dart) and
[continuation evidence](evidence/storage-ext-20261114). External tools are used
only to construct and verify test inputs; they are not shipped, linked or
invoked by the app. The new runtime code is original MIT, and the application's
existing license remains unchanged.

On-disk facts were checked against the Linux kernel's ext4 documentation:
[superblock](https://docs.kernel.org/filesystems/ext4/super.html),
[group descriptors](https://docs.kernel.org/filesystems/ext4/group_descr.html),
[inodes](https://docs.kernel.org/filesystems/ext4/inodes.html),
[block and extent mapping](https://docs.kernel.org/filesystems/ext4/ifork.html),
[directories](https://docs.kernel.org/filesystems/ext4/directory.html) and
[checksums](https://docs.kernel.org/filesystems/ext4/checksums.html).
Specification text and filesystem implementation sources are not incorporated.
