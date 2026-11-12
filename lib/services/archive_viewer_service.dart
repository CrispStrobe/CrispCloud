// lib/services/archive_viewer_service.dart
//
// Archive reading for the F3 viewer, built on two MIT/BSD-licensed pure-Dart
// libraries:
//
//  * package:koni_archive — ZIP, TAR, GZIP (incl. .tar.gz), 7z and RAR.
//    Metadata-only open, streaming reads with a per-entry size cap
//    (decompression-bomb protection), sanitized entry paths, checksum
//    verification, and password support (ZIP/7z/RAR4/RAR5).
//  * package:archive — bounded decompression for bzip2 / xz / zstd
//    containers (`.tar.bz2`, `.tbz2`, `.tar.xz`, `.tar.zst`, …) and
//    single-file `.gz`/`.bz2`/`.xz`/`.zst` expansion. Every decode passes
//    `maxOutputSize`, so a compression bomb fails with an error instead of
//    exhausting memory.
//
// Neither library is GPL; both are permissive (koni_archive: MIT,
// archive: MIT). No native code, no FFI, works on Flutter web too.

import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_cab_reader.dart';
import 'archive_dmg_reader.dart';
import 'archive_format_registry.dart';
import 'archive_hfs_reader.dart';
import 'archive_iso_reader.dart';
import 'archive_lz4_codec.dart';
import 'archive_lzma_codec.dart';
import 'archive_lzip_codec.dart';
import 'archive_unix_compress_codec.dart';
import 'archive_package_readers.dart';
import 'archive_pbzx_source.dart';
import 'archive_rpm_reader.dart';
import 'archive_slice_source.dart';
import 'archive_types.dart';

export 'archive_types.dart';

/// Open [bytes] as an archive.
///
/// Throws [ArchivePasswordRequiredException] for encrypted archives and
/// [ArchiveViewException] for unsupported/corrupt/oversized input.
Future<ViewerArchive> openViewerArchive(
  Uint8List bytes, {
  required String name,
  String? password,
  int maxMemberBytes = kArchiveReadLimit,
}) => openViewerArchiveSource(
  koni.MemoryByteSource(bytes, name: name),
  name: name,
  password: password,
  maxMemberBytes: maxMemberBytes,
);

/// Opens an owned random-access source without retaining a full input buffer.
/// The returned handle owns [source] and closes it on failure or on close.
/// Package-only compression formats still require a bounded container decode.
Future<ViewerArchive> openViewerArchiveSource(
  koni.ByteSource source, {
  required String name,
  String? password,
  int maxMemberBytes = kArchiveReadLimit,
  int maxBufferedContainerBytes = kArchiveReadLimit,
}) async {
  try {
    if (maxMemberBytes <= 0 || maxBufferedContainerBytes <= 0) {
      throw ArgumentError('Archive limits must be positive.');
    }
    final archive = await _openSource(
      source,
      name: name,
      password: password,
      maxMemberBytes: maxMemberBytes,
      maxBufferedContainerBytes: maxBufferedContainerBytes,
      depth: 0,
    );
    final note = archiveFormatForName(name)?.notes ?? '';
    if (note.isEmpty) return archive;
    return ViewerArchive.reader(
      formatName: archive.formatName,
      members: archive.members,
      notices: [note, ...archive.notices],
      isDirectCompressionPayload: archive.isDirectCompressionPayload,
      read: (member, limit) => archive.readMember(member, maxBytes: limit),
      streamReader: (member, chunkSize) => archive.openMember(
        member,
        maxBytes: maxMemberBytes,
        chunkSize: chunkSize,
      ),
      close: archive.close,
    );
  } catch (_) {
    await source.close();
    rethrow;
  }
}

Future<ViewerArchive> _openSource(
  koni.ByteSource source, {
  required String name,
  String? password,
  required int maxMemberBytes,
  required int maxBufferedContainerBytes,
  required int depth,
}) async {
  try {
    if (depth > 4) {
      throw const ArchiveViewException('Too many nested compression wrappers.');
    }
    final header = await source.read(
      0,
      source.length < 512 ? source.length : 512,
    );
    // UDIF block payloads can themselves begin with BZh or another codec
    // signature. Its validated trailer must win over stream sniffing.
    if (source.length >= 512 &&
        _hasMagic(await source.read(source.length - 512, 4), 0, const [
          0x6b,
          0x6f,
          0x6c,
          0x79,
        ])) {
      return await openDmgArchive(source, maxMemberBytes: maxMemberBytes);
    }
    if (_hasMagic(header, 0, const [0x70, 0x62, 0x7a, 0x78])) {
      if (depth >= 4) {
        throw const ArchiveViewException(
          'Too many nested compression wrappers.',
        );
      }
      final innerName = _innerContainerName(name);
      final decoded = await ArchivePbzxSource.open(source, name: innerName);
      try {
        final innerHeader = await decoded.read(
          0,
          decoded.length < 512 ? decoded.length : 512,
        );
        if (isArchiveFilename(innerName) || _hasContainerMagic(innerHeader)) {
          final inner = await _openSource(
            decoded,
            name: innerName,
            password: password,
            maxMemberBytes: maxMemberBytes,
            maxBufferedContainerBytes: maxBufferedContainerBytes,
            depth: depth + 1,
          );
          return ViewerArchive.reader(
            formatName: 'pbzx/${inner.formatName}',
            members: inner.members,
            notices: [_pbzxNotice, ...inner.notices],
            read: (member, limit) => inner.readMember(member, maxBytes: limit),
            streamReader: (member, chunkSize) => inner.openMember(
              member,
              maxBytes: maxMemberBytes,
              chunkSize: chunkSize,
            ),
            close: inner.close,
          );
        }
        final member = ViewerArchiveMember(
          name: innerName,
          size: decoded.length,
          isFile: true,
          isEncrypted: false,
          pathEscapedRoot: false,
          index: 0,
        );
        return ViewerArchive.reader(
          formatName: 'pbzx',
          members: [member],
          notices: [_pbzxNotice],
          read: (member, limit) async {
            if (member.size > maxMemberBytes) {
              throw const ArchiveViewException(
                'PBZX payload exceeds the member read limit.',
              );
            }
            return decoded.read(0, member.size);
          },
          close: decoded.close,
        );
      } catch (_) {
        await decoded.close();
        rethrow;
      }
    }
    final compression = await _compressionForSource(source, header);
    if (compression != null) {
      return await _openCompressedSource(
        source,
        compression: compression,
        name: name,
        password: password,
        maxMemberBytes: maxMemberBytes,
        maxBufferedContainerBytes: maxBufferedContainerBytes,
        depth: depth,
      );
    }
    if (_hasMagic(header, 0, const [
          0x21,
          0x3c,
          0x61,
          0x72,
          0x63,
          0x68,
          0x3e,
          10,
        ]) ||
        _hasMagic(header, 0, const [
          0x21,
          0x3c,
          0x74,
          0x68,
          0x69,
          0x6e,
          0x3e,
          10,
        ])) {
      return await openArArchive(source, maxMemberBytes: maxMemberBytes);
    }
    if (_hasMagic(header, 0, const [48, 55, 48, 55, 48]) ||
        _hasMagic(header, 0, const [0xc7, 0x71]) ||
        _hasMagic(header, 0, const [0x71, 0xc7])) {
      return await openCpioArchive(source, maxMemberBytes: maxMemberBytes);
    }
    if (_hasMagic(header, 0, const [0x78, 0x61, 0x72, 0x21])) {
      return await openXarArchive(source, maxMemberBytes: maxMemberBytes);
    }
    if (_hasMagic(header, 0, const [0xed, 0xab, 0xee, 0xdb])) {
      return await openRpmArchive(
        source,
        maxMemberBytes: maxMemberBytes,
        maxBufferedContainerBytes: maxBufferedContainerBytes,
      );
    }
    if (_hasMagic(header, 0, const [0x4d, 0x53, 0x43, 0x46])) {
      return await openCabArchive(
        source,
        maxMemberBytes: maxMemberBytes,
        maxFolderBytes: maxBufferedContainerBytes,
      );
    }
    if (_hasMagic(header, 0, const [0x43, 0x72, 0x32, 0x34])) {
      if (header.length < 16) {
        throw const ArchiveViewException('Truncated CRX header.');
      }
      final data = ByteData.sublistView(header);
      final version = data.getUint32(4, Endian.little);
      final int offset;
      if (version == 2) {
        offset =
            16 +
            data.getUint32(8, Endian.little) +
            data.getUint32(12, Endian.little);
      } else if (version == 3) {
        offset = 12 + data.getUint32(8, Endian.little);
      } else {
        throw const ArchiveViewException(
          'Only CRX2 and CRX3 containers are supported.',
        );
      }
      if (offset > 16 * 1024 * 1024 || offset > source.length - 4) {
        throw const ArchiveViewException('Invalid or oversized CRX header.');
      }
      final payload = ArchiveSliceSource(
        source,
        offset: offset,
        length: source.length - offset,
        name: 'extension.zip',
      );
      if (!_hasMagic(await payload.read(0, 2), 0, const [0x50, 0x4b])) {
        throw const ArchiveViewException(
          'The CRX payload is not a ZIP archive.',
        );
      }
      return await _openWithKoni(
        payload,
        password: password,
        maxMemberBytes: maxMemberBytes,
      );
    }
    // Ordinary archive signatures take priority over misleading filenames.
    if (_hasMagic(header, 0, const [0x50, 0x4b]) ||
        _hasMagic(header, 0, const [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]) ||
        _hasMagic(header, 0, const [0x52, 0x61, 0x72, 0x21]) ||
        looksLikeTar(header)) {
      return await _openWithKoni(
        source,
        password: password,
        maxMemberBytes: maxMemberBytes,
      );
    }
    // Filesystem signatures also win over misleading container suffixes.
    if (source.length >= 32774 &&
        _hasMagic(await source.read(32769, 5), 0, const [
          0x43,
          0x44,
          0x30,
          0x30,
          0x31,
        ])) {
      return await openIsoArchive(source, maxMemberBytes: maxMemberBytes);
    }
    if (source.length >= 1026 && _isHfsMagic(await source.read(1024, 2))) {
      return await openHfsArchive(source, maxMemberBytes: maxMemberBytes);
    }
    final lower = name.toLowerCase();
    if (lower.endsWith('.dmg')) {
      return await openDmgArchive(source, maxMemberBytes: maxMemberBytes);
    }
    if (lower.endsWith('.iso')) {
      return await openIsoArchive(source, maxMemberBytes: maxMemberBytes);
    }
    if (lower.endsWith('.hfs') || lower.endsWith('.hfsx')) {
      return await openHfsArchive(source, maxMemberBytes: maxMemberBytes);
    }
    // LZMA-alone has no unique magic. Route an explicit suffix only after
    // every recognized archive/filesystem signature has had priority.
    if (lower.endsWith('.lzma') || lower.endsWith('.tlz')) {
      return await _openCompressedSource(
        source,
        compression: 'lzma',
        name: name,
        password: password,
        maxMemberBytes: maxMemberBytes,
        maxBufferedContainerBytes: maxBufferedContainerBytes,
        depth: depth,
      );
    }
    return await _openWithKoni(
      source,
      password: password,
      maxMemberBytes: maxMemberBytes,
    );
  } catch (_) {
    await source.close();
    rethrow;
  }
}

Future<ViewerArchive> _openCompressedSource(
  koni.ByteSource source, {
  required String compression,
  required String name,
  required String? password,
  required int maxMemberBytes,
  required int maxBufferedContainerBytes,
  required int depth,
}) async {
  if (depth >= 4) {
    throw const ArchiveViewException('Too many nested compression wrappers.');
  }
  if (source.length > maxBufferedContainerBytes) {
    throw ArchiveViewException(
      'This compression format requires a buffered decode limited to ${_mb(maxBufferedContainerBytes)}.',
    );
  }
  final input = await source.read(0, source.length);
  final notices = <String>[];
  final Uint8List decompressed;
  if (compression == 'lz4') {
    final decoded = decodeArchiveLz4(
      input,
      maxOutputBytes: maxMemberBytes < kArchiveReadLimit
          ? maxMemberBytes
          : kArchiveReadLimit,
    );
    decompressed = decoded.bytes;
    notices.add(
      'LZ4 frame headers and all present block/content checksums were checked. Frames without optional content checksums do not provide a stored whole-payload digest.',
    );
    if (!decoded.canRewrite) {
      notices.add(
        'This LZ4 frame collection or skippable extension metadata is read-only; a one-frame rewrite would discard its framing.',
      );
    }
  } else {
    decompressed = decompressSingleFile(
      input,
      'payload.$compression',
      maxBytes: maxMemberBytes,
    ).data;
    if (compression == 'lzma') {
      notices.add(
        'LZMA-alone has no stored content checksum. Stream boundaries, decoded size, dictionary distances and range-coder completion were checked.',
      );
    } else if (compression == 'lz') {
      notices.add(
        'Lzip member CRC32, decoded lengths and complete stream boundaries were checked. Lzip is read-only.',
      );
    } else if (compression == 'z') {
      notices.add(
        'UNIX compress has no stored checksum or decoded length. Successful LZW decoding cannot detect every bit change or truncation at a valid code boundary. This format is read-only.',
      );
    }
  }
  await source.close();
  final innerName = _innerContainerName(name);
  if (isArchiveFilename(innerName) || _hasContainerMagic(decompressed)) {
    final inner = await _openSource(
      koni.MemoryByteSource(decompressed, name: innerName),
      name: innerName,
      password: password,
      maxMemberBytes: maxMemberBytes,
      maxBufferedContainerBytes: maxBufferedContainerBytes,
      depth: depth + 1,
    );
    return ViewerArchive.reader(
      formatName: inner.formatName,
      members: inner.members,
      notices: [...notices, ...inner.notices],
      read: (member, limit) => inner.readMember(member, maxBytes: limit),
      streamReader: (member, chunkSize) => inner.openMember(
        member,
        maxBytes: maxMemberBytes,
        chunkSize: chunkSize,
      ),
      close: inner.close,
    );
  }
  return ViewerArchive.direct(
    formatName: switch (compression) {
      'gz' => 'gzip',
      'bz2' => 'bzip2',
      'zst' => 'zstd',
      'lz' => 'lzip',
      'z' => 'compress',
      _ => compression,
    },
    name: innerName,
    data: decompressed,
    notices: notices,
  );
}

bool _isSkippableFrame(List<int> bytes) =>
    bytes.length >= 4 &&
    bytes[0] >= 0x50 &&
    bytes[0] <= 0x5f &&
    bytes[1] == 0x2a &&
    bytes[2] == 0x4d &&
    bytes[3] == 0x18;

/// LZ4 and Zstandard share skippable-frame magic. Follow bounded metadata to
/// the first actual data frame rather than choosing the wrong codec by suffix.
Future<String?> _compressionForSource(
  koni.ByteSource source,
  Uint8List header,
) async {
  if (!_isSkippableFrame(header)) return _compressionMagic(header);
  var offset = 0, frames = 0;
  while (offset < source.length) {
    if (++frames > 4096 || source.length - offset < 8) {
      throw const ArchiveViewException(
        'Invalid or excessive skippable compression frames.',
      );
    }
    final prefix = await source.read(offset, 8);
    if (!_isSkippableFrame(prefix)) {
      final compression = _compressionMagic(prefix);
      if (compression == 'lz4' || compression == 'zst') return compression;
      throw const ArchiveViewException(
        'Skippable frames must precede a supported LZ4 or Zstandard data frame.',
      );
    }
    final size = ByteData.sublistView(prefix).getUint32(4, Endian.little);
    if (size > source.length - offset - 8) {
      throw const ArchiveViewException(
        'Truncated skippable compression frame.',
      );
    }
    offset += 8 + size;
  }
  throw const ArchiveViewException('Compression input contains no data frame.');
}

bool _hasMagic(List<int> bytes, int offset, List<int> magic) {
  if (offset < 0 || offset + magic.length > bytes.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[offset + i] != magic[i]) return false;
  }
  return true;
}

bool _isHfsMagic(List<int> bytes) =>
    bytes.length >= 2 &&
    bytes[0] == 0x48 &&
    (bytes[1] == 0x2b || bytes[1] == 0x58);

String? _compressionMagic(List<int> bytes) {
  if (_hasMagic(bytes, 0, const [0x1f, 0x8b])) return 'gz';
  if (_hasMagic(bytes, 0, const [0x42, 0x5a, 0x68])) return 'bz2';
  if (_hasMagic(bytes, 0, const [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0])) return 'xz';
  if (_hasMagic(bytes, 0, const [0x28, 0xb5, 0x2f, 0xfd])) return 'zst';
  if (_hasMagic(bytes, 0, const [0x04, 0x22, 0x4d, 0x18])) return 'lz4';
  if (_hasMagic(bytes, 0, const [0x4c, 0x5a, 0x49, 0x50])) return 'lz';
  if (_hasMagic(bytes, 0, const [0x1f, 0x9d])) return 'z';
  return null;
}

bool _hasContainerMagic(Uint8List bytes) =>
    _compressionMagic(bytes) != null ||
    _isSkippableFrame(bytes) ||
    _hasMagic(bytes, 0, const [0x70, 0x62, 0x7a, 0x78]) ||
    _hasMagic(bytes, 0, const [0xed, 0xab, 0xee, 0xdb]) ||
    _hasMagic(bytes, 0, const [0x4d, 0x53, 0x43, 0x46]) ||
    looksLikeTar(bytes) ||
    _hasMagic(bytes, 0, const [0x50, 0x4b]) ||
    _hasMagic(bytes, 0, const [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]) ||
    _hasMagic(bytes, 0, const [0x52, 0x61, 0x72, 0x21]) ||
    _hasMagic(bytes, 0, const [0x21, 0x3c, 0x61, 0x72, 0x63, 0x68, 0x3e, 10]) ||
    _hasMagic(bytes, 0, const [48, 55, 48, 55, 48]) ||
    _hasMagic(bytes, 0, const [0xc7, 0x71]) ||
    _hasMagic(bytes, 0, const [0x71, 0xc7]) ||
    _hasMagic(bytes, 0, const [0x78, 0x61, 0x72, 0x21]) ||
    _hasMagic(bytes, 0, const [0x43, 0x72, 0x32, 0x34]) ||
    _hasMagic(bytes, 32769, const [0x43, 0x44, 0x30, 0x30, 0x31]) ||
    _hasMagic(bytes, bytes.length - 512, const [0x6b, 0x6f, 0x6c, 0x79]) ||
    (bytes.length >= 1026 && _isHfsMagic(bytes.sublist(1024, 1026)));

String _innerContainerName(String name) {
  name = name.replaceAll('\\', '/').split('/').last;
  final lower = name.toLowerCase();
  for (final alias in const [
    '.tgz',
    '.tbz2',
    '.tbz',
    '.txz',
    '.tzst',
    '.tlz',
    '.taz',
  ]) {
    if (lower.endsWith(alias)) {
      return '${name.substring(0, name.length - alias.length)}.tar';
    }
  }
  final stripped = stripCompressionSuffix(name);
  return stripped == name ? '$name.uncompressed' : stripped;
}

Future<ViewerArchive> _openWithKoni(
  koni.ByteSource source, {
  String? password,
  required int maxMemberBytes,
}) async {
  koni.ArchiveReader reader;
  try {
    // Use the reader directly (not the Archive facade): a reader may throw
    // synchronously from openRead() for encrypted/unsupported entries, and
    // the facade's stream wrapper turns that into an unclosed stream (hang).
    reader = await koni.builtInFormats.openReader(
      source,
      options: koni.ArchiveReadOptions(
        password: password,
        maxEntrySize: maxMemberBytes,
        maxEntryCount: 200000,
        maxContainerDecodeSize: maxMemberBytes,
      ),
    );
  } on koni.EncryptedArchiveException catch (e) {
    await source.close();
    throw ArchivePasswordRequiredException(
      'This archive is encrypted.',
      code: ArchiveMessageCode.archiveEncrypted,
      wrongPassword: password != null || e is koni.InvalidPasswordException,
    );
  } on koni.SizeLimitExceededException catch (e) {
    await source.close();
    throw ArchiveViewException(
      'The archive expands beyond the ${_mb(maxMemberBytes)} safety limit '
      '(${e.message}).',
      code: ArchiveMessageCode.archiveLimit,
      arguments: {'limit': _mb(maxMemberBytes), 'detail': e.message},
    );
  } on koni.ArchiveException catch (e) {
    await source.close();
    throw ArchiveViewException(
      'Unsupported or corrupt archive: ${e.message}',
      code: ArchiveMessageCode.corrupt,
      arguments: {'detail': e.message},
    );
  } catch (e) {
    await source.close();
    throw ArchiveViewException(
      'Unsupported or corrupt archive: $e',
      code: ArchiveMessageCode.corrupt,
      arguments: {'detail': e},
    );
  }

  final entries = reader.entries;
  final members = <ViewerArchiveMember>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    members.add(
      ViewerArchiveMember(
        name: entry.path.isEmpty ? '/' : entry.path,
        size: entry.uncompressedSize,
        isFile: entry.isFile,
        isEncrypted: entry.isEncrypted,
        isSpecial: !entry.isFile && !entry.isDirectory,
        modified: entry.modified,
        posixMode: entry.posixMode,
        pathEscapedRoot: entry.pathEscapedRoot,
        index: i,
      ),
    );
  }

  return ViewerArchive.reader(
    formatName: reader.format.name,
    members: List<ViewerArchiveMember>.unmodifiable(members),
    read: (member, requestedCap) async {
      final limit = requestedCap < maxMemberBytes
          ? requestedCap
          : maxMemberBytes;
      final entry = entries[member.index];
      if (entry.isEncrypted && password == null) {
        throw const ArchivePasswordRequiredException(
          'This entry is encrypted.',
        );
      }
      final builder = BytesBuilder(copy: false);
      try {
        final stream = reader.openRead(entry); // may throw synchronously
        await for (final chunk in stream) {
          if (builder.length + chunk.length > limit) {
            throw ArchiveViewException(
              'The entry is larger than the ${_mb(limit)} safety limit.',
              code: ArchiveMessageCode.entryLimit,
              arguments: {'limit': _mb(limit)},
            );
          }
          builder.add(chunk);
        }
      } on ArchiveViewException {
        rethrow;
      } on koni.EncryptedArchiveException catch (e) {
        throw ArchivePasswordRequiredException(
          'This entry is encrypted.',
          code: ArchiveMessageCode.entryEncrypted,
          wrongPassword: password != null || e is koni.InvalidPasswordException,
        );
      } on koni.SizeLimitExceededException catch (e) {
        throw ArchiveViewException(
          'The entry is larger than the ${_mb(limit)} safety limit '
          '(${e.message}).',
          code: ArchiveMessageCode.entryLimitDetail,
          arguments: {'limit': _mb(limit), 'detail': e.message},
        );
      } on koni.ArchiveException catch (e) {
        if (entry.isEncrypted) {
          // 7z has no password check: a wrong password shows up as corrupt
          // data or a checksum mismatch.
          throw const ArchivePasswordRequiredException(
            'The password is wrong or the entry is corrupt.',
            code: ArchiveMessageCode.wrongOrCorrupt,
            wrongPassword: true,
          );
        }
        throw ArchiveViewException(
          'Could not read entry: ${e.message}',
          code: ArchiveMessageCode.readEntry,
          arguments: {'detail': e.message},
        );
      } catch (e) {
        throw ArchiveViewException(
          'Could not read entry: $e',
          code: ArchiveMessageCode.readEntry,
          arguments: {'detail': e},
        );
      }
      return builder.takeBytes();
    },
    close: () async {
      try {
        await reader.close();
      } finally {
        await source.close();
      }
    },
  );
}

// ---------------------------------------------------------------------------
// Single-file compression
// ---------------------------------------------------------------------------

/// Whether [name] is a single-file compression (not a tar container):
/// `.gz`, `.bz2`, `.xz`, `.zst` — used to auto-expand on open.
bool isSingleCompressedFile(String name) =>
    archiveFormatForName(name)?.singleFileCompression ?? false;

/// Remove a single compression suffix (`.gz`, `.bz2`, `.xz`, `.zst`).
String stripCompressionSuffix(String name) {
  final lower = name.toLowerCase();
  for (final suffix in const [
    '.pbzx',
    '.lzma',
    '.lz4',
    '.lz',
    '.z',
    '.gzip',
    '.bzip2',
    '.zstd',
    '.gz',
    '.bz2',
    '.xz',
    '.zst',
  ]) {
    if (lower.endsWith(suffix)) {
      return name.substring(0, name.length - suffix.length);
    }
  }
  return name;
}

/// Decompress a single-file `.gz`/`.bz2`/`.xz`/`.zst` payload, bounded by
/// [maxBytes] so compression bombs cannot exhaust memory.
({Uint8List data, String innerName}) decompressSingleFile(
  Uint8List bytes,
  String name, {
  int maxBytes = kArchiveReadLimit,
}) {
  var lower = name.toLowerCase();
  final boundedCodecLimit = maxBytes < kArchiveReadLimit
      ? maxBytes
      : kArchiveReadLimit;
  // A real framing signature wins over a misleading compression extension.
  // LZMA-alone remains suffix-routed because it has no unique magic.
  var signature = bytes;
  var frames = 0;
  while (_isSkippableFrame(signature)) {
    if (++frames > 4096 || signature.length < 8) {
      throw const ArchiveViewException(
        'Invalid or excessive skippable compression frames.',
      );
    }
    final length = ByteData.sublistView(signature).getUint32(4, Endian.little);
    if (length > signature.length - 8) {
      throw const ArchiveViewException(
        'Truncated skippable compression frame.',
      );
    }
    signature = Uint8List.sublistView(signature, 8 + length);
  }
  final detected = _compressionMagic(signature);
  if (detected != null) lower = 'payload.$detected';
  final Uint8List data;
  try {
    if (lower.endsWith('.gz') || lower.endsWith('.gzip')) {
      data = const ar.GZipDecoder().decodeBytes(
        bytes,
        verify: true,
        maxOutputSize: maxBytes,
      );
    } else if (lower.endsWith('.bz2') ||
        lower.endsWith('.bzip2') ||
        lower.endsWith('.tbz2') ||
        lower.endsWith('.tbz')) {
      data = ar.BZip2Decoder().decodeBytes(
        bytes,
        verify: true,
        maxOutputSize: maxBytes,
      );
    } else if (lower.endsWith('.xz') || lower.endsWith('.txz')) {
      data = ar.XZDecoder().decodeBytes(
        bytes,
        verify: true,
        maxOutputSize: maxBytes,
      );
    } else if (lower.endsWith('.lzma') || lower.endsWith('.tlz')) {
      data = decodeArchiveLzma(bytes, maxOutputBytes: boundedCodecLimit);
    } else if (lower.endsWith('.lz4')) {
      data = decodeArchiveLz4(bytes, maxOutputBytes: boundedCodecLimit).bytes;
    } else if (lower.endsWith('.lz')) {
      data = decodeArchiveLzip(bytes, maxOutputBytes: boundedCodecLimit);
    } else if (lower.endsWith('.z') || lower.endsWith('.taz')) {
      data = decodeArchiveUnixCompress(
        bytes,
        maxOutputBytes: boundedCodecLimit,
      );
    } else if (lower.endsWith('.zst') ||
        lower.endsWith('.zstd') ||
        lower.endsWith('.tzst')) {
      data = ar.ZstdDecoder().decodeBytes(
        bytes,
        verify: true,
        maxOutputSize: maxBytes,
      );
    } else {
      throw ArchiveViewException(
        'Not a single-file compressed format: $name',
        code: ArchiveMessageCode.singleFormat,
        arguments: {'name': name},
      );
    }
  } on ArchiveViewException {
    rethrow;
  } catch (e) {
    throw ArchiveViewException(
      'Could not decompress $name (it may be corrupt or larger than the '
      '${_mb(maxBytes)} safety limit): $e',
      code: ArchiveMessageCode.decompressFile,
      arguments: {'name': name, 'limit': _mb(maxBytes), 'detail': e},
    );
  }
  return (data: data, innerName: stripCompressionSuffix(name));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// True when the buffer starts with the POSIX tar magic at offset 257.
bool looksLikeTar(Uint8List data) {
  if (data.length < 262) return false;
  return data[257] == 0x75 && // u
      data[258] == 0x73 && // s
      data[259] == 0x74 && // t
      data[260] == 0x61 && // a
      data[261] == 0x72; // r
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

const _pbzxNotice =
    'PBZX is read-only. Stored/XZ chunks are decoded on demand (16 MiB per '
    'chunk, 2 GiB logical payload); member reads retain their existing limit. '
    'Present XZ integrity checks are verified for chunks read; stored chunks '
    'and XZ CHECK_NONE streams have no data checksum. '
    'Package signatures are not verified. Unsupported inner formats are '
    'exposed as one decoded payload.';
