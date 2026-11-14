# Archive and disk-image coverage

CrispCloud shares one format registry between pane navigation, F3, archive
search and extraction. A filename offers a reader; the reader validates the
actual container. Content signatures take priority over misleading suffixes.
Readable formats do not automatically acquire a writer.

## Capabilities

**Create** makes a separate verified output from selected local files. **Edit**
means a staged member change followed by whole-container repacking, independent
verification and the existing reviewed publication/recovery workflow. A format
family can have a writer while an individual file remains read-only because its
metadata, protection or filesystem structures cannot be preserved.

| Format | Browse / read / extract | Create | Edit existing | Writer boundary |
| --- | --- | --- | --- | --- |
| ZIP / CBZ | Yes | Yes | Eligible ZIP policy | Native unencrypted creation/editing streams within an 8 GiB budget; ZIP64 is supported. Original supported AES-256 protection uses the smaller buffered path. Comic member order is preserved. |
| 7z / CB7 | Yes | Yes | Eligible 7z policy | Native unencrypted Store/LZMA2 creation and eligible editing stream within an 8 GiB budget. Protected archives retain their password/header visibility on the smaller buffered path. |
| Numbered 7z volumes | Complete `.7z.001` sets, with 3–6 digit numbering | No | No | Complete captured sibling manifest; at most 1,024 parts, 8 GiB native / 256 MiB browser aggregate input. Native eligible members stream; unsupported/encrypted methods retain bounded decoding. Read-only across pane, F3 and extraction. |
| Windows PE SFX | Checked ZIP, 7z or RAR immediate overlays | No | No | Unsigned supported PE profiles; 32 MiB maximum stub and 16 MiB inspected metadata. Rejects ambiguous, signed and installer-specific layouts. Never executes the stub or drops it through an ordinary archive rewrite. |
| TAR / CBT | Yes | Yes | Inspected regular-file profiles | Preserves understood ownership, names, permissions, timestamps and PAX metadata; unknown extensions, links and special records are refused. |
| Compressed TAR | gzip, bzip2, XZ, Zstandard, LZ4, LZMA, UNIX compress | Yes, all seven | Eligible TAR plus one supported wrapper | Native TGZ/TAR.GZ creation/editing streams within an 8 GiB budget, including the decoded TAR headers. Other wrappers and buffered paths retain a 64 MiB decoded TAR limit. Includes short and long suffix aliases. |
| Compressed files | gzip, bzip2, XZ, Zstandard, LZ4, LZMA, UNIX compress | Yes, one file | Replace one ordinary payload | No member add/delete/rename or filesystem modes. Output filename supplies the decompressed name. Nested archive payloads can be created/read; single-payload editing requires the immediate decoded payload and cannot flatten inner wrappers. |
| Lzip | Lzip v1 and TAR.LZ | No | No | Checks CRC32, size, EOS and full member boundaries. Consecutive nonempty members are supported; v0, ignored tails and empty members inside collections are refused. |
| UNIX compress | .Z, .tar.Z and .taz | .Z and TAR.Z | Eligible direct payload or supported TAR | Reads 9–16-bit block/nonblock LZW; creates 12/14/16-bit block streams and rewrites with 14-bit block coding. No stored checksum or decoded size: some corruption or valid-prefix truncation cannot be detected. |
| JAR / WAR / EAR | Yes | Unsigned archives | Unsigned archives only | Signing records and signature-related manifest digests block rewriting. This is archive editing, not compilation or signing. |
| KMZ | Yes | Yes | Yes | A KML document must remain at the top level. |
| AR | Ordinary, GNU and BSD members | Flat regular files | Inspected profiles | Preserves order, ownership, permissions, timestamps and supported long-name style. Symbol indexes and thin archives are refused. |
| CPIO | Modern binary LE/BE, portable ASCII/odc, SVR4 newc and CRC | Newc, odc, binary LE, binary BE | Inspected profiles in their original layout | Preserves understood record/root/trailer metadata, ownership, device/inode fields, ordering and supported padding. Links, hard links, special records, incompatible mixed profiles and overflowing fields are refused. PWB-specific types are not interpreted. |
| RPM | Classic v3/v4 newc/CRC payloads | No | No | gzip, bzip2, XZ, Zstandard and uncompressed payloads. Supported present MD5/SHA-256 payload checksums are checked; publisher signatures and separate header/file digests are not authenticated. No installation or script execution. |
| CAB | Single-cabinet stored and MSZIP folders | No | No | Preserves MSZIP dictionary history across blocks and checks present block checksums when reading a folder. Spanned cabinets, split files, Quantum/LZX and unspecified non-ASCII legacy name encodings are refused. |
| XAR | XAR v1, stored/zlib/bzip2/XZ members | Unsigned XAR | Inspected unsigned profiles | Preserves known IDs, ownership, permissions, times, checksums and compression policy. Unknown XML/heap data, signatures, ACLs and xattrs block rewriting. |
| DEB / UDEB | AR wrapper and nested TAR members | No package builder | Coordinated prebuilt payload replacement | Exact original three-member wrapper/order; required control fields and present md5sums are checked. Replace prepared control/data payloads together. Nested in-app package edits are disabled. |
| ISO | ISO 9660, Joliet and ordinary Rock Ridge, including bounded regular-file multi-extent chains | Data ISO | Inspected data-only, single-extent profiles | Native creation/editing uses an 8 GiB image budget; each written member must be smaller than 4 GiB. Reader chains can represent logical members up to 8 GiB within existing operation limits. Retains inspected volume/root/Rock Ridge/Joliet metadata. Multi-extent files, boot records, hybrid/system areas, UDF, extra sessions and unknown extensions block rewriting. |
| UDF / ISO-UDF bridge | UDF 1.02/1.50/2.00/2.01 physical Type 1 partitions, FE/EFE, bounded embedded/short/long allocations, ordered multi-extent and sparse regular files | No | No | 2048-byte blocks; metadata CRC/tag/location checks. Virtual, sparable and metadata partitions, chained volume/file-set sequences and filesystem repair remain unsupported. Bridge images expose the UDF namespace and never acquire ISO writer eligibility. |
| FAT volume | FAT12/16/32, validated live chains, ASCII short names and checked UTF-16 long names | No | No | 512–4096-byte sectors, clusters through 32 KiB, bounded allocation and directory work. Dirty/active-table notices remain visible. No exFAT, OEM-only name decoding, deleted-file recovery or repair. |
| Linux ext volume | Bounded ext2/clean ext3/ext4 with classic/extent maps, sparse regular files and selected metadata checksums | No | No | 1/2/4 KiB blocks; strict UTF-8; regular hard-link paths, metadata-only links/specials. Indexed directories, external xattrs, journal recovery and unknown features are refused. See the [exact profile](archive-ext-profile.md). |
| NTFS volume | Bounded clean NTFS 3.0/3.1, resident/nonresident unnamed data, sparse/initialized ranges, validated indexes and regular hard links | No | No | Alternate streams are exact named metadata notices; system metadata is omitted while allocations remain checked. Attribute lists, compression, encryption, reparse points and recovery are refused. Independent complete-image corpus covers 3.1. See the [exact profile](archive-ntfs-profile.md). |
| Raw disk image | Unambiguous primary MBR or fully validated mirrored GPT; exact raw partition slices and eligible supported FAT/ext/NTFS filesystems | No | No | `.img`, `.ima`, `.dd`, `.raw`; `.fat`, `.fat12`, `.fat16`, `.fat32` name standalone volumes. Unknown partition types remain raw. No EBR, VM-container decoding, mounting or table writes. |
| HFS+ / HFSX | Hierarchy and regular data forks | Fresh HFSX data image | No | Native creation has an 8 GiB image budget and is case-sensitive, unjournaled HFSX with frozen HFS Unicode normalization. Existing filesystem metadata is not reconstructed from a partial file view. |
| DMG | Unencrypted UDIF raw/zero/ADC/zlib/bzip2/LZFSE/XZ-LZMA partitions and supported filesystems | HFSX data-volume DMG | Verified canonical single-volume HFSX data profiles on native local storage | Writer: 8 GiB packed/decoded budget, raw/zlib/zero blocks. Checks every nonpayload HFS byte and both UDIF CRC layers before writing; preserves volume/root/member dates and modes. Other codecs, partitions, resource forks, xattrs, signing and filesystem layouts are not rewritten. APFS file views are unsupported. |
| RAR / CBR | Existing compression/password reader plus streamed RAR5 Store | Built-in RAR5 Store / CBR; compressed RAR5 through a checked installed tool | Inspected unencrypted, nonsolid, single-volume RAR5 Store | Built-in native 8 GiB container/expanded budget, CRC-protected payloads, UTF-8 names, modes and retained exact time records. External creation has a separate 64 MiB/member and 256 MiB total/output budget. Existing compressed, encrypted, split, recovery, owner/link and unknown metadata profiles remain read-only. No external RAR engine is bundled. |
| Other ZIP packages | Yes | No | No | WHL, APK/APKS/XAPK, IPA/AAB, XPI, NuGet, VSIX, APPX/MSIX and bundles require package-specific rebuild/signing workflows. |
| CRX | CRX2/CRX3 ZIP payload | No | No | Header is bounded; publisher signatures are not authenticated. |
| PKG / XIP | XAR members and supported nested PBZX/CPIO payloads | No | No | Preview an extensionless `Payload` or `Content` member in F3 to browse its supported inner file tree. Package metadata and signing need dedicated tools. |
| PBZX | Stored/XZ block stream and supported inner containers | No | No | Positional chunk decoding; portable CPIO payloads become a file tree. Unknown inner formats remain one decoded payload. Apple Archive/YAA and other unsupported payload formats are not interpreted. |
| Static object libraries (`.a`) | AR members | No | No | A linker/archive tool must regenerate the library symbol index. |

Office and EPUB files retain their document/book viewers. No archive action
installs a package, executes a member, mounts an image or writes a physical disk.
The existing source-account, review, verification and recovery requirements in
[archive endpoints](archive-endpoints.md) govern every enabled rewrite.

## Creating and editing

The [Commander workflow guide](archive-commander-workflows.md) covers shared
background jobs, separate-per-selection creation, batch testing and extraction,
installed packers, bounded 7z tuning, numbered volumes and SFX browsing. These workflows
retain the format-specific limits in this table.

Use **Create archive…** for the 35-choice format picker. It exposes only implemented
compression choices and password options. gzip/bzip2/XZ/Zstandard/LZ4/LZMA/UNIX compress take one
regular file; AR takes flat regular files; the other creation formats support
folders within their format-specific name/depth limits. KMZ needs a top-level
KML document. Java archives must be unsigned.

Fresh images use a private output spool on native platforms. The creator opens
the completed image, compares its complete namespace and streamed file SHA-256
values, then rechecks source versions, contents, folder membership and captured
permission bits. It also verifies the staged destination bytes before publishing
an exclusively created output. Cancellation or a source/verification failure
leaves no published partial image. Source files are retained.

Ordinary executable and directory permission bits are captured when the source
backend provides them; otherwise new files/directories use format defaults.
Creation does not copy ownership, ACLs, resource forks or extended attributes.
Setuid/setgid inputs are refused because their original ownership is not captured.
HFSX normalizes names according to HFS's frozen Unicode 3.2 rules and rejects
collisions after normalization. Images contain ordinary data files and folders,
not a preservation copy of a macOS application filesystem.

Open an eligible archive workspace to edit, add, rename or remove members.
**Review** builds and verifies a concrete candidate. **Save** publishes that
reviewed candidate at the captured original path through the existing recovery
journal. Unsupported format structures produce a specific read-only reason.
Member metadata and source order survive successive saves, including renamed
members. Single compressed files expose replacement of their one payload.

DEB/UDEB editing accepts externally prepared control and data archives together;
it does not regenerate dependency metadata, Installed-Size or missing checksum
coverage. The structural and present-md5sums checks establish the supported
wrapper profile, not full package-build validity or publisher trust.

## Recovering ZIP records

Select one native local ZIP or CBZ and choose **Recover ZIP to new file…** from
the context menu, Tools menu or command palette. The report lists verified
stored/deflated local records and explains exclusions or an early scan stop.
Review the selected entries and new ZIP filename, then recover through the
Operations queue. The candidate is rebuilt, reopened by a separate ZIP reader,
and verified before staged exclusive publication. Existing files are never
replaced. Input, expanded contents and output each have a 64 MiB bound.

Measured deflate data descriptors are supported; stored descriptors, encrypted
entries, ZIP64, self-extractors and recognized split sets are outside this
recovery profile. A verified prefix does not establish completeness of a
truncated archive. See the [complete recovery and restart contract](archive-zip-recovery.md).

## Copying between archives

With two archive panes open, select source members and use **F5** or **Copy**.
Review the destination directory, collision policy, staged member changes and
protection policy before saving. The workspace's **Copy out** action also accepts
an archive destination when its source draft is clean. Source and destination
routes/passwords are captured independently, including nested archives. Read-only
source formats can supply ordinary members when they fit the workspace bounds.

Copies retain hierarchy, empty directories, supported times and permission bits;
protection follows the destination archive. Source ownership, ACLs, resource
forks, links and signatures are not imported. Save or discard a source draft
first. The same physical outer archive, including native hard-link aliases,
cannot be both endpoints of this transaction. Source bytes are checked before
staging and again before destination installation. Source archives are retained.
Archive-to-archive moves use the separate native transaction below.

## Moving between archives

With two distinct writable top-level native archives open, use **F6** or
**Move**, or choose **Move to the other archive…** from a clean workspace.
Choose the destination directory and keep-both/replace/skip conflict policy.
**Prepare both reviews** verifies the destination additions and source removals
before either physical archive changes; **Publish reviewed move** confirms
that concrete pair. Independent source/destination passwords are supported.

The destination is published and verified first. Source removal requires a
durable dependency on that exact destination, retained across restart. Only
successfully copied members are removed; skipped descendants keep their parent
directories. Supported retained-source metadata and original source protection
follow its writer policy. Imported metadata and destination protection follow
the copy profile above, including its ownership/ACL/signature limits.

Cancellation or a failure between publications can leave a published copy and
unremoved source contents. An interrupted source installation can instead leave
the original at a recorded backup path. The result distinguishes those outcomes
and directs recovery to both captured archive paths. Recovery cannot finish
source removal or clean its original backup if the destination changed; an
intact original can be restored through verified exclusive moves.

This is ordered publication of two archives, not one atomic filesystem update.
Nested cross-container routes, browser/remote publication, same physical outer
archives and hard-link aliases remain outside this move scope. The combined
packed candidate budget is the sum of the two workspace limits when either
workspace uses native streaming, up to 16 GiB for two eligible 8 GiB workspaces;
each container retains its individual limit. Two buffered workspaces share the
existing 256 MiB combined budget. See the [endpoint contract](archive-endpoints.md)
for precise receipt, source-authority, recovery and external-change boundaries.
Rearrangement within one workspace uses the grouped move below.

## Moving members within an archive

Open an eligible archive workspace, select files or folders and choose **Move
within archive…**. Choose an existing destination folder and a collision policy:
**Stop without changes**, **Keep both (new name)** or **Skip conflicting items**.
The entire selection is checked before one draft change. Existing destination
files/folders are retained; colliding folders are not merged. Skipping a folder
keeps its complete source subtree. A move to the same parent changes nothing.

Recursive and empty folders, implicit directories, overlapping parent/child
selections and pending draft edits are supported. Moving a folder into itself or
one of its descendants is refused. The picker captures the selection and
workspace generations; a changed workspace requires reopening the picker.

**Save archive** builds the normal review and publishes the verified complete
container. Original member identity retains the format's supported metadata and
protection. Nested workspaces publish through their captured outer archive.
Flat AR, single compressed payloads, replacement-only Debian package profiles
and read-only containers do not expose this action. This workflow does not join
two independently opened aliases or move between different nested routes.

## Testing an archive

Choose **Test archive** in F3's archive listing. The report reads regular members
sequentially, verifies whatever checks their readers provide, calculates SHA-256
values and distinguishes checked, failed, skipped and unprocessed entries.
Expand a row for its digest or failure details; **Copy report** copies the full
report. Unsafe/special entries and members exceeding limits remain visible.

Buffered checks retain a 64 MiB member limit and 256 MiB declared work budget.
Eligible native streamed readers use their existing member and total-work
limits, up to 8 GiB; protected, nested and unsupported streaming profiles retain
their smaller bounds. Failed attempts still consume their declared budget.
Namespace validation is bounded separately. Cancellation is cooperative between reads/chunks; an active
buffered decode may finish first. The report never changes archive contents and
does not repair data, authenticate a publisher or invent stored checksums.
LZMA-alone and UNIX compress lack payload checksums, and optional checksums may
also be absent in other formats. An incomplete check is never a passing report.

## Using disk images

For raw disk images, **F3 → Hex → Inspect partitions** reads bounded GPT/MBR
metadata, reports independent primary/backup CRC results and selects fields in
Hex. For an admitted table, **Browse image** opens the
[read-only image adapter](archive-disk-image-profile.md) and retains the chosen
512/4096-byte sector size. The source and table are revalidated when opening.
Each partition has `partition-<table-index>/raw.img`; eligible FAT/ext partitions
also expose `partition-<table-index>/files/…`. Standalone FAT/ext volumes expose
their own files directly. Neither path grants partition or filesystem writes.

The first [FAT profile](archive-fat-profile.md) supports FAT12/16/32 with
validated chains, safe long names and bounded metadata work. MBR/GPT browsing
requires an admitted table; damaged or conflicting copies stay in the
inspection workflow. An unsupported or corrupt child filesystem remains raw
with a notice. Source-access failures and cancellation stop the operation.
The [ext profile](archive-ext-profile.md) adds Linux ext2/clean ext3/ext4 volumes
through the same read-only route, with sparse/indirect/extent allocation and
selected metadata-checksum validation.
Native F3 and workspace input images retain the existing 8 GiB ceiling. A
workspace also counts raw partitions and their file views in its aggregate
8 GiB expanded-content allowance; selecting both copies their overlapping
content twice. Buffered and remote paths retain their own smaller limits.

ISO multi-extent chains appear as one regular file, with sections read in their
recorded order. The reader bounds section counts and combined logical size;
existing preview/extraction limits still apply. Multi-extent images remain
read-only. See [ISO section-chain support](archive-iso-multiextent.md).

Supported DMG compression includes ADC (UDCO), LZFSE (ULFO) and XZ-wrapped LZMA (ULMO), with
strict chunk-length checks and a 16 MiB compressed-chunk/dictionary ceiling.
These added codecs are read-only; see [DMG codec profiles](archive-dmg-codecs.md)
for integrity boundaries and independently generated verification inputs.

Open a supported image as a folder to navigate its files. F3 provides a member
listing and **Container details**, including applicable limitations and any
filesystem that could not be opened. Safe regular members can be previewed or
copied through the existing archive workflow.

DMGs expose two distinct trees:

- `files/<number>-<volume>/…` contains files from supported FAT, HFS+/HFSX, UDF or ISO
  partitions. These are data forks, not complete macOS application bundles
  with resource forks, extended attributes, permissions or code signatures.
- `partitions/<number>-<volume>.<fat|hfs|udf|iso|img>` contains raw partition images.
  Their size may exceed the member extraction limit even when small files in
  their filesystem remain readable. Select the `files` tree when extracting
  filesystem contents; extracting everything also requests the raw images.

DMG symbolic links, including the common `Applications` link, are omitted
from the file tree with an explicit notice. Their original records remain in
the raw image. An unsupported or damaged filesystem produces a raw partition
plus a visible explanation, never a claim that its files were decoded.
Child filesystem notices are forwarded into the DMG details, including dirty
FAT flags and open UDF volume status.
Direct pane browsing rejects namespaces containing unsafe paths or unsupported
special entries. Extraction rejects any such selected entry, while safe selected
subsets remain extractable. F3 displays these records with reading disabled when
the underlying reader can enumerate them; malformed ISO/HFS names are refused
while opening the image.

## Using package payloads

Open `.rpm`, `.cab` or `.pbzx` through the normal archive pane or F3 viewer.
RPM presents the payload's CPIO tree directly. CAB exposes its files with
Windows separators normalized to archive paths. A PBZX stream containing a
supported archive exposes that archive's tree; an opaque stream exposes one
decoded member. Signature detection also works for extensionless F3 inputs and
inside supported compression wrappers.

For an Apple `.pkg` or `.xip`, F3 first lists the XAR wrapper. Preview its
`Payload` or `Content` member to open supported PBZX/CPIO contents, then preview
individual regular files. That nested preview still buffers the outer XAR
member up to the existing 64 MiB limit; larger outer members remain unavailable
through this path. A standalone PBZX file can use the larger positional path
described below. No package action installs software or executes scripts.

RPM, CAB and PBZX remain read-only, including after a misleading filename
change. Standalone eligible odc/binary CPIO can be created and rewritten in its
original profile, alongside newc/CRC rewriting. This does not make an enclosing
RPM, PBZX or signed package writable. Package signature notices distinguish
content checksums from publisher authentication.

## Bounds and integrity

- Native pane sessions spool at most 8 GiB; browser pane sessions keep at most
  256 MiB in memory. These are input limits, not promised resident-memory use.
- Native F3 borrows its existing random-access source for archive metadata
  and member reads. Large local disk images do not require a full-file buffer;
  ordinary remote files use the existing 2 GiB spool limit. Ordinary browser F3
  retains its 64 MiB full-data input limit. First parts of numbered 7z sets use
  the separate 8 GiB native / 256 MiB browser input allowance; their complete
  captured set must also fit that aggregate limit. Native remote F3 can retain
  both its first-part spool and the set snapshots. Password retries borrow a fresh reader, and
  changing modes or closing the viewer immediately invalidates pending reads.
- Buffered interactive member reads remain capped at 64 MiB per member.
  Eligible native top-level ZIP/CBZ, 7z/CB7, TAR/CBT, TGZ/TAR.GZ and RAR5
  Store/CBR workspaces
  stream imports, copy-out, repacking, verification and publication within an
  8 GiB member/container/expanded-content budget. Editing a member in an in-memory
  text or hex editor retains its separate bound. Native direct extraction uses
  the streamed reader for eligible formats; buffered extraction keeps
  its 64 MiB member and 256 MiB input/total-output limits. Copying through a pane
  keeps its own operation planning and cancellation rules.
- Fresh ISO/HFSX/DMG creation on bounded native local storage streams within
  an 8 GiB image budget, including image metadata and filesystem free space.
  Eligible existing data ISO and fully verified canonical single-volume HFSX
  data DMG profiles also support streamed workspace editing and extraction.
  ISO and DMG allow 100,000 entries; each ISO file must be smaller than 4 GiB.
  Existing raw HFS images remain read-only. Other creation backends retain
  the 2 GiB image bound; browser output spools remain capped at 256 MiB.
  Buffered previews retain their own limits, and the creation UI remains
  native-local. See the [ISO/RAR/DMG scope and evidence](archive-iso-rar-dmg.md).
- Fresh native uncompressed TAR/CBT creation also streams to a 2 GiB packed
  output bound, including headers and alignment. Eligible bounded native-local
  endpoints can create members above 64 MiB and archives above 256 MiB, with
  streaming member hashes, full source rechecks and staged byte readback.
  Existing eligible native TAR editing uses its separate 8 GiB streaming budget.
  See the [measured large TAR evidence](archive-sync-large-tar-verification.md).
- Native unencrypted ZIP/CBZ, 7z/CB7 Store/LZMA2, RAR5 Store/CBR and
  TGZ/TAR.GZ creation streams
  within an 8 GiB member/expanded/packed budget. TGZ's decoded TAR including
  headers must also fit. Protected archives, nested writes, browser/fallback
  paths, 7z Deflate creation and other formats retain their buffered limits:
  64 MiB/member and 256 MiB total/packed, with 64 MiB for compressed streams
  and decoded TAR wrappers. Native creation and workspace saves can use the
  [shared background queue](archive-operation-queue.md) within these same bounds;
  queuing does not expand a codec's supported profile.
  See the [parity and verification status](archive-parity-large-continuation.md).
- Compression wrappers are bounded by 64 MiB input/output by default and
  four nested wrappers. Readers check available integrity/framing information;
  formats without a stored checksum or decoded length cannot detect every valid
  prefix or bit change. Actual member length must match metadata.
  Rewriting retains supported gzip name/comment/time/header-CRC metadata and XZ
  integrity checks. Concatenated gzip/XZ/Zstandard streams, gzip application
  extra fields, Zstandard dictionaries and skippable extension frames remain
  read-only because a one-stream rewrite cannot preserve all their semantics.
  XZ output uses real LZMA2 compression, including CRC32/CRC64/SHA-256 framing.
  Fresh and rewritten LZ4 output uses independent 256 KiB blocks with
  block/content checksums and real compression (or explicit Store at creation).
  Eligible rewrites use this canonical block/checksum profile rather than
  retaining the original encoder's settings; linked blocks are readable.
  Reading is limited to 4,096 combined data/skippable frames and 1,000,000 blocks.
  LZ4 collections and skippable metadata stay read-only. Legacy LZ4 and external
  dictionaries are unavailable. Shared LZ4/Zstandard skippable magic is resolved by reading
  ahead to the actual bounded data-frame header.
- LZMA-alone uses explicit `.lzma`/`.tlz` filename hints because it has no unique
  signature. Known/unknown sizes, mandatory end markers where needed, exact
  input consumption, final range state and dictionary distances are checked.
  Dictionaries are capped at 64 MiB and `lc + lp` at four; declarations below
  4 KiB use the format's 4 KiB minimum. Fresh and rewritten output uses real
  compression, canonical `lc=3, lp=0, pb=2` properties, a known size and no end
  marker. Creation's Fast/Normal/Maximum choices use 64 KiB/8 MiB/64 MiB
  dictionaries; workspace rewrites use the default 8 MiB dictionary.
  LZMA-alone has no stored content checksum. Lzip v1 reuses this bounded engine
  with required EOS and verifies its own CRC32 and footer. Lzip input is limited
  to 4,096 members, with dictionaries between 4 KiB and 64 MiB; a standalone
  empty member is supported, but empty members inside collections are refused.
  Single compressed-file rewriting is refused once the reader has traversed
  another container, even if nested layers have the same format name.
- UNIX compress creation uses 12-, 14- or 16-bit block dictionaries for Fast,
  Normal or Maximum. A full dictionary resets before adding another phrase.
  Eligible rewrites normalize accepted 9–16-bit block/nonblock inputs to the
  normal 14-bit block profile. Input/output each remain capped at 64 MiB, and
  `.tar.Z`/`.taz` also require a supported TAR profile. No checksum or decoded
  length is stored; structural validity cannot prove absence of all corruption
  or valid-prefix truncation. Creation/rewrite verification still compares the
  complete result with its captured source. Independent gzip/libarchive and
  actual JavaScript evidence are recorded in the
  [UNIX compress writer profiles](../test/fixtures/archives/UNIX_COMPRESS_WRITER_PROFILES.md).
- ISO and HFS enforce 100,000 entries, 64 directory levels and 32 MiB of
  directory/catalog metadata. ISO also bounds continuation and pathname data.
  The ISO writer uses an ordinary primary hierarchy of at most eight levels
  including the root, without relocation. HFSX names fit 255 UTF-16 units and
  HFS timestamps fit the 1904–2040 unsigned epoch range. Unsupported dates or
  names fail before publication. XAR rewrites are capped at 5,000 entries and
  65 path components, with explicit directory records.
- AR/CPIO/XAR enforce 200,000 records, 16 MiB aggregate metadata and 16 KiB
  names. XAR compressed/expanded TOCs are each capped at 8 MiB, with bounded
  XML events, elements and depth.
- RPM header metadata is limited to 16 MiB and 200,000 index entries. Packed
  and expanded payloads are each capped at 64 MiB by default; XZ dictionaries
  and Zstandard windows are capped at 64 MiB. Header ranges, tag types, actual
  compression, declared sizes and supported present MD5/SHA-256 payload digests
  are checked before opening the CPIO tree. Unsupported digests, compressors,
  v6 and stripped large-file payloads are refused. Links and special CPIO
  entries remain non-extractable.
- CAB metadata is capped at 16 MiB, names at 16 KiB, folders at 4,096 and data
  blocks at 100,000. A decoded folder is capped at 64 MiB by default; opening
  reads its metadata without decoding file data. Member reads decode and check
  the entire containing folder, keeping one shared folder cache. Present block
  checksums are verified on read, not on listing. MSZIP blocks retain the last
  32 KiB of folder history and cannot expand beyond their declared 32 KiB block
  bound. UTF-8 flagged names and unflagged ASCII names are supported. CAB dates
  are local wall-clock values without a stored time zone.
- PBZX inputs and logical decoded payloads are bounded at 2 GiB, with at most
  100,000 chunks. Each chunk and XZ dictionary is capped at 16 MiB; a single
  source read is capped at 64 MiB. Framing is indexed without fetching payload
  bytes; positional reads serialize access to one shared decoded-chunk cache.
  A large CPIO member can be skipped while listing and reading a later small
  member. This does not raise member extraction limits. Stored size must not
  exceed decoded size, and only the final chunk may be shorter than the declared
  block size. Present XZ checksums are verified for chunks actually read;
  stored chunks and XZ `CHECK_NONE` streams have no data checksum. Partial
  browsing does not verify an entire PBZX payload or a package signature.
- DMG limits XML metadata to 8 MiB, block maps to 128 and chunks to 100,000.
  Each compressed chunk is limited to 16 MiB. One shared chunk cache avoids
  retaining an expanded buffer per partition. Declared disk geometry is
  bounded separately from allocatable memory.
- DMG compression checksums, when present, are checked when decoded. ADC and
  LZFSE have no embedded checksum. A raw partition's
  CRC is checked when that whole partition is extracted; UDIF ignore blocks
  do not contribute to the CRC. Partial file browsing does not verify the
  whole-image checksum or any publisher signature.
- FAT listing is bounded by 64 MiB metadata reads, 32 MiB directory allocation,
  100,000 entries, depth 64, 1,048,576 cluster visits and 100,000 extents.
  Partition-image and DMG FAT adapters share traversal and metadata allowances
  across child volumes and count retained relative plus prefixed paths against
  16 MiB. Member payload reads are separately bounded. See the two reader
  profiles for exact accounting and unsupported structures.
- During FAT recognition/listing inside DMG, separate shared caps permit at
  most 64 MiB of backing input and 256 MiB of cache-miss decompression work.
  This accounts for compressed-block amplification beyond logical metadata
  request sizes. Exhaustion retains raw entries with a notice and suppresses
  further filesystem probing; it does not broaden extraction limits.
- Readers validate source ranges and short reads, enforce source ownership,
  reject malformed metadata, and never follow archive links. Extraction
  keeps existing path traversal, destination-link and overwrite protections.

## Dependencies and provenance

The app bundles no external packer. Built-in Dart readers, writers and format
adapters reuse the existing locked packages. Optional external creation uses
an explicitly configured installed 7-Zip/RAR executable only after its exact
profile passes the checks described in the [workflow guide](archive-commander-workflows.md).
`koni_codecs` 0.9.0 is an explicit direct dependency for LZMA/LZMA2 encoding:
`koni_archive` 0.9.0 and its 0.9.0 codec/core packages (MIT), `archive` 4.6.0
(MIT), `xml` 6.6.1 (MIT) and `crypto` 3.0.7 (BSD-3-Clause). Check `pubspec.lock`
when updating these versions; dependency ranges are not a codec guarantee.

Primary references used for layout and validation:

- [ECMA-119 / ISO 9660](https://ecma-international.org/publications-and-standards/standards/ecma-119/).
- [Apple HFS Plus Volume Format, TN1150](https://developer.apple.com/library/archive/technotes/tn/tn1150.html).
- [XZ file format](https://tukaani.org/xz/xz-file-format.txt).
- [LZ4 frame](https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md) and [block](https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md) specifications.
- [XXH32 checksum specification](https://github.com/Cyan4973/xxHash/blob/dev/doc/xxhash_spec.md).
- [LZMA-alone layout](https://github.com/tukaani-project/xz/blob/master/doc/lzma-file-format.txt).
- [Igor Pavlov's LZMA packet/range-coder specification](https://android.googlesource.com/platform/external/lzma/+/refs/heads/nougat-dev/DOC/lzma-specification.txt).
- [Lzip v1 format](https://www.nongnu.org/lzip/manual/lzip_manual.html#File-format).
- [UNIX compress format](https://man.openbsd.org/compress.1) and independent public-domain ncompress validation.
- [Binary CPIO layout](https://github.com/libarchive/libarchive/blob/master/libarchive/cpio.5).
- [GNU binutils AR](https://sourceware.org/binutils/docs/binutils/ar.html).
- [GNU CPIO format reference](https://www.gnu.org/software/cpio/manual/html_node/Media.html).
- [Portable CPIO header layout](https://www.ibm.com/docs/en/zos/3.1.0?topic=formats-cpio-format-cpio-archives).
- [RPM v3/v4 format and headers](https://rpm.org/docs/4.20.x/manual/format_header.html).
- [Microsoft Cabinet format](https://learn.microsoft.com/en-us/previous-versions/bb417343(v=msdn.10)) and [MSZIP structures](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-mci/3048c471-f739-4d30-bcb3-a962cfe84a69).
- [PBZX reference reader](https://github.com/blacktop/ipsw/blob/master/pkg/ota/pbzx/read.go).
- [Apple XAR sources](https://github.com/apple-oss-distributions/xar).
- [UDIF reference implementation](https://github.com/mozilla/libdmg-hfsplus).
- [archive 4.6.0 strict-decoder contract](https://pub.dev/packages/archive/changelog).

The test corpus includes original malformed-input fixtures, reference AR/CPIO/
XAR output from GNU ar and libarchive, a libarchive-produced ISO (including
Unicode and long Rock Ridge continuation names), and independently formatted
HFS+/UDIF images with a multi-level catalog, 42 original text files and an
Applications link. Native generators are test tooling only. Exact fixture
commands, tool revisions and hashes are in
[NATIVE_DISK_IMAGES.md](../test/fixtures/archives/NATIVE_DISK_IMAGES.md).

The package continuation adds independently produced Windows MakeCAB cabinets,
rpmbuild RPMs, an original libarchive portable CPIO, and PBZX framing verified by
an independent BSD-licensed decoder with native liblzma. The MSZIP reference
includes a block that cannot decode without the previous dictionary. Reproducible
commands, source revisions, fixture hashes and attribution are in
[CAB_READERS.md](../test/fixtures/archives/CAB_READERS.md),
[RPM_REFERENCE.md](../test/fixtures/archives/RPM_REFERENCE.md),
[CPIO_ODC.md](../test/fixtures/archives/CPIO_ODC.md) and
[PBZX_REFERENCE.md](../test/fixtures/archives/PBZX_REFERENCE.md).
These native/reference tools are test dependencies only; the app adds no
runtime dependency or subprocess decoder.
The complete observed test scope and local environment are recorded in
[package-reader verification](archive-package-readers-verification.md).

Writer acceptance also includes native GNU tar/Python tarfile and
GNU ar/libarchive/dpkg-deb readback,
Python/liblzma decoding of emitted XZ, libarchive ISO metadata/content checks,
and native fsck.hfsplus plus libdmg extraction of fresh HFSX/UDIF images. Large
streaming cases exceed the interactive 64 MiB member limit. The reproducible
optional reference checks are:

- [ISO generator](../test/support/generate_iso_writer_reference.dart) and
  [libarchive verifier](../test/support/verify_iso_writer_libarchive.py).
- [Package emitter](../test/support/emit_archive_package_writers.dart) and
  [GNU ar/libarchive/dpkg verifier](../test/support/check_archive_package_writers.py).
- [TAR emitter](../test/support/emit_archive_tar_writer.dart) and
  [GNU tar/Python verifier](../test/support/check_archive_tar_writer.py).
- [HFSX/DMG filesystem and extraction checker](../test/support/verify_disk_writer_native.dart).

These reference tools are test dependencies only. Native macOS mounting and
platform-specific release acceptance are not established by Linux readback.

APFS, ARJ/LZH/ACE/UC2, CAB Quantum/LZX/spanning, RPM v6/stripped
payloads, Apple Archive/YAA and additional ZIPX methods are not enabled by these
increments. G22 remains partial; additional profiles require their own
implementation and independent fixtures. The later read-only
[UDF increment](archive-udf-profile.md) has its own bounded profile and evidence.

The workflow/codec continuation adds original liblz4, liblzma and libarchive
fixtures, public-domain ncompress validation, binary CPIO in both byte orders,
and independent wrapped TAR fixtures. See [LZ4](../test/fixtures/archives/LZ4-REFERENCE.md),
[LZMA](../test/fixtures/archives/LZMA-REFERENCE.md),
[Lzip](../test/fixtures/archives/LZIP-REFERENCE.md),
[UNIX compress](../test/fixtures/archives/UNIX_COMPRESS_REFERENCE.md), and
[binary CPIO](../test/fixtures/archives/CPIO_BINARY.md) for provenance and commands.
The [continuation record](archive-workflows-codecs-continuation.md) records the
independent feature-ideas review of VaultExplorer; none of its GPL implementation,
tests or assets were inspected or imported.
The [verification record](archive-workflows-codecs-verification.md) gives the
observed regression, analysis, independent readback and portable-runtime gates.

The [rearrangement/CPIO continuation](archive-rearrange-cpio-continuation.md)
adds grouped moves within one workspace and three legacy CPIO creation choices.
[CPIO writer provenance](../test/fixtures/archives/CPIO_WRITER_PROFILES.md)
records exact profile preservation, integer/name bounds and native libarchive
readback. odc and binary CPIO contain no stored content checksum or encryption.

The [native move/UNIX compress continuation](archive-move-compress-continuation.md)
adds reviewed destination-first moves between eligible top-level native archives,
durable destination-dependent source recovery, and `.Z`/TAR.Z creation and
eligible rewrites. Its [verification record](archive-move-compress-verification.md)
records service/UI regressions, independent gzip/libarchive readback, actual
JavaScript execution and the remaining publication/format limits.
