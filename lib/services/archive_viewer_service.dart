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
import 'archive_rar_metadata_reader.dart';
import 'archive_sevenz_byte_reader.dart';
import 'archive_sevenz_metadata.dart' show SevenZId, readSevenZipNumber;
import 'archive_sfx_source.dart';
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
    // Intercept PE files before any generic ZIP fallback. A ZIP self-extractor
    // retains executable offsets; treating it as an ordinary ZIP could later
    // authorize a rewrite that silently discards its executable prefix.
    if (_hasMagic(header, 0, const [0x4d, 0x5a])) {
      final payload = await openPeSfxSource(source);
      final inner = await _openWithKoni(
        payload,
        password: password,
        maxMemberBytes: maxMemberBytes,
      );
      if (inner.formatName != payload.archiveKind) {
        await inner.close();
        throw const ArchiveViewException(
          'The executable archive payload does not match its inspected format.',
        );
      }
      return ViewerArchive.reader(
        formatName: 'sfx/${inner.formatName}',
        members: inner.members,
        notices: [...ArchiveSfxSource.notices, ...inner.notices],
        read: (member, limit) => inner.readMember(member, maxBytes: limit),
        streamReader: (member, chunkSize) => inner.openMember(
          member,
          maxBytes: maxMemberBytes,
          chunkSize: chunkSize,
        ),
        close: inner.close,
      );
    }
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
        'UNIX compress has no stored checksum or decoded length. Successful LZW decoding cannot detect every bit change or truncation at a valid code boundary. Eligible rewrites use 14-bit block coding.',
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

// The pinned 7z fallback allocates ciphertext and intermediate coder buffers,
// not just the final folder output. Its own maxContainerDecodeSize check does
// not cover those allocations. Inspect both public and decoded headers before
// passing immutable metadata to that reader. Native streamed 7z has a separate
// decoder and never enters this bounded fallback.
const _sevenZipFallbackInputLimit = 256 * 1024 * 1024;
const _sevenZipFallbackHeaderLimit = 16 * 1024 * 1024;
const _sevenZipFallbackCountLimit = 200000;

Never _sevenZipResourceLimit(String detail, int limit) =>
    throw ArchiveViewException(
      '7z bounded fallback refuses $detail above ${_mb(limit)}.',
      code: ArchiveMessageCode.archiveLimit,
      arguments: {'limit': _mb(limit), 'detail': detail},
    );

Never _sevenZipInvalid(String detail) =>
    throw koni.InvalidHeaderException(detail, format: '7z');

class _SevenZipFolderBudget {
  _SevenZipFolderBudget(this.outputs, this.finalOutput, this.packedInputs);
  final int outputs, finalOutput, packedInputs;
  int size = 0, substreams = 1;
  bool hasCrc = false;
}

/// A resource scan, not a replacement content/CRC decoder. The same scanner
/// checks the encoded-header stream table and the eventual main stream table.
class _SevenZipResourceScanner {
  _SevenZipResourceScanner(this.reader, this.sourceLength, this.limit);
  final ByteReader reader;
  final int sourceLength, limit;
  int _coders = 0, _graphStreams = 0;
  int number() => readSevenZipNumber(reader);

  int count(String label, [int maximum = _sevenZipFallbackCountLimit]) {
    final value = number();
    if (value > maximum) {
      throw ArchiveViewException(
        '7z bounded metadata supports at most $maximum $label.',
      );
    }
    if (value > reader.remaining) {
      _sevenZipInvalid('7z $label does not fit its metadata.');
    }
    return value;
  }

  void digests(int count, {void Function(int, bool)? onDefined}) {
    final all = reader.readUint8();
    final bits = all == 0 ? reader.readBytes((count + 7) ~/ 8) : null;
    var defined = 0;
    for (var i = 0; i < count; i++) {
      final present = bits == null || bits[i ~/ 8] & (0x80 >> (i % 8)) != 0;
      if (present) defined++;
      onDefined?.call(i, present);
    }
    reader.skip(defined * 4);
  }

  _SevenZipFolderBudget folder() {
    final coderCount = count('coder count', 64);
    if (coderCount == 0) _sevenZipInvalid('A 7z folder has no coders.');
    if ((_coders += coderCount) > _sevenZipFallbackCountLimit) {
      throw const ArchiveViewException(
        '7z bounded metadata supports at most 200000 coders.',
      );
    }
    var inputs = 0, outputs = 0;
    for (var i = 0; i < coderCount; i++) {
      final flags = reader.readUint8();
      if (flags & 0x80 != 0) {
        throw koni.UnsupportedFeatureException(
          'Alternative 7z coders are unsupported.',
          format: '7z',
        );
      }
      final id = reader.readBytes(flags & 15);
      final complex = flags & 0x10 != 0;
      final ins = complex ? number() : 1;
      final outs = complex ? number() : 1;
      if (ins < 1 || outs < 1) {
        _sevenZipInvalid('A 7z coder has no input or output.');
      }
      if (ins > 64 - inputs || outs > 64 - outputs) {
        throw const ArchiveViewException(
          '7z bounded metadata supports at most 64 input and output streams per folder.',
        );
      }
      inputs += ins;
      outputs += outs;
      final properties = flags & 0x20 != 0
          ? reader.readBytes(count('coder properties', 1024 * 1024))
          : Uint8List(0);
      if (id.length == 3 && _hasMagic(id, 0, const [3, 1, 1])) {
        if (properties.length != 5) {
          _sevenZipInvalid('Invalid 7z LZMA properties.');
        }
        if (ByteData.sublistView(properties).getUint32(1, Endian.little) >
            kArchiveReadLimit) {
          _sevenZipResourceLimit('an LZMA dictionary', kArchiveReadLimit);
        }
      }
      if (id.length == 1 && id.single == 0x21) {
        if (properties.length != 1) {
          _sevenZipInvalid('Invalid 7z LZMA2 properties.');
        }
        // Property 28 is 64 MiB; 29 is 96 MiB. The largest property (40)
        // advertises a 4 GiB dictionary even for a tiny final output.
        if (properties.single > 28) {
          _sevenZipResourceLimit('an LZMA2 dictionary', kArchiveReadLimit);
        }
      }
      if (_hasMagic(id, 0, const [0x06, 0xf1, 0x07, 0x01]) && id.length == 4) {
        if (properties.isEmpty) _sevenZipInvalid('Missing 7z AES properties.');
        if (properties.first & 0x3f > 20) {
          throw const ArchiveViewException(
            '7z AES key derivation above 2^20 rounds is not supported by the bounded reader.',
          );
        }
      }
    }
    _graphStreams += inputs + outputs;
    if (_graphStreams > 2 * _sevenZipFallbackCountLimit) {
      throw const ArchiveViewException(
        '7z bounded metadata supports at most 400000 coder input and output streams.',
      );
    }
    final boundIn = <int>{}, boundOut = <int>{};
    for (var i = 0; i < outputs - 1; i++) {
      final input = number(), output = number();
      if (input >= inputs ||
          output >= outputs ||
          !boundIn.add(input) ||
          !boundOut.add(output)) {
        _sevenZipInvalid('Invalid or duplicate 7z coder binding.');
      }
    }
    final packed = inputs - boundIn.length;
    if (packed < 1 || packed > 64) {
      _sevenZipInvalid('Invalid 7z packed-stream graph.');
    }
    if (packed != 1) {
      final indices = <int>{};
      for (var i = 0; i < packed; i++) {
        final index = number();
        if (index >= inputs || boundIn.contains(index) || !indices.add(index)) {
          _sevenZipInvalid('Invalid 7z packed-stream index.');
        }
      }
    }
    final finalOutput = List.generate(
      outputs,
      (i) => i,
    ).singleWhere((i) => !boundOut.contains(i));
    return _SevenZipFolderBudget(outputs, finalOutput, packed);
  }

  List<_SevenZipFolderBudget> streams() {
    final packedSizes = <int>[];
    final folders = <_SevenZipFolderBudget>[];
    var id = number(), declaredPacks = 0, packPosition = 0;
    if (id == SevenZId.packInfo) {
      packPosition = number();
      declaredPacks = count('packed-stream count');
      var inner = number();
      var sizesSeen = false, crcSeen = false;
      while (inner != SevenZId.end) {
        if (inner == SevenZId.size && !sizesSeen) {
          sizesSeen = true;
          for (var i = 0; i < declaredPacks; i++) {
            final size = number();
            if (size > kArchiveReadLimit) {
              _sevenZipResourceLimit('a packed stream', kArchiveReadLimit);
            }
            packedSizes.add(size);
          }
        } else if (inner == SevenZId.crc && !crcSeen) {
          crcSeen = true;
          digests(declaredPacks);
        } else {
          _sevenZipInvalid('Unexpected or repeated 7z packed-stream property.');
        }
        inner = number();
      }
      if (packedSizes.length != declaredPacks ||
          packPosition > sourceLength - 32) {
        _sevenZipInvalid('Invalid 7z packed-stream sizes or position.');
      }
      var position = 32 + packPosition;
      for (final size in packedSizes) {
        if (size > sourceLength - position) {
          _sevenZipInvalid('A 7z packed stream extends beyond its source.');
        }
        position += size;
      }
      id = number();
    }
    if (id == SevenZId.unpackInfo) {
      if (number() != SevenZId.folder) {
        _sevenZipInvalid('7z folder metadata is missing.');
      }
      final folderCount = count('folder count');
      if (reader.readUint8() != 0) {
        throw koni.UnsupportedFeatureException(
          'External 7z folder metadata is unsupported.',
          format: '7z',
        );
      }
      var usedPacks = 0;
      for (var i = 0; i < folderCount; i++) {
        final next = folder();
        usedPacks += next.packedInputs;
        folders.add(next);
      }
      if (usedPacks != declaredPacks || number() != SevenZId.codersUnpackSize) {
        _sevenZipInvalid(
          '7z packed streams or coder sizes do not match their folders.',
        );
      }
      for (final folder in folders) {
        for (var i = 0; i < folder.outputs; i++) {
          final size = number();
          if (size > limit) _sevenZipResourceLimit('a coder output', limit);
          if (i == folder.finalOutput) folder.size = size;
        }
      }
      var inner = number();
      if (inner == SevenZId.crc) {
        digests(
          folders.length,
          onDefined: (i, value) => folders[i].hasCrc = value,
        );
        inner = number();
      }
      if (inner != SevenZId.end) {
        _sevenZipInvalid('Unexpected 7z unpack property.');
      }
      id = number();
    } else if (declaredPacks != 0) {
      _sevenZipInvalid('7z packed streams have no folder metadata.');
    }
    if (id == SevenZId.subStreamsInfo) {
      var inner = number();
      if (inner == SevenZId.numUnpackStream) {
        var total = 0;
        for (final folder in folders) {
          folder.substreams = number();
          total += folder.substreams;
          if (total > _sevenZipFallbackCountLimit) {
            throw const ArchiveViewException(
              '7z bounded metadata supports at most 200000 substreams.',
            );
          }
        }
        inner = number();
      }
      if (inner == SevenZId.size) {
        for (final folder in folders) {
          var total = 0;
          for (var i = 0; i < folder.substreams - 1; i++) {
            final size = number();
            if (size > folder.size - total) {
              _sevenZipInvalid('7z substreams exceed their folder.');
            }
            total += size;
          }
        }
        inner = number();
      } else if (folders.any((folder) => folder.substreams > 1)) {
        _sevenZipInvalid('7z substream sizes are missing.');
      }
      if (inner == SevenZId.crc) {
        final unknown = folders.fold<int>(
          0,
          (sum, folder) =>
              sum +
              (folder.substreams == 1 && folder.hasCrc ? 0 : folder.substreams),
        );
        digests(unknown);
        inner = number();
      }
      if (inner != SevenZId.end) {
        _sevenZipInvalid('Unexpected 7z substream property.');
      }
      id = number();
    }
    if (id != SevenZId.end ||
        folders.any((f) => f.substreams == 0 && f.size != 0)) {
      _sevenZipInvalid('Invalid 7z stream-table terminator or empty folder.');
    }
    return folders;
  }

  void files() {
    if (number() > _sevenZipFallbackCountLimit) {
      throw const ArchiveViewException(
        '7z bounded metadata supports at most 200000 files.',
      );
    }
    final properties = <int>{};
    var count = 0;
    for (var id = number(); id != SevenZId.end; id = number()) {
      // Padding and unknown extension properties may repeat. Only the fields
      // that allocate per-file vectors need to be unique for this reader.
      if (const {
            SevenZId.emptyStream,
            SevenZId.emptyFile,
            SevenZId.name,
            SevenZId.mTime,
            SevenZId.winAttributes,
          }.contains(id) &&
          !properties.add(id)) {
        _sevenZipInvalid('Repeated 7z file-metadata property.');
      }
      if (++count > _sevenZipFallbackCountLimit) {
        throw const ArchiveViewException(
          '7z file properties exceed their bounded metadata count.',
        );
      }
      reader.skip(number());
    }
  }

  void plainHeader() {
    if (number() != SevenZId.header) {
      _sevenZipInvalid('Missing 7z file header.');
    }
    var id = number();
    if (id == SevenZId.archiveProperties) {
      for (
        var property = number();
        property != SevenZId.end;
        property = number()
      ) {
        reader.skip(number());
      }
      id = number();
    }
    if (id == SevenZId.additionalStreamsInfo) {
      throw koni.UnsupportedFeatureException(
        'Additional 7z streams are unsupported.',
        format: '7z',
      );
    }
    if (id == SevenZId.mainStreamsInfo) {
      streams();
      id = number();
    }
    if (id == SevenZId.filesInfo) {
      files();
      id = number();
    }
    if (id != SevenZId.end || reader.remaining != 0) {
      _sevenZipInvalid('Unexpected trailing 7z metadata.');
    }
  }
}

/// Presents only the metadata already checked above. Packed bytes keep their
/// original offsets. Closing this borrowed view never closes the owned input.
class _SevenZipCheckedSource implements koni.ByteSource {
  _SevenZipCheckedSource(
    this.parent,
    Uint8List header, {
    required this.sourceLength,
  }) : header = Uint8List.fromList(header),
       start = Uint8List(32) {
    start.setRange(0, 8, const [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0, 4]);
    final data = ByteData.sublistView(start);
    data.setUint32(12, sourceLength - 32, Endian.little);
    data.setUint32(20, header.length, Endian.little);
    data.setUint32(28, ar.getCrc32(header), Endian.little);
    data.setUint32(
      8,
      ar.getCrc32(Uint8List.sublistView(start, 12)),
      Endian.little,
    );
  }
  final koni.ByteSource parent;
  final int sourceLength;
  final Uint8List header, start;
  bool _closed = false;
  @override
  int get length => sourceLength + header.length;
  @override
  String? get name => parent.name;
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (_closed ||
        offset < 0 ||
        length < 0 ||
        offset > this.length ||
        length > this.length - offset) {
      _sevenZipInvalid('Read leaves the checked 7z source.');
    }
    if (length > kArchiveReadLimit) {
      _sevenZipResourceLimit('a source read', kArchiveReadLimit);
    }
    final result = Uint8List(length);
    var done = 0;
    while (done < length) {
      final at = offset + done;
      final boundary = at < 32
          ? 32
          : at < sourceLength
          ? sourceLength
          : this.length;
      final take = length - done < boundary - at
          ? length - done
          : boundary - at;
      final bytes = at < 32
          ? Uint8List.sublistView(start, at, at + take)
          : at < sourceLength
          ? await parent.read(at, take)
          : Uint8List.sublistView(
              header,
              at - sourceLength,
              at - sourceLength + take,
            );
      if (bytes.length != take) {
        _sevenZipInvalid('Truncated checked 7z source.');
      }
      result.setRange(done, done + take, bytes);
      done += take;
    }
    return result;
  }

  @override
  Future<void> close() async => _closed = true;
}

Future<koni.ByteSource> _preflightSevenZipFallback(
  koni.ByteSource source, {
  required String? password,
  required int limit,
}) async {
  final sourceLength = source.length;
  if (sourceLength < 6 ||
      !_hasMagic(await source.read(0, 6), 0, const [
        0x37,
        0x7a,
        0xbc,
        0xaf,
        0x27,
        0x1c,
      ])) {
    _sevenZipInvalid('The detected 7z signature changed before inspection.');
  }
  if (sourceLength > _sevenZipFallbackInputLimit) {
    _sevenZipResourceLimit('whole input', _sevenZipFallbackInputLimit);
  }
  if (sourceLength < 32) _sevenZipInvalid('Truncated 7z signature header.');
  final prefix = await source.read(0, 32);
  if (prefix.length != 32 || prefix[6] != 0) {
    _sevenZipInvalid('Unsupported 7z signature header.');
  }
  final start = ByteReader(prefix)..skip(8);
  final startCrc = start.readUint32le();
  if (ar.getCrc32(Uint8List.sublistView(prefix, 12)) != startCrc) {
    _sevenZipInvalid('7z start-header checksum does not match.');
  }
  final offset = start.readUint64le(),
      size = start.readUint64le(),
      crc = start.readUint32le();
  if (size > _sevenZipFallbackHeaderLimit) {
    _sevenZipResourceLimit('metadata', _sevenZipFallbackHeaderLimit);
  }
  if (offset > sourceLength - 32 || size > sourceLength - 32 - offset) {
    _sevenZipInvalid('7z metadata extends beyond its source.');
  }
  if (size == 0) {
    if (sourceLength != 32 || offset != 0) {
      _sevenZipInvalid('Empty 7z has unexpected data.');
    }
    return _SevenZipCheckedSource(
      source,
      Uint8List.fromList([SevenZId.header, SevenZId.end]),
      sourceLength: sourceLength,
    );
  }
  var header = Uint8List.fromList(await source.read(32 + offset, size));
  if (header.length != size || ar.getCrc32(header) != crc) {
    _sevenZipInvalid('7z metadata checksum does not match.');
  }
  final cursor = ByteReader(header);
  if (readSevenZipNumber(cursor) == SevenZId.encodedHeader) {
    final streamOffset = cursor.position;
    final encoded = _SevenZipResourceScanner(
      cursor,
      sourceLength,
      limit,
    ).streams();
    if (encoded.length != 1 ||
        encoded.single.substreams != 1 ||
        cursor.remaining != 0) {
      _sevenZipInvalid('7z encoded metadata must be one complete stream.');
    }
    if (encoded.single.size > _sevenZipFallbackHeaderLimit) {
      _sevenZipResourceLimit('decoded metadata', _sevenZipFallbackHeaderLimit);
    }
    // Reuse the public decoder only after validating every allocation in this
    // table. Exposing its single stream avoids private package APIs and lets
    // us inspect the decoded header before the real reader parses any files.
    final syntheticHeader = BytesBuilder(copy: false)
      ..add(const [SevenZId.header, SevenZId.mainStreamsInfo])
      ..add(Uint8List.sublistView(header, streamOffset))
      ..addByte(SevenZId.end);
    final synthetic = _SevenZipCheckedSource(
      source,
      syntheticHeader.takeBytes(),
      sourceLength: sourceLength,
    );
    koni.ArchiveReader? decoder;
    try {
      decoder = await koni.builtInFormats.openReader(
        synthetic,
        options: koni.ArchiveReadOptions(
          password: password,
          maxEntrySize: limit,
          maxEntryCount: 1,
          maxContainerDecodeSize: limit,
        ),
      );
      if (decoder.entries.length != 1) {
        _sevenZipInvalid('Invalid encoded 7z header stream.');
      }
      final output = BytesBuilder(copy: false);
      await for (final chunk in decoder.openRead(decoder.entries.single)) {
        if (chunk.length > encoded.single.size - output.length) {
          _sevenZipInvalid('Decoded 7z metadata exceeds its declared size.');
        }
        output.add(Uint8List.fromList(chunk));
      }
      if (output.length != encoded.single.size) {
        _sevenZipInvalid('Decoded 7z metadata is truncated.');
      }
      header = output.takeBytes();
    } finally {
      await decoder?.close();
      await synthetic.close();
    }
  }
  _SevenZipResourceScanner(
    ByteReader(header),
    sourceLength,
    limit,
  ).plainHeader();
  return _SevenZipCheckedSource(source, header, sourceLength: sourceLength);
}

Future<bool> _requiresHeaderPassword(koni.ByteSource source, int limit) async {
  if (source.length < 6) return false;
  final borrowed = ArchiveSliceSource(
    source,
    offset: 0,
    length: source.length,
    ownsParent: false,
  );
  try {
    if (!_hasMagic(await borrowed.read(0, 6), 0, const [
      0x37,
      0x7a,
      0xbc,
      0xaf,
      0x27,
      0x1c,
    ])) {
      return false;
    }
    final checked = await _preflightSevenZipFallback(
      borrowed,
      password: null,
      limit: limit < kArchiveReadLimit ? limit : kArchiveReadLimit,
    );
    final public = await koni.builtInFormats.openReader(
      checked,
      options: koni.ArchiveReadOptions(
        maxEntrySize: limit < kArchiveReadLimit ? limit : kArchiveReadLimit,
        maxEntryCount: 200000,
        maxContainerDecodeSize: limit < kArchiveReadLimit
            ? limit
            : kArchiveReadLimit,
      ),
    );
    await public.close();
    return false;
  } on koni.EncryptedArchiveException {
    return true;
  } catch (_) {
    // Corruption without evidence of encryption retains the original error.
    return false;
  } finally {
    await borrowed.close();
  }
}

Future<ViewerArchive> _openWithKoni(
  koni.ByteSource source, {
  String? password,
  required int maxMemberBytes,
}) async {
  koni.ArchiveReader reader;
  try {
    // Fix the selected decoder before opening it. A second auto-detection on
    // mutable input must not switch an uninspected format into the 7z fallback.
    final format = await koni.builtInFormats.detect(source);
    if (format == null) {
      throw koni.UnsupportedFormatException(
        'The archive format could not be determined.',
      );
    }
    final checked = format.name == '7z'
        ? await _preflightSevenZipFallback(
            source,
            password: password,
            limit: maxMemberBytes < kArchiveReadLimit
                ? maxMemberBytes
                : kArchiveReadLimit,
          )
        : source;
    final decodeLimit =
        checked is _SevenZipCheckedSource && maxMemberBytes > kArchiveReadLimit
        ? kArchiveReadLimit
        : maxMemberBytes;
    // Use the reader directly (not the Archive facade): a reader may throw
    // synchronously from openRead() for encrypted/unsupported entries, and
    // the facade's stream wrapper turns that into an unclosed stream (hang).
    reader = await koni.builtInFormats.openReader(
      checked,
      format: format,
      options: koni.ArchiveReadOptions(
        password: password,
        maxEntrySize: decodeLimit,
        maxEntryCount: 200000,
        maxContainerDecodeSize: decodeLimit,
      ),
    );
  } on ArchiveViewException {
    await source.close();
    rethrow;
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
    // A 7z encrypted header has no independent password verifier. Decrypting
    // with a wrong password can fail as a codec/header error instead. Only
    // offer a password retry when opening this same bounded source without a
    // password independently confirms header encryption.
    final encryptedHeader =
        password != null &&
        await _requiresHeaderPassword(source, maxMemberBytes);
    await source.close();
    if (encryptedHeader) {
      throw const ArchivePasswordRequiredException(
        'The password is wrong or the archive header is corrupt.',
        code: ArchiveMessageCode.wrongOrCorrupt,
        wrongPassword: true,
      );
    }
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
  List<DateTime?>? rarTimes;
  if (reader.format.name == 'rar') {
    try {
      rarTimes = await readRar5ModifiedTimes(source, entries);
    } catch (_) {
      try {
        await reader.close();
      } finally {
        await source.close();
      }
      rethrow;
    }
  }
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
        modified: rarTimes?[i] ?? entry.modified,
        posixMode: entry.posixMode,
        pathEscapedRoot: entry.pathEscapedRoot,
        index: i,
      ),
    );
  }

  Stream<List<int>> readChunks(
    ViewerArchiveMember member,
    int requestedCap,
  ) async* {
    final limit = requestedCap < maxMemberBytes ? requestedCap : maxMemberBytes;
    final entry = entries[member.index];
    if (entry.isEncrypted && password == null) {
      throw const ArchivePasswordRequiredException('This entry is encrypted.');
    }
    var received = 0;
    try {
      final stream = reader.openRead(entry); // may throw synchronously
      await for (final chunk in stream) {
        if (chunk.length > limit - received) {
          throw ArchiveViewException(
            'The entry is larger than the ${_mb(limit)} safety limit.',
            code: ArchiveMessageCode.entryLimit,
            arguments: {'limit': _mb(limit)},
          );
        }
        received += chunk.length;
        yield chunk;
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
  }

  return ViewerArchive.reader(
    formatName: reader.format.name,
    members: List<ViewerArchiveMember>.unmodifiable(members),
    read: (member, requestedCap) async {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in readChunks(member, requestedCap)) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    },
    // The pinned TAR and ZIP readers index metadata and read content in
    // bounded chunks. Other Koni readers retain their buffered adapter. Any
    // compression wrapper was already decoded under its separate container
    // limit; this does not increase that allowance or readMember's default.
    streamReader: const {'tar', 'zip'}.contains(reader.format.name)
        ? (member, chunkSize) => readChunks(member, maxMemberBytes)
        : null,
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
