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
| ZIP / CBZ | Yes | Yes | Eligible ZIP policy | Original supported AES-256 protection is retained. Comic member order is preserved. |
| 7z / CB7 | Yes | Yes | Eligible 7z policy | Original password and header visibility are retained. |
| TAR / CBT | Yes | Yes | Inspected regular-file profiles | Preserves understood ownership, names, permissions, timestamps and PAX metadata; unknown extensions, links and special records are refused. |
| Compressed TAR | gzip, bzip2, XZ, Zstandard | Yes, all four | Eligible TAR plus one supported wrapper | Includes TGZ, TBZ/TBZ2, TXZ, TZST and long suffix aliases. Decoded TAR is limited to 64 MiB, including headers. |
| Compressed files | gzip, bzip2, XZ, Zstandard | Yes, one file | Replace one ordinary payload | No member add/delete/rename or filesystem modes. Output filename supplies the decompressed name. Nested archive payloads can be created/read; editing requires a supported container/wrapper profile. |
| JAR / WAR / EAR | Yes | Unsigned archives | Unsigned archives only | Signing records and signature-related manifest digests block rewriting. This is archive editing, not compilation or signing. |
| KMZ | Yes | Yes | Yes | A KML document must remain at the top level. |
| AR | Ordinary, GNU and BSD members | Flat regular files | Inspected profiles | Preserves order, ownership, permissions, timestamps and supported long-name style. Symbol indexes and thin archives are refused. |
| CPIO | SVR4 newc and CRC | Newc | Inspected newc/CRC | Preserves known record/root/trailer metadata. Links, hard links, device records and unsupported variants are refused. |
| XAR | XAR v1, stored/zlib/bzip2/XZ members | Unsigned XAR | Inspected unsigned profiles | Preserves known IDs, ownership, permissions, times, checksums and compression policy. Unknown XML/heap data, signatures, ACLs and xattrs block rewriting. |
| DEB / UDEB | AR wrapper and nested TAR members | No package builder | Coordinated prebuilt payload replacement | Exact original three-member wrapper/order; required control fields and present md5sums are checked. Replace prepared control/data payloads together. Nested in-app package edits are disabled. |
| ISO | ISO 9660, Joliet and ordinary Rock Ridge | Data ISO | Inspected data-only profiles | Rock Ridge retains exact Unicode/long names; Joliet has compatible alternate names. Boot records, hybrid/system areas, UDF, extra sessions and unknown extensions block rewriting. |
| HFS+ / HFSX | Hierarchy and regular data forks | Fresh HFSX data image | No | Creation is case-sensitive, unjournaled HFSX with frozen HFS Unicode normalization. Existing filesystem metadata is not reconstructed from a partial file view. |
| DMG | Unencrypted supported UDIF partitions/filesystems | Fresh HFSX data-volume DMG | No | Creates unsigned, unencrypted raw/zlib/zero-block UDIF. Existing partitions, filesystem metadata, APFS and signing require another workflow. |
| RAR / CBR | Existing reader | No | No | Existing password and compression-method limits apply. |
| Other ZIP packages | Yes | No | No | WHL, APK/APKS/XAPK, IPA/AAB, XPI, NuGet, VSIX, APPX/MSIX and bundles require package-specific rebuild/signing workflows. |
| CRX | CRX2/CRX3 ZIP payload | No | No | Header is bounded; publisher signatures are not authenticated. |
| PKG / XIP | XAR members | No | No | Package metadata and signing need dedicated tools; PBZX remains an undecoded payload. |
| Static object libraries (`.a`) | AR members | No | No | A linker/archive tool must regenerate the library symbol index. |

Office and EPUB files retain their document/book viewers. No archive action
installs a package, executes a member, mounts an image or writes a physical disk.
The existing source-account, review, verification and recovery requirements in
[archive endpoints](archive-endpoints.md) govern every enabled rewrite.

## Creating and editing

Use **Create archive…** for the format picker. It exposes only implemented
compression choices and password options. gzip/bzip2/XZ/Zstandard take one
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

## Using disk images

Open a supported image as a folder to navigate its files. F3 provides a member
listing and **Container details**, including applicable limitations and any
filesystem that could not be opened. Safe regular members can be previewed or
copied through the existing archive workflow.

DMGs expose two distinct trees:

- `files/<number>-<volume>/…` contains files from supported HFS+/HFSX or ISO
  partitions. These are data forks, not complete macOS application bundles
  with resource forks, extended attributes, permissions or code signatures.
- `partitions/<number>-<volume>.<hfs|iso|img>` contains raw partition images.
  Their size may exceed the member extraction limit even when small files in
  their filesystem remain readable. Select the `files` tree when extracting
  filesystem contents; extracting everything also requests the raw images.

DMG symbolic links, including the common `Applications` link, are omitted
from the file tree with an explicit notice. Their original records remain in
the raw image. An unsupported or damaged filesystem produces a raw partition
plus a visible explanation, never a claim that its files were decoded.
Direct pane browsing rejects namespaces containing unsafe paths or unsupported
special entries. Extraction rejects any such selected entry, while safe selected
subsets remain extractable. F3 displays these records with reading disabled when
the underlying reader can enumerate them; malformed ISO/HFS names are refused
while opening the image.

## Bounds and integrity

- Native pane sessions spool at most 2 GiB; browser pane sessions keep at most
  256 MiB in memory. These are input limits, not promised resident-memory use.
- Native F3 borrows its existing random-access source for archive metadata
  and member reads. Large local disk images do not require a full-file buffer;
  remote files use the existing 2 GiB spool limit. Browser F3 retains its
  64 MiB full-data input limit. Password retries borrow a fresh reader, and
  changing modes or closing the viewer immediately invalidates pending reads.
- Interactive member reads and existing workspace edits are capped at 64 MiB per member. Direct whole-archive extraction keeps
  its 256 MiB input/total-output limits. Copying through a pane keeps its own
  operation planning and cancellation rules.
- Fresh native ISO/HFSX/DMG creation streams output up to 2 GiB, including image
  metadata. Files larger than 64 MiB are supported in that creation path and
  verified by streaming; this does not raise the existing workspace edit,
  preview or ordinary extraction limits. Browser/fallback output spools are
  capped at 256 MiB, and the creation UI remains native-local.
- Ordinary creation and existing workspace publication keep the 256 MiB packed
  and decoded-total limits; compressed streams and decoded TAR wrappers keep
  their 64 MiB bounds. Native spooling does not make buffered codecs unbounded.
- Compression wrappers are bounded by 64 MiB input/output by default and
  four nested wrappers. Decompression checks integrity and truncation rather
  than accepting partial output. Actual member length must match metadata.
  Rewriting retains supported gzip name/comment/time/header-CRC metadata and XZ
  integrity checks. Concatenated gzip/XZ/Zstandard streams, gzip application
  extra fields, Zstandard dictionaries and skippable extension frames remain
  read-only because a one-stream rewrite cannot preserve all their semantics.
  XZ output uses real LZMA2 compression, including CRC32/CRC64/SHA-256 framing.
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
- DMG limits XML metadata to 8 MiB, block maps to 128 and chunks to 100,000.
  Each compressed chunk is limited to 16 MiB. One shared chunk cache avoids
  retaining an expanded buffer per partition. Declared disk geometry is
  bounded separately from allocatable memory.
- DMG compressed-block checksums are checked when decoded. A raw partition's
  CRC is checked when that whole partition is extracted; UDIF ignore blocks
  do not contribute to the CRC. Partial file browsing does not verify the
  whole-image checksum or any publisher signature.
- Readers validate source ranges and short reads, enforce source ownership,
  reject malformed metadata, and never follow archive links. Extraction
  keeps existing path traversal, destination-link and overwrite protections.

## Dependencies and provenance

No native runtime or subprocess packer is added to the app. The readers and
writers are original Dart implementations using the existing locked packages;
`koni_codecs` 0.9.0 is now an explicit direct dependency for LZMA2 compression:
`koni_archive` 0.9.0 and its 0.9.0 codec/core packages (MIT), `archive` 4.6.0
(MIT), `xml` 6.6.1 (MIT) and `crypto` 3.0.7 (BSD-3-Clause). Check `pubspec.lock`
when updating these versions; dependency ranges are not a codec guarantee.

Primary references used for layout and validation:

- [ECMA-119 / ISO 9660](https://ecma-international.org/publications-and-standards/standards/ecma-119/).
- [Apple HFS Plus Volume Format, TN1150](https://developer.apple.com/library/archive/technotes/tn/tn1150.html).
- [XZ file format](https://tukaani.org/xz/xz-file-format.txt).
- [GNU binutils AR](https://sourceware.org/binutils/docs/binutils/ar.html).
- [GNU CPIO format reference](https://www.gnu.org/software/cpio/manual/html_node/Media.html).
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

UDF, APFS, CAB, RPM, ARJ/LZH/ACE/UC2, raw LZMA and additional ZIPX methods are
not enabled by this increment. G22 remains partial; support for these codecs
requires its own implementation and independent fixtures.
