# Archive and disk-image coverage

CrispCloud shares one format registry between pane navigation, F3, archive
search and extraction. A filename offers a reader; the reader validates the
actual container. Content signatures take priority over misleading suffixes.
Readable formats do not automatically acquire a writer.

## Capabilities

| Format | Browse / read / extract | Create / modify | Limits specific to this reader |
| --- | --- | --- | --- |
| ZIP | Yes | Existing reviewed ZIP policy | Supported methods and original encryption policy still apply. |
| ZIP packages | Yes | Read-only | JAR/WAR/EAR, WHL, APK/APKS/XAPK, IPA/AAB, XPI, NuGet, VSIX, CBZ, KMZ, APPX/MSIX and their bundles. Package signatures are not authenticated. |
| CRX | CRX2/CRX3 ZIP payload | Read-only | Header is bounded; publisher signature is not authenticated. |
| 7z / CB7 | Yes | `.7z` only, existing policy | CB7 is a read-only alias. |
| RAR / CBR | Existing reader | Read-only | Existing password and compression-method limits apply. |
| TAR / CBT | Yes | `.tar` only, existing policy | CBT is a read-only alias. |
| Compressed TAR | gzip, bzip2, xz, Zstandard | `.tar.gz` / `.tgz` only, existing policy | Includes TBZ/TBZ2/TXZ/TZST and `.tar.bzip2` / `.tar.zstd` aliases. |
| Compressed files | gzip, bzip2, xz, Zstandard | No new writer | `.gzip`, `.bzip2`, `.zstd` aliases; recognized nested archives open after bounded decompression. |
| ISO | ISO 9660, Joliet and ordinary Rock Ridge | Read-only | 2048-byte blocks. No UDF-only, multi-volume, multi-extent, interleaved, relocated Rock Ridge or zisofs images. |
| DMG | Unencrypted UDIF partitions and supported filesystems | Read-only | Single segment; raw, zero-fill, ignore, zlib and bzip2 chunks. No encrypted DMG, ADC, LZFSE or LZMA chunks, or binary-resource-fork-only images. |
| HFS+ / HFSX | Hierarchy and regular data forks | Read-only | Inline extents. No journal replay, compressed files, hard links, resource-fork extraction or overflow-extents reads. APFS file browsing is unavailable. |
| AR / DEB / UDEB / `.a` | Ordinary, GNU and BSD AR members | Read-only | Thin archives are refused; symbol indexes are omitted. DEB control/data members can be opened as nested archives. |
| CPIO | SVR4 newc and CRC | Read-only | No binary/odc or concatenated CPIO. Links, hard links and devices are not extracted. |
| XAR / PKG / XIP | XAR v1, stored/zlib/bzip2/xz members | Read-only | Present supported content checksums are checked. Publisher signatures are not authenticated. XIP's PBZX payload is a separate, undecoded member. |

Office and EPUB files retain their document/book viewers. No format in this
increment installs packages, executes members, mounts an image, writes a disk
filesystem or enables a new whole-container publication policy. Existing
ZIP/7z/TAR/TAR.GZ writes retain their captured-source and verified-publication
requirements in [archive endpoints](archive-endpoints.md).

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
Direct ISO/HFS/CPIO/XAR browsing retains the stricter shared namespace policy:
special entries or unsafe paths prevent entering/extracting that namespace;
F3 can show those records with reading disabled.

## Bounds and integrity

- Native pane sessions spool at most 2 GiB; browser pane sessions keep at most
  256 MiB in memory. These are input limits, not promised resident-memory use.
- Member reads are capped at 64 MiB. Direct whole-archive extraction keeps
  its 256 MiB input/total-output limits. Copying through a pane keeps its own
  operation planning and cancellation rules.
- Compression wrappers are bounded by 64 MiB input/output by default and
  four nested wrappers. Decompression checks integrity and truncation rather
  than accepting partial output. Actual member length must match metadata.
- ISO and HFS enforce 100,000 entries, 64 directory levels and 32 MiB of
  directory/catalog metadata. ISO also bounds continuation and pathname data.
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

No native runtime, subprocess packer or new dependency was added. The new
readers are original Dart implementations using the existing locked packages:
`koni_archive` 0.9.0 and its 0.9.0 codec/core packages (MIT), `archive` 4.6.0
(MIT), `xml` 6.6.1 (MIT) and `crypto` 3.0.7 (BSD-3-Clause). Check `pubspec.lock`
when updating these versions; dependency ranges are not a codec guarantee.

Primary references used for layout and validation:

- [ECMA-119 / ISO 9660](https://ecma-international.org/publications-and-standards/standards/ecma-119/).
- [Apple HFS Plus Volume Format, TN1150](https://developer.apple.com/library/archive/technotes/tn/tn1150.html).
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

UDF, APFS, CAB, RPM, ARJ/LZH/ACE/UC2, raw LZMA and additional ZIPX methods are
not enabled by this increment. G22 remains partial; support for these codecs
requires its own implementation and independent fixtures.
