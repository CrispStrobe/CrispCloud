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

import 'archive_dmg_reader.dart';
import 'archive_format_registry.dart';
import 'archive_hfs_reader.dart';
import 'archive_iso_reader.dart';
import 'archive_package_readers.dart';
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
      read: (member, limit) => archive.readMember(member, maxBytes: limit),
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
    final compression = _compressionMagic(header);
    if (compression != null) {
      if (depth >= 4) {
        throw const ArchiveViewException(
          'Too many nested compression wrappers.',
        );
      }
      if (source.length > maxBufferedContainerBytes) {
        throw ArchiveViewException(
          'This compression format requires a buffered decode limited to '
          '${_mb(maxBufferedContainerBytes)}.',
        );
      }
      final decompressed = decompressSingleFile(
        await source.read(0, source.length),
        'payload.$compression',
        maxBytes: maxMemberBytes,
      ).data;
      await source.close();
      final innerName = _innerContainerName(name);
      if (isArchiveFilename(innerName) || _hasContainerMagic(decompressed)) {
        return await _openSource(
          koni.MemoryByteSource(decompressed, name: innerName),
          name: innerName,
          password: password,
          maxMemberBytes: maxMemberBytes,
          maxBufferedContainerBytes: maxBufferedContainerBytes,
          depth: depth + 1,
        );
      }
      return ViewerArchive.direct(
        formatName: compression == 'gz'
            ? 'gzip'
            : compression == 'bz2'
            ? 'bzip2'
            : compression == 'zst'
            ? 'zstd'
            : compression,
        name: innerName,
        data: decompressed,
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
    if (_hasMagic(header, 0, const [48, 55, 48, 55, 48])) {
      return await openCpioArchive(source, maxMemberBytes: maxMemberBytes);
    }
    if (_hasMagic(header, 0, const [0x78, 0x61, 0x72, 0x21])) {
      return await openXarArchive(source, maxMemberBytes: maxMemberBytes);
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
  if (bytes.length >= 4 &&
      bytes[0] >= 0x50 &&
      bytes[0] <= 0x5f &&
      bytes[1] == 0x2a &&
      bytes[2] == 0x4d &&
      bytes[3] == 0x18) {
    return 'zst';
  }
  return null;
}

bool _hasContainerMagic(Uint8List bytes) =>
    _compressionMagic(bytes) != null ||
    looksLikeTar(bytes) ||
    _hasMagic(bytes, 0, const [0x50, 0x4b]) ||
    _hasMagic(bytes, 0, const [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]) ||
    _hasMagic(bytes, 0, const [0x52, 0x61, 0x72, 0x21]) ||
    _hasMagic(bytes, 0, const [0x21, 0x3c, 0x61, 0x72, 0x63, 0x68, 0x3e, 10]) ||
    _hasMagic(bytes, 0, const [48, 55, 48, 55, 48]) ||
    _hasMagic(bytes, 0, const [0x78, 0x61, 0x72, 0x21]) ||
    _hasMagic(bytes, 0, const [0x43, 0x72, 0x32, 0x34]) ||
    _hasMagic(bytes, 32769, const [0x43, 0x44, 0x30, 0x30, 0x31]) ||
    _hasMagic(bytes, bytes.length - 512, const [0x6b, 0x6f, 0x6c, 0x79]) ||
    (bytes.length >= 1026 && _isHfsMagic(bytes.sublist(1024, 1026)));

String _innerContainerName(String name) {
  name = name.replaceAll('\\', '/').split('/').last;
  final lower = name.toLowerCase();
  for (final alias in const ['.tgz', '.tbz2', '.tbz', '.txz', '.tzst']) {
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
  final lower = name.toLowerCase();
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
