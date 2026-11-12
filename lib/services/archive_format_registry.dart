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
      '.jar',
      '.war',
      '.ear',
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
      '.cbz',
      '.kmz',
      '.appx',
      '.appxbundle',
      '.msix',
      '.msixbundle',
    ],
    mimeType: 'application/zip',
    notes: 'Read-only package contents. Publisher signatures are not verified.',
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
  ),
  ArchiveFormatCapability(
    id: 'tar-xz',
    label: 'TAR + xz',
    suffixes: ['.tar.xz', '.txz'],
    mimeType: 'application/x-xz',
  ),
  ArchiveFormatCapability(
    id: 'tar-zstd',
    label: 'TAR + Zstandard',
    suffixes: ['.tar.zst', '.tar.zstd', '.tzst'],
    mimeType: 'application/zstd',
  ),
  ArchiveFormatCapability(
    id: 'gzip',
    label: 'gzip',
    suffixes: ['.gz', '.gzip'],
    mimeType: 'application/gzip',
    singleFileCompression: true,
  ),
  ArchiveFormatCapability(
    id: 'bzip2',
    label: 'bzip2',
    suffixes: ['.bz2', '.bzip2'],
    mimeType: 'application/x-bzip2',
    singleFileCompression: true,
  ),
  ArchiveFormatCapability(
    id: 'xz',
    label: 'xz',
    suffixes: ['.xz'],
    mimeType: 'application/x-xz',
    singleFileCompression: true,
  ),
  ArchiveFormatCapability(
    id: 'zstd',
    label: 'Zstandard',
    suffixes: ['.zst', '.zstd'],
    mimeType: 'application/zstd',
    singleFileCompression: true,
  ),
  ArchiveFormatCapability(
    id: 'iso',
    label: 'ISO 9660',
    suffixes: ['.iso'],
    mimeType: 'application/x-iso9660-image',
    notes: 'ISO 9660 and Joliet files. UDF-only images are not supported.',
  ),
  ArchiveFormatCapability(
    id: 'dmg',
    label: 'Apple disk image',
    suffixes: ['.dmg'],
    mimeType: 'application/x-apple-diskimage',
    notes:
        'Unencrypted UDIF images with raw, zero, zlib or bzip2 blocks. '
        'HFS+/HFSX data forks and partition images; APFS files are unavailable.',
  ),
  ArchiveFormatCapability(
    id: 'hfs',
    label: 'HFS+ image',
    suffixes: ['.hfs', '.hfsx'],
    mimeType: 'application/octet-stream',
    notes: 'HFS+/HFSX data forks with inline extents; no filesystem writes.',
  ),
  ArchiveFormatCapability(
    id: 'ar',
    label: 'AR / Debian package',
    suffixes: ['.ar', '.a', '.deb', '.udeb'],
    mimeType: 'application/x-archive',
    notes:
        'AR members, including nested control/data archives. No installation.',
  ),
  ArchiveFormatCapability(
    id: 'cpio',
    label: 'CPIO',
    suffixes: ['.cpio'],
    mimeType: 'application/x-cpio',
    notes:
        'newc and CRC variants. Links and special entries cannot be extracted.',
  ),
  ArchiveFormatCapability(
    id: 'xar',
    label: 'XAR package',
    suffixes: ['.xar', '.pkg', '.xip'],
    mimeType: 'application/x-xar',
    notes:
        'XAR members only. Publisher signatures are not verified; XIP PBZX '
        'payloads remain separate members.',
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
