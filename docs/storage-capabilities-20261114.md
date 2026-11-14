# Storage capability expansion: archive, container and filesystem workbench

Status: source-backed architecture and library assessment. This branch changes
documentation and evidence only; recommended capabilities require implementation
and qualification before they can be advertised in the app.

## Reconciled baseline

On 2026-11-14 all remote branch heads, tags and `refs/pull/*/head` were fetched.
All **10 existing branch heads** and **90 historical pull-request heads** are
ancestors of `4d65b86dab36ca8f5dcd192c776de369aa5a4932`. There were no open PRs.
No additional merge or recovery of divergent content was necessary.

The previous handoff's merge, `81639c44da5c9c905e5bcbe8d04308fce7bda17a`, is
seven commits behind this baseline. Those commits include viewer long-line
handling, newer canonical Office sources, reader cleanup and release evidence.
They are retained intact.

The working branch is
[`integration/storage-capabilities-20261114`](https://github.com/CrispStrobe/CrispCloud/tree/integration/storage-capabilities-20261114).
Checkpoints are pushed as the assessment develops. Existing branches remain.
The complete source refs and ancestry outcomes are in
[`evidence/storage-capabilities-20261114/ancestry.json`](evidence/storage-capabilities-20261114/ancestry.json).

## Scope and license filter

Evaluate additions for archive inspection/recovery, filesystem and partition
browsing, disk/container formats, structured hex tools and robust copying.
The requested filter accepts MIT, Apache-2.0, BSD, MPL and comparable terms;
excludes GPL and noncommercial restrictions. This assessment also excludes
LGPL-backed additions unless the user changes that constraint explicitly.
Licenses apply to the selected implementation and its runtime dependencies,
not merely its wrapper. A permissive wrapper around a GPL/LGPL engine is not
an accepted implementation.

This is an addition policy, not a relicensing of CrispCloud. The repository's
existing `LICENSE.txt` is GNU AGPL v3; individual existing packages have their
own license and attribution records.

## Recommendation

Extend the existing byte-source, archive and operation contracts into a disk
and filesystem workbench. The first useful additions are **LZFSE DMG reading,
bounded UDF reading, ZIP salvage to a new file, and a GPT/MBR inspector linked
to the current hex view**. Follow with read-only filesystem adapters and
recovery tools. These close identifiable gaps without replacing working archive
or transfer engines.

Use a small C/Rust bridge where it has a concrete advantage. Evaluate a
DiscUtils helper or a deliberate UDF port for optical/VM coverage. Avoid
automatically introducing C, Rust, Go and .NET runtimes together: several
candidates are alternatives, and many of their headline features already ship.
OCI image browsing can start with existing TAR and JSON facilities; a Go
containerregistry helper becomes useful when registry interoperability is a
separate product goal.

### Existing capabilities to preserve

The following findings come from the source at the reconciled baseline, not
from assumptions about a generic file manager.

| Area | Already present | Useful increment |
| --- | --- | --- |
| Archive formats | ZIP/7z/TAR/RAR/ISO/DMG, package readers and many codecs, with distinct read/create/edit profiles | LZFSE blocks, UDF-only images, ZIP salvage, VM and OCI semantics |
| Archive operations | Shared queue, batch testing/extraction, streamed eligible native workspaces, inspected writers and staged publication | New adapters and recovery operation types in the same queue |
| Hex editing | MIT editor with virtualized rows, nibble input, search, selection, insertion, undo and verified save | Typed data interpretation, structural drill-down, binary diff and patch export |
| Hex viewing | Native F3 already uses lazy byte windows | Version-bound remote and nested-container ranges |
| Binary structures | Apache-2.0 parser for bounded PNG/Wasm/ELF/PE/Mach-O/ZIP/Java headers | Lazy partition/filesystem metadata and validation findings connected to byte selections |
| Copy and recovery | Durable entry journals, path claims, verified-prefix recovery and staged verification | Aggregate bandwidth allocation, damaged-media extent maps and completion of latent delta paths |
| Native copy efficiency | CoW cloning, genuine preallocation and platform metadata facilities | Profile-specific sparse/extent handling and independent qualification |

Evidence: [format coverage](archive-format-coverage.md),
[archive gap register](file-manager-gaps/03-archives-and-containers.md),
[hex integration](hex-editor-integration.md),
[binary parser](../lib/services/binary_structure_service.dart),
[transfer queue](transfer-queue.md),
[transfer recovery](../lib/services/transfer_recovery_service.dart), and
[native copy primitives](../lib/services/native_copy_primitives_io.dart).
Those documents contain historical verification claims with their own pins;
this assessment does not rerun or extend those claims.

## Candidate libraries

License descriptions below apply to the identified source component. They are
not approval of every optional dependency, bundled executable, example,
database, build script or precompiled distribution. Exact reviewed source
revisions and build graphs must be selected before integration.

### Archives and compression

| Candidate | License and primary evidence | Role in CrispCloud | Material boundary |
| --- | --- | --- | --- |
| Apple lzfse | [BSD-3-Clause](https://github.com/lzfse/lzfse/blob/master/LICENSE); [project](https://github.com/lzfse/lzfse) | Decode missing LZFSE/LZVN blocks behind the current DMG reader | Codec only: no DMG encryption, APFS or partition parsing. Native C and browser implementations need separate qualification. |
| minizip-ng | [zlib](https://github.com/zlib-ng/minizip-ng/blob/develop/LICENSE); [features and options](https://github.com/zlib-ng/minizip-ng) | Recover a damaged/missing ZIP central directory into a fresh verified output; investigate split-ZIP profiles | Directory recovery cannot restore missing payload bytes. Disable automatic dependency fetching; explicitly choose codecs, crypto and character conversion. |
| libarchive | [Mostly BSD-2-Clause, with documented exceptions](https://github.com/libarchive/libarchive/blob/master/COPYING); [formats](https://github.com/libarchive/libarchive/wiki/LibarchiveFormats) | Optional uncommon-format backend or independent verification oracle | Much of its coverage is already present. It is a streaming reader/writer, not an in-place editor or replacement for current encrypted 7z/RAR handling. |
| libzip | [BSD-3-Clause](https://libzip.org/license/); [API](https://libzip.org/documentation/libzip/) | Alternative transactional ZIP backend if a concrete gap warrants it | Existing ZIP editing and publication already cover the core use case. Do not add a second editing engine merely for its format list. |
| liblzma / LZMA SDK | [liblzma 0BSD](https://github.com/tukaani-project/xz/blob/master/COPYING); [SDK public domain](https://www.7-zip.org/sdk.html) | Selected codec implementation or native acceleration if needed | Existing XZ/LZMA coverage already ships. liblzma is not the whole XZ source tree; the SDK is not the whole 7-Zip distribution. |

For libarchive, keep the GPL LZO dependency disabled and constrain external
filter execution; its format documentation describes fallbacks to installed
programs. Its COPYING file distinguishes source-file licenses from varying
build-script licenses. Select the Apache-2.0 or CC0 grant where the BLAKE2
sources offer alternatives. Preserve per-file attribution.

For minizip-ng, the upstream build exposes MZ_ICONV, crypto backends and
MZ_FETCH_LIBS. A zlib top-level license does not establish the license of the
chosen iconv implementation or every fetched library. Configure a reproducible,
explicit build; do not import the default dependency graph without checking it.

### Partition, filesystem and disk-image engines

| Candidate | License and primary evidence | Useful capability | Limits and integration cost |
| --- | --- | --- | --- |
| gptman + mbrman | MIT OR Apache-2.0; [gptman](https://github.com/rust-disk-partition-management/gptman), [mbrman](https://github.com/rust-disk-partition-management/mbrman) | Parse, inspect and selectively write GPT/MBR partition tables | A table editor does not relocate file contents or resize a filesystem. Image-only inspection is the initial scope. |
| rust-fatfs | [MIT](https://github.com/rafalh/rust-fatfs/blob/master/LICENSE.txt); [features](https://github.com/rafalh/rust-fatfs) | FAT12/16/32, long names, file/directory operations and formatting | Not exFAT. Start read-only; FAT image creation/editing can be a separately qualified writer profile. |
| ChaN FatFs | [BSD-style terms in the official application note](https://elm-chan.org/fsw/ff/doc/appnote.html) | Portable C FAT/exFAT with block callbacks and a configurable read-only build | Separate from rust-fatfs. Upstream also discusses exFAT patent rights; the code license is not a blanket conclusion on those rights. |
| ext4-view | MIT OR Apache-2.0; [source and licenses](https://github.com/nicholasbishop/ext4-view-rs) | Read-only ext2/ext3/ext4 access through a supplied reader | Useful for browsing/extraction. Unsupported incompatibility features and corruption must be distinct outcomes. No repair/write claim. |
| ColinFinck/ntfs | MIT OR Apache-2.0; [features and exclusions](https://github.com/ColinFinck/ntfs) | Read-only NTFS metadata, directory traversal, attributes, sparse data and alternate streams | Upstream excludes writes, compression, encryption, journaling, reparse points and security descriptors. Do not silently flatten unsupported cases. |
| DiscUtils | [MIT](https://github.com/DiscUtils/DiscUtils/blob/develop/LICENSE.txt); [scope](https://github.com/DiscUtils/DiscUtils) | UDF/ISO/FAT/NTFS and VM containers such as VHD/VHDX/VDI/VMDK/XVA | C#/.NET helper or reviewed port, not a Dart package. Select modules; verify read/create/edit separately for every format. |
| go-diskfs | [MIT](https://github.com/diskfs/go-diskfs/blob/master/LICENSE); [current API](https://github.com/diskfs/go-diskfs) | MBR/GPT, FAT, ISO9660, SquashFS, ext4 and a limited read-only EROFS profile | Go helper alternative. ISO/SquashFS creation uses finalization, not arbitrary editing afterward. No QCOW support merely because it appears on a roadmap. |
| go-apfs | [Apache-2.0](https://github.com/blacktop/go-apfs/blob/main/LICENSE); [project](https://github.com/blacktop/go-apfs) | Experimental APFS listing and extraction | Research only: upstream labels it WIP. Current go.mod includes lzfse-cgo; do not assume a pure-Go/Wasm build or encrypted APFS support. |

The smaller Rust components give a controlled native scope and can reuse the
repository's Rust dependency review patterns. DiscUtils is the strongest broad
candidate when UDF and VM disk formats justify a desktop helper. go-diskfs is
an alternative when a Go image service is preferred. The recommendation is to
choose against fixture coverage and packaging cost, rather than adopt all three.

An initial browser implementation should expose only parsers that actually
compile and pass browser tests. A Rust or C library being theoretically
compilable to Wasm does not establish its I/O, memory, thread or integer behavior
in the browser. None of these libraries grants browser access to physical disks.

### OCI and Docker containers

[google/go-containerregistry](https://github.com/google/go-containerregistry)
is [Apache-2.0](https://github.com/google/go-containerregistry/blob/main/LICENSE).
It offers image manifests, indexes, layers, registries, tarballs, layouts and
mutation/export APIs. This is a useful independent meaning of “container” in
addition to disk images and archives.

A user-facing OCI browser should show both individual layers and a merged file
tree, including the layer that supplied each visible file. Implement whiteout
deletions and opaque-directory semantics; a list of TAR members does not
represent the final root filesystem. Check descriptor sizes and digests, bound
layer expansion, and never execute image entrypoints. Treat links and special
files as metadata unless the extraction policy explicitly supports them.

Existing TAR readers make a smaller offline Dart implementation plausible.
The Go library is a candidate backend or reference oracle; registry credentials,
remote writes and network access should be separate capabilities.

### Hex, identification, copy and backup

| Candidate | License and primary evidence | Best use | Boundary |
| --- | --- | --- | --- |
| binrw | [MIT](https://github.com/jam1garner/binrw) | Declarative Rust binary structures, attached to existing hex ranges | Layout parsing/writing alone is not semantic repair. |
| file/libmagic | [BSD-style two-clause terms](https://github.com/file/file/blob/master/COPYING) | Content-based type hints for misnamed files and recovered fragments | Inspect selected magic database and dependencies. Identification is not validity or integrity verification. |
| BLAKE3 | [Apache-2.0 option](https://github.com/BLAKE3-team/BLAKE3/blob/master/LICENSE_A2) | Strong extent hashes, diff caches and optional fast verification | Preserve SHA-256 compatibility in existing journals; benchmark before changing algorithms. |
| xxHash library | [BSD-2-Clause](https://github.com/Cyan4973/xxHash/blob/dev/LICENSE) | Fast candidate filtering before strong comparison | Noncryptographic. Its [CLI has GPL terms](https://github.com/Cyan4973/xxHash/blob/dev/cli/COPYING), so select only the intended library. |
| rclone | [MIT](https://github.com/rclone/rclone/blob/master/COPYING); [RC API](https://rclone.org/rc/) | Optional native provider bridge and supported server-side operations | Keep CrispCloud's durable journal authoritative. rclone does not supply universal partial-file resumption or binary deltas. |
| Xdelta 3, Apache branch | [Current upstream licensing](https://github.com/jmacd/xdelta) | VCDIFF patch export/application for large images | Choose the Apache source branch, not xdelta-gpl or historic releases. Bind base and result hashes and apply to staging. |
| openrsync | [ISC](https://github.com/kristapsdz/openrsync/blob/master/LICENSE.md); [scope](https://github.com/kristapsdz/openrsync) | Optional Unix/SSH delta transfer | Protocol 27 and a subset of rsync behavior; not a universal Flutter or Windows backend. |
| restic / Kopia | [restic BSD-2-Clause](https://github.com/restic/restic/blob/master/LICENSE), [Kopia Apache-2.0](https://github.com/kopia/kopia/blob/master/LICENSE) | A future versioned, deduplicated backup product feature | Backup repositories, retention and restore are separate semantics from ordinary copy/move. Choose one after a restore requirement is defined. |

Deeper executable inspection could optionally use
[goblin (MIT)](https://github.com/m4b/goblin) and
[Capstone (BSD core, plus bundled notices)](https://github.com/capstone-engine/capstone).
These are secondary to disk and container structures for this request.

rclone's [FAQ](https://rclone.org/faq/) describes its partial-transfer limitation.
Its [check command](https://rclone.org/commands/rclone_check/) can perform
downloaded-content comparison when selected; ordinary backend checksum options
do not imply a strong end-to-end digest on every provider. Report the actual
verification mode. RC process jobs must not replace restart-safe app records.

## Recovery and repair are separate operations

The useful distinctions are: diagnose metadata, salvage valid archive members,
carve content from raw bytes, recover deleted files from surviving filesystem
metadata, image damaged media, and modify filesystem metadata. One successful
parser or checksum check does not implement all of these.

[sleuthkit/scalpel](https://github.com/sleuthkit/scalpel) is a real Apache-2.0
carving candidate with a library API. Its own README says maintenance stopped
after integration encountered memory leaks and that official releases are not
being produced. Its stock Windows package includes LGPL pthreads and TRE
dependencies. Evaluate only an audited source subset with suitable dependencies
and resource limits; do not approve the distribution as-is. The different
Scalpel3 project is GPL and is excluded.

An original bounded carver for a small set of formats may be easier to maintain.
Begin with validated JPEG/PNG/PDF/ZIP-family candidates, chunk-boundary-safe
signature detection and format-aware end/length validation. Export to another
destination with source offsets, ranges, hashes and validation findings.
Mark missing or unreadable ranges explicitly. A magic/footer match by itself
must not produce a “fully recovered” result.

Carving does not normally reconstruct original names, directories or arbitrary
fragmentation. FAT deleted-entry recovery and NTFS MFT-based recovery are
separate future profiles that need metadata-specific implementations. The
read-only filesystem libraries above are not advertised as undelete engines.

For damaged-media imaging, use a durable extent map recording unattempted,
read, failed, retried and intentionally skipped regions. Keep offsets stable
and let users retry selected failures without rereading everything. A hole or
zero-filled failed sector must remain distinguishable from a successfully read
zero sector. No complete, maintained permissive replacement for GNU ddrescue's
whole workflow was established in this study.

## Exclusions and license traps

| Candidate | Why it does not meet the selected policy |
| --- | --- |
| PhotoRec / TestDisk | [GPL v2 or later](https://www.cgsecurity.org/wiki/TestDisk). Workflow inspiration, not an approved embedded engine. |
| GParted / GNU Parted | GPL tools; a permissive partition-table parser is a different scope from filesystem resizing. |
| ImHex / PatternLanguage | [ImHex GPL](https://github.com/WerWolv/ImHex); [PatternLanguage LGPL](https://github.com/WerWolv/PatternLanguage). An MIT grammar is not the execution engine. |
| GNU rsync / ddrescue | [rsync GPL](https://rsync.samba.org/GPL.html), [ddrescue GPL](https://www.gnu.org/software/ddrescue/). An external wrapper does not change this product dependency policy. |
| bit7z plus ordinary 7-Zip backend | [bit7z MPL wrapper](https://github.com/rikyoz/bit7z) still requires a [7-Zip backend with LGPL/unRAR terms](https://www.7-zip.org/license.txt). |
| lwext4 default/full build | [Upstream](https://github.com/gkostka/lwext4) documents GPL extents and xattr source within otherwise BSD code. Do not describe the whole library as BSD. |
| libfsapfs and libudfread | LGPL implementations, excluded by the conservative policy used here. |
| Kaitai as an undifferentiated package | [Compiler/visualizer GPL, runtimes separately licensed](https://kaitai.io/). Use existing Dart parsing or binrw under the current strict scope; revisit build-time compiler use only as a distinct decision. |

Existing app licensing is a separate question from new dependencies.
[The current audit](fuse_and_license_audit.md) records AGPL app licensing,
LGPL libfuse headers and libsmb2 notices, and an optional separately installed
FUSE-T path gated on noncommercial use. The FUSE runtimes are not bundled by
that build script. This study does not establish that the existing application
is GPL/LGPL/NC-free and does not silently change those profiles.
