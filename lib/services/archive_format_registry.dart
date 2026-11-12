/// Reader recognition shared by pane navigation, F3, search and extraction.
/// A suffix is a routing hint: each reader must validate the actual bytes.
/// Creation and modification remain governed by ArchiveEndpointPolicy.
class ArchiveFormatCapability {
  const ArchiveFormatCapability({
    required this.id,
    required this.label,
    required this.suffixes,
    required this.mimeType,
    this.canCreate = false,
    this.canModify = false,
    this.singleFileCompression = false,
    this.notes = '',
  });

  final String id;
  final String label;
  final List<String> suffixes;
  final String mimeType;
  final bool canCreate;
  final bool canModify;
  final bool singleFileCompression;
  final String notes;
}

const archiveFormatCapabilities = <ArchiveFormatCapability>[
  ArchiveFormatCapability(
    id: 'zip',
    label: 'ZIP',
    suffixes: ['.zip'],
    mimeType: 'application/zip',
    canCreate: true,
    canModify: true,
  ),
  ArchiveFormatCapability(
    id: 'zip-package',
    label: 'ZIP package',
    suffixes: [
      '.whl',
      '.apk',
      '.apks',
      '.xapk',
      '.ipa',
      '.aab',
      '.xpi',
      '.nupkg',
      '.snupkg',
      '.vsix',
      '.appx',
      '.appxbundle',
      '.msix',
      '.msixbundle',
    ],
    mimeType: 'application/zip',
    notes: 'Read-only package contents. Publisher signatures are not verified.',
  ),
  ArchiveFormatCapability(
    id: 'zip-alias',
    label: 'ZIP comic / map archive',
    suffixes: ['.cbz', '.kmz'],
    mimeType: 'application/zip',
    canCreate: true,
    canModify: true,
    notes: 'ZIP members. KMZ requires a KML document at its top level.',
  ),
  ArchiveFormatCapability(
    id: 'java-archive',
    label: 'Java archive',
    suffixes: ['.jar', '.war', '.ear'],
    mimeType: 'application/zip',
    canCreate: true,
    canModify: true,
    notes: 'Unsigned archive members can be edited. Signing records or manifest digests require a signing workflow. Publisher signatures are not verified.',
  ),
  ArchiveFormatCapability(
    id: 'crx',
    label: 'Chrome extension',
    suffixes: ['.crx'],
    mimeType: 'application/x-chrome-extension',
    notes: 'CRX2/CRX3 ZIP payload only. Publisher signatures are not verified.',
  ),
  ArchiveFormatCapability(
    id: '7z',
    label: '7-Zip',
    suffixes: ['.7z'],
    mimeType: 'application/x-7z-compressed',
    canCreate: true,
    canModify: true,
  ),
  ArchiveFormatCapability(
    id: '7z-alias',
    label: '7-Zip comic archive',
    suffixes: ['.cb7'],
    mimeType: 'application/x-7z-compressed',
    canCreate: true,
    canModify: true,
  ),
  ArchiveFormatCapability(
    id: 'rar',
    label: 'RAR',
    suffixes: ['.rar', '.cbr'],
    mimeType: 'application/vnd.rar',
  ),
  ArchiveFormatCapability(
    id: 'tar',
    label: 'TAR',
    suffixes: ['.tar'],
    mimeType: 'application/x-tar',
    canCreate: true,
    canModify: true,
  ),
  ArchiveFormatCapability(
    id: 'tar-alias',
    label: 'TAR comic archive',
    suffixes: ['.cbt'],
    mimeType: 'application/x-tar',
    canCreate: true,
    canModify: true,
  ),
  ArchiveFormatCapability(
    id: 'tar-gzip',
    label: 'TAR + gzip',
    suffixes: ['.tar.gz', '.tgz'],
    mimeType: 'application/gzip',
    canCreate: true,
    canModify: true,
  ),
  ArchiveFormatCapability(
    id: 'tar-bzip2',
    label: 'TAR + bzip2',
    suffixes: ['.tar.bz2', '.tar.bzip2', '.tbz2', '.tbz'],
    mimeType: 'application/x-bzip2',
    canCreate: true,
    canModify: true,
  ),
  ArchiveFormatCapability(
    id: 'tar-xz',
    label: 'TAR + xz',
    suffixes: ['.tar.xz', '.txz'],
    mimeType: 'application/x-xz',
    canCreate: true,
    canModify: true,
  ),
  ArchiveFormatCapability(
    id: 'tar-zstd',
    label: 'TAR + Zstandard',
    suffixes: ['.tar.zst', '.tar.zstd', '.tzst'],
    mimeType: 'application/zstd',
    canCreate: true,
    canModify: true,
  ),
  ArchiveFormatCapability(
    id: 'tar-lz4',
    label: 'TAR + LZ4',
    suffixes: ['.tar.lz4'],
    mimeType: 'application/x-lz4',
    canCreate: true,
    canModify: true,
    notes: 'Bounded TAR in modern LZ4 frames. Rewrite only eligible TAR metadata inside one frame without skippable extensions; new output includes block and content checksums.',
  ),
  ArchiveFormatCapability(
    id: 'tar-lzma',
    label: 'TAR + LZMA',
    suffixes: ['.tar.lzma', '.tlz'],
    mimeType: 'application/x-lzma',
    canCreate: true,
    canModify: true,
    notes: 'Bounded TAR in one strictly validated LZMA-alone stream. Recognized by filename; the format has no content checksum. Rewrite requires eligible TAR metadata.',
  ),
  ArchiveFormatCapability(
    id: 'tar-lzip',
    label: 'TAR + Lzip',
    suffixes: ['.tar.lz'],
    mimeType: 'application/x-lzip',
    notes: 'Read-only TAR in Lzip v1 members, with CRC32, size and exact framing checks. Dictionaries and decoded contents are limited to 64 MiB.',
  ),
  ArchiveFormatCapability(
    id: 'tar-compress',
    label: 'TAR + UNIX compress',
    suffixes: ['.tar.z', '.taz'],
    mimeType: 'application/x-compress',
    canCreate: true,
    canModify: true,
    notes: 'Bounded TAR in UNIX compress (.Z) streams. Rewrite requires eligible TAR metadata in one wrapper; output uses 14-bit block coding. The compression format has no content checksum or decoded length.',
  ),
  ArchiveFormatCapability(
    id: 'gzip',
    label: 'gzip',
    suffixes: ['.gz', '.gzip'],
    mimeType: 'application/gzip',
    canCreate: true,
    canModify: true,
    singleFileCompression: true,
  ),
  ArchiveFormatCapability(
    id: 'bzip2',
    label: 'bzip2',
    suffixes: ['.bz2', '.bzip2'],
    mimeType: 'application/x-bzip2',
    canCreate: true,
    canModify: true,
    singleFileCompression: true,
  ),
  ArchiveFormatCapability(
    id: 'xz',
    label: 'xz',
    suffixes: ['.xz'],
    mimeType: 'application/x-xz',
    canCreate: true,
    canModify: true,
    singleFileCompression: true,
  ),
  ArchiveFormatCapability(
    id: 'zstd',
    label: 'Zstandard',
    suffixes: ['.zst', '.zstd'],
    mimeType: 'application/zstd',
    canCreate: true,
    canModify: true,
    singleFileCompression: true,
  ),
  ArchiveFormatCapability(
    id: 'lz4',
    label: 'LZ4',
    suffixes: ['.lz4'],
    mimeType: 'application/x-lz4',
    canCreate: true,
    canModify: true,
    singleFileCompression: true,
    notes: 'Read modern independent/linked frames and verify present checksums. Edit one frame without skippable extensions; external dictionaries and legacy frames are unsupported. New output includes checksums.',
  ),
  ArchiveFormatCapability(
    id: 'lzma',
    label: 'LZMA-alone',
    suffixes: ['.lzma'],
    mimeType: 'application/x-lzma',
    canCreate: true,
    canModify: true,
    singleFileCompression: true,
    notes: 'Recognized by filename, with exact stream-boundary, dictionary and range-state checks. The format has no content checksum. Compressed/decoded contents and dictionaries are limited to 64 MiB.',
  ),
  ArchiveFormatCapability(
    id: 'lzip',
    label: 'Lzip',
    suffixes: ['.lz'],
    mimeType: 'application/x-lzip',
    singleFileCompression: true,
    notes: 'Read-only Lzip v1 with CRC32, decoded-size, member-size and end-marker checks. Consecutive nonempty members are supported; dictionaries and decoded contents are limited to 64 MiB.',
  ),
  ArchiveFormatCapability(
    id: 'compress',
    label: 'UNIX compress',
    suffixes: ['.z'],
    mimeType: 'application/x-compress',
    canCreate: true,
    canModify: true,
    singleFileCompression: true,
    notes: 'Bounded UNIX compress (.Z) streams. Create 12-, 14- or 16-bit block coding; replace only an immediate regular payload, rewritten with 14-bit block coding. The format has no content checksum or decoded length; compressed and decoded contents are limited to 64 MiB.',
  ),
  ArchiveFormatCapability(
    id: 'iso',
    label: 'ISO 9660',
    suffixes: ['.iso'],
    mimeType: 'application/x-iso9660-image',
    canCreate: true,
    canModify: true,
    notes: 'Create data ISO images with Rock Ridge and Joliet. Rewrite inspected data-only profiles; boot, hybrid and UDF images remain read-only.',
  ),
  ArchiveFormatCapability(
    id: 'dmg',
    label: 'Apple disk image',
    suffixes: ['.dmg'],
    mimeType: 'application/x-apple-diskimage',
    canCreate: true,
    notes:
        'Unencrypted UDIF images with raw, zero, zlib or bzip2 blocks. '
        'Create new HFSX data-volume DMGs. Existing images remain read-only; APFS files are unavailable.',
  ),
  ArchiveFormatCapability(
    id: 'hfs',
    label: 'HFS+ image',
    suffixes: ['.hfs', '.hfsx'],
    mimeType: 'application/octet-stream',
    canCreate: true,
    notes: 'Read HFS+/HFSX data forks; create new case-sensitive HFSX data images. Existing filesystem images remain read-only.',
  ),
  ArchiveFormatCapability(
    id: 'ar',
    label: 'AR archive',
    suffixes: ['.ar'],
    mimeType: 'application/x-archive',
    canCreate: true,
    canModify: true,
    notes: 'Flat regular members with ownership and timestamps. Symbol-indexed libraries require a linker/archive tool.',
  ),
  ArchiveFormatCapability(
    id: 'ar-library',
    label: 'Static object library',
    suffixes: ['.a'],
    mimeType: 'application/x-archive',
    notes: 'Read object members. Library symbol indexes require a linker/archive tool to rebuild.',
  ),
  ArchiveFormatCapability(
    id: 'deb',
    label: 'Debian package',
    suffixes: ['.deb', '.udeb'],
    mimeType: 'application/x-archive',
    canModify: true,
    notes: 'Validated replacement of existing ordered control/data payloads. Package checksums must remain consistent; no package installation or signing.',
  ),
  ArchiveFormatCapability(
    id: 'cpio',
    label: 'CPIO',
    suffixes: ['.cpio'],
    mimeType: 'application/x-cpio',
    canCreate: true,
    canModify: true,
    notes:
        'Read little/big-endian binary, odc, newc and CRC variants; create newc, odc or binary and rewrite inspected profiles without changing their layout. '
        'Links and special entries cannot be extracted.',
  ),
  ArchiveFormatCapability(
    id: 'rpm',
    label: 'RPM package',
    suffixes: ['.rpm'],
    mimeType: 'application/x-rpm',
    notes: 'Read classic RPM CPIO payloads with gzip, bzip2, XZ, Zstandard or no compression. Package scripts are never run; publisher signatures are not verified.',
  ),
  ArchiveFormatCapability(
    id: 'cab',
    label: 'Microsoft Cabinet',
    suffixes: ['.cab'],
    mimeType: 'application/vnd.ms-cab-compressed',
    notes: 'Read single-cabinet stored/MSZIP folders. Multi-cabinet files, Quantum and LZX are unavailable; cabinet signatures are not verified.',
  ),
  ArchiveFormatCapability(
    id: 'xar',
    label: 'XAR archive',
    suffixes: ['.xar'],
    mimeType: 'application/x-xar',
    canCreate: true,
    canModify: true,
    notes: 'Unsigned XAR members with inspected metadata, checksums and compression. Signed or unknown structures remain read-only.',
  ),
  ArchiveFormatCapability(
    id: 'xar-package',
    label: 'Apple package / XIP',
    suffixes: ['.pkg', '.xip'],
    mimeType: 'application/x-xar',
    notes: 'XAR package members; preview supported PBZX/CPIO Payload or Content members to browse their files. Publisher signatures are not verified; package metadata and signing require a dedicated workflow.',
  ),
  ArchiveFormatCapability(
    id: 'pbzx',
    label: 'Apple PBZX payload',
    suffixes: ['.pbzx'],
    mimeType: 'application/octet-stream',
    notes: 'Read stored/XZ block-compressed payloads and supported inner archives. Package signatures are not verified.',
  ),
];

/// The longest matching suffix wins, so .tar.gz is not a standalone .gz.
ArchiveFormatCapability? archiveFormatForName(String name) {
  final lower = name.toLowerCase();
  ArchiveFormatCapability? match;
  var length = 0;
  for (final format in archiveFormatCapabilities) {
    for (final suffix in format.suffixes) {
      if (suffix.length > length && lower.endsWith(suffix)) {
        match = format;
        length = suffix.length;
      }
    }
  }
  return match;
}

bool isArchiveFilename(String name) => archiveFormatForName(name) != null;

/// Recognizes virtual member routes without a second extension allowlist.
bool isArchiveVirtualPath(String path) {
  var cursor = 0;
  while (true) {
    final separator = path.indexOf(':/', cursor);
    if (separator < 0) return false;
    if (isArchiveFilename(path.substring(0, separator))) return true;
    cursor = separator + 2;
  }
}
