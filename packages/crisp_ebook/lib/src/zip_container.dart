part of '../crisp_ebook.dart';

/// ZIP indexing is separate from inflation so a false size field never causes
/// unbounded allocation in a general-purpose ZIP decoder. ZIP64 and split
/// archives are intentionally outside this bounded editing profile.
class _ZipContainer {
  final Uint8List bytes;
  final Map<String, _ZipMember> members;
  final Uint8List comment;

  _ZipContainer._(this.bytes, this.members, this.comment);

  factory _ZipContainer.open(Uint8List input, EpubLimits limits) {
    if (input.length > limits.maxArchiveBytes) {
      throw const EpubException(
        'archive_limit',
        'The ebook exceeds the archive size limit.',
      );
    }
    if (input.length < 22) {
      throw const EpubException(
        'invalid_zip',
        'The ebook is not a complete ZIP archive.',
      );
    }
    final bytes = Uint8List.fromList(input);
    final data = ByteData.sublistView(bytes);
    var eocd = -1;
    final floor = bytes.length > 65557 ? bytes.length - 65557 : 0;
    for (var i = bytes.length - 22; i >= floor; i--) {
      if (data.getUint32(i, Endian.little) == 0x06054b50 &&
          i + 22 + data.getUint16(i + 20, Endian.little) == bytes.length) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) {
      throw const EpubException(
        'invalid_zip',
        'The ZIP directory is missing or truncated.',
      );
    }
    final disk = data.getUint16(eocd + 4, Endian.little);
    final directoryDisk = data.getUint16(eocd + 6, Endian.little);
    final count = data.getUint16(eocd + 10, Endian.little);
    final localCount = data.getUint16(eocd + 8, Endian.little);
    final directorySize = data.getUint32(eocd + 12, Endian.little);
    final directoryStart = data.getUint32(eocd + 16, Endian.little);
    if (disk != 0 || directoryDisk != 0 || count != localCount) {
      throw const EpubException(
        'split_zip',
        'Split ZIP ebooks are not supported.',
      );
    }
    if (count == 0xffff ||
        directorySize == 0xffffffff ||
        directoryStart == 0xffffffff) {
      throw const EpubException(
        'zip64',
        'ZIP64 ebooks are outside the bounded editing profile.',
      );
    }
    if (count > limits.maxEntries) {
      throw const EpubException(
        'entry_limit',
        'The ebook has too many archive entries.',
      );
    }
    if (directoryStart + directorySize != eocd || directoryStart > eocd) {
      throw const EpubException(
        'invalid_zip',
        'The ZIP directory bounds are invalid.',
      );
    }
    final members = <String, _ZipMember>{};
    final ranges = <(int, int)>[];
    var cursor = directoryStart;
    var expanded = 0;
    for (var i = 0; i < count; i++) {
      if (cursor + 46 > eocd ||
          data.getUint32(cursor, Endian.little) != 0x02014b50) {
        throw const EpubException(
          'invalid_zip',
          'An archive directory entry is invalid.',
        );
      }
      final flags = data.getUint16(cursor + 8, Endian.little);
      final method = data.getUint16(cursor + 10, Endian.little);
      final crc = data.getUint32(cursor + 16, Endian.little);
      final compressedSize = data.getUint32(cursor + 20, Endian.little);
      final size = data.getUint32(cursor + 24, Endian.little);
      final nameLength = data.getUint16(cursor + 28, Endian.little);
      final extraLength = data.getUint16(cursor + 30, Endian.little);
      final commentLength = data.getUint16(cursor + 32, Endian.little);
      final attributes = data.getUint32(cursor + 38, Endian.little);
      final localOffset = data.getUint32(cursor + 42, Endian.little);
      final end = cursor + 46 + nameLength + extraLength + commentLength;
      if (end > eocd || nameLength == 0 || nameLength > 4096) {
        throw const EpubException(
          'invalid_zip',
          'An archive filename or header is invalid.',
        );
      }
      String name;
      try {
        name = utf8.decode(
          Uint8List.sublistView(bytes, cursor + 46, cursor + 46 + nameLength),
        );
      } on FormatException {
        throw const EpubException(
          'zip_encoding',
          'EPUB archive filenames must be UTF-8.',
        );
      }
      final isDirectory = name.endsWith('/');
      _safeArchivePath(name, directory: isDirectory);
      if (members.containsKey(name) ||
          members.containsKey('$name/') ||
          (isDirectory &&
              members.containsKey(name.substring(0, name.length - 1)))) {
        throw EpubException(
          'duplicate_path',
          'Duplicate archive entry.',
          path: name,
        );
      }
      if ((flags & 0x41) != 0) {
        throw EpubException(
          'zip_encrypted',
          'Password-encrypted ZIP containers are not supported.',
          path: name,
        );
      }
      if (method != 0 && method != 8) {
        throw EpubException(
          'zip_compression',
          'EPUB entries must use stored or Deflate compression.',
          path: name,
        );
      }
      if (((attributes >> 16) & 0xf000) == 0xa000) {
        throw EpubException(
          'zip_symlink',
          'Symbolic links are not permitted inside an ebook.',
          path: name,
        );
      }
      if (size > limits.maxEntryBytes ||
          compressedSize > limits.maxArchiveBytes ||
          localOffset == 0xffffffff ||
          data.getUint16(cursor + 34, Endian.little) != 0) {
        throw EpubException(
          'entry_limit',
          'An archive entry exceeds the supported bounds.',
          path: name,
        );
      }
      expanded += size;
      if (expanded > limits.maxExpandedBytes) {
        throw const EpubException(
          'expanded_limit',
          'The ebook exceeds the expanded size limit.',
        );
      }
      if (localOffset + 30 > directoryStart ||
          data.getUint32(localOffset, Endian.little) != 0x04034b50) {
        throw EpubException(
          'invalid_zip',
          'An archive local header is invalid.',
          path: name,
        );
      }
      final localFlags = data.getUint16(localOffset + 6, Endian.little);
      final localMethod = data.getUint16(localOffset + 8, Endian.little);
      final localNameLength = data.getUint16(localOffset + 26, Endian.little);
      final localExtraLength = data.getUint16(localOffset + 28, Endian.little);
      final payloadStart =
          localOffset + 30 + localNameLength + localExtraLength;
      if (localFlags != flags ||
          localMethod != method ||
          payloadStart + compressedSize > directoryStart ||
          localNameLength != nameLength) {
        throw EpubException(
          'invalid_zip',
          'Conflicting ZIP entry headers.',
          path: name,
        );
      }
      if (!_bytesEqual(
        Uint8List.sublistView(
          bytes,
          localOffset + 30,
          localOffset + 30 + localNameLength,
        ),
        Uint8List.sublistView(bytes, cursor + 46, cursor + 46 + nameLength),
      )) {
        throw EpubException(
          'invalid_zip',
          'Conflicting ZIP filenames.',
          path: name,
        );
      }
      if ((flags & 8) == 0 &&
          (data.getUint32(localOffset + 14, Endian.little) != crc ||
              data.getUint32(localOffset + 18, Endian.little) !=
                  compressedSize ||
              data.getUint32(localOffset + 22, Endian.little) != size)) {
        throw EpubException(
          'invalid_zip',
          'Conflicting ZIP sizes or checksums.',
          path: name,
        );
      }
      if (method == 0 && compressedSize != size) {
        throw EpubException(
          'invalid_zip',
          'Stored entry sizes do not match.',
          path: name,
        );
      }
      _validateZipExtra(
        Uint8List.sublistView(
          bytes,
          localOffset + 30 + localNameLength,
          payloadStart,
        ),
        name,
      );
      _validateZipExtra(
        Uint8List.sublistView(
          bytes,
          cursor + 46 + nameLength,
          cursor + 46 + nameLength + extraLength,
        ),
        name,
      );
      ranges.add((localOffset, payloadStart + compressedSize));
      members[name] = _ZipMember(
        name: name,
        size: size,
        method: method,
        crc: crc,
        payload: Uint8List.sublistView(
          bytes,
          payloadStart,
          payloadStart + compressedSize,
        ),
        localExtra: Uint8List.sublistView(
          bytes,
          localOffset + 30 + localNameLength,
          payloadStart,
        ),
        centralExtra: Uint8List.sublistView(
          bytes,
          cursor + 46 + nameLength,
          cursor + 46 + nameLength + extraLength,
        ),
        comment: Uint8List.sublistView(bytes, end - commentLength, end),
        dosTime: data.getUint32(cursor + 12, Endian.little),
        attributes: attributes,
        versionMade: data.getUint16(cursor + 4, Endian.little),
        directory: isDirectory,
      );
      cursor = end;
    }
    if (cursor != eocd) {
      throw const EpubException(
        'invalid_zip',
        'The archive directory length does not match.',
      );
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 1; i < ranges.length; i++) {
      if (ranges[i].$1 < ranges[i - 1].$2) {
        throw const EpubException(
          'invalid_zip',
          'Overlapping ZIP entries are not permitted.',
        );
      }
    }
    return _ZipContainer._(
      bytes,
      Map.unmodifiable(members),
      Uint8List.sublistView(bytes, eocd + 22),
    );
  }
}

class _ZipMember {
  final String name;
  final int size;
  final int method;
  final int crc;
  final Uint8List payload;
  final Uint8List localExtra;
  final Uint8List centralExtra;
  final Uint8List comment;
  final int dosTime;
  final int attributes;
  final int versionMade;
  final bool directory;

  _ZipMember({
    required this.name,
    required this.size,
    required this.method,
    required this.crc,
    required this.payload,
    required this.localExtra,
    required this.centralExtra,
    required this.comment,
    required this.dosTime,
    required this.attributes,
    required this.versionMade,
    required this.directory,
  });

  Uint8List read() {
    try {
      final bytes = method == 0
          ? Uint8List.fromList(payload)
          : const archive.ZLibDecoder().decodeBytes(
              payload,
              raw: true,
              verify: true,
              throwOnError: true,
              maxOutputSize: size == 0 ? 1 : size,
            );
      if (bytes.length != size || archive.getCrc32(bytes) != crc) {
        throw EpubException(
          'zip_checksum',
          'An archive entry is corrupt.',
          path: name,
        );
      }
      return bytes;
    } on EpubException {
      rethrow;
    } catch (_) {
      throw EpubException(
        'zip_inflate',
        'An archive entry is corrupt or exceeds its declared size.',
        path: name,
      );
    }
  }
}

/// Writes fresh local headers and directory offsets while copying untouched
/// compressed streams verbatim. Unknown resources and their extra fields stay
/// intact. The required mimetype entry is always first, stored, and extra-free.
Uint8List _writeZip(
  Map<String, _ZipMember> originals,
  Map<String, Uint8List> changed,
  Set<String> removed,
  EpubLimits limits, {
  Uint8List? archiveComment,
}) {
  final names = <String>{'mimetype', ...originals.keys, ...changed.keys}
    ..removeWhere(removed.contains);
  if (names.length > limits.maxEntries || names.length >= 0xffff) {
    throw const EpubException('entry_limit', 'The ebook has too many entries.');
  }
  final output = BytesBuilder(copy: false);
  final directory = BytesBuilder(copy: false);
  var expanded = 0;
  for (final name in names) {
    final original = originals[name];
    final bytes = name == 'mimetype'
        ? Uint8List.fromList(utf8.encode('application/epub+zip'))
        : changed[name];
    Uint8List payload;
    int method;
    int size;
    int crc;
    if (bytes != null) {
      size = bytes.length;
      crc = archive.getCrc32(bytes);
      if (size > limits.maxEntryBytes) {
        throw EpubException(
          'entry_limit',
          'The resource is too large.',
          path: name,
        );
      }
      final compressed = name == 'mimetype' || size < 96
          ? bytes
          : archive.Deflate(bytes, level: 6).getBytes();
      method = !identical(compressed, bytes) && compressed.length < bytes.length
          ? 8
          : 0;
      payload = method == 8 ? compressed : bytes;
    } else if (original != null) {
      payload = original.payload;
      method = original.method;
      size = original.size;
      crc = original.crc;
    } else {
      continue;
    }
    expanded += size;
    if (expanded > limits.maxExpandedBytes) {
      throw const EpubException(
        'expanded_limit',
        'The ebook exceeds the expanded size limit.',
      );
    }
    final filename = Uint8List.fromList(utf8.encode(name));
    final localExtra = name == 'mimetype'
        ? Uint8List(0)
        : original?.localExtra ?? Uint8List(0);
    final centralExtra = name == 'mimetype'
        ? Uint8List(0)
        : original?.centralExtra ?? Uint8List(0);
    final comment = original?.comment ?? Uint8List(0);
    final localOffset = output.length;
    final header = ByteData(30);
    header.setUint32(0, 0x04034b50, Endian.little);
    header.setUint16(4, 20, Endian.little);
    header.setUint16(6, 0x800, Endian.little);
    header.setUint16(8, method, Endian.little);
    header.setUint32(10, original?.dosTime ?? 0x00210000, Endian.little);
    header.setUint32(14, crc, Endian.little);
    header.setUint32(18, payload.length, Endian.little);
    header.setUint32(22, size, Endian.little);
    header.setUint16(26, filename.length, Endian.little);
    header.setUint16(28, localExtra.length, Endian.little);
    final projected =
        output.length +
        30 +
        filename.length +
        localExtra.length +
        payload.length +
        directory.length +
        46 +
        filename.length +
        centralExtra.length +
        comment.length +
        22 +
        (archiveComment?.length ?? 0);
    if (projected > limits.maxArchiveBytes) {
      throw const EpubException(
        'archive_limit',
        'The saved ebook would exceed the archive size limit.',
      );
    }
    output.add(header.buffer.asUint8List());
    output.add(filename);
    output.add(localExtra);
    output.add(payload);
    final central = ByteData(46);
    central.setUint32(0, 0x02014b50, Endian.little);
    central.setUint16(4, original?.versionMade ?? 20, Endian.little);
    central.setUint16(6, 20, Endian.little);
    central.setUint16(8, 0x800, Endian.little);
    central.setUint16(10, method, Endian.little);
    central.setUint32(12, original?.dosTime ?? 0x00210000, Endian.little);
    central.setUint32(16, crc, Endian.little);
    central.setUint32(20, payload.length, Endian.little);
    central.setUint32(24, size, Endian.little);
    central.setUint16(28, filename.length, Endian.little);
    central.setUint16(30, centralExtra.length, Endian.little);
    central.setUint16(32, comment.length, Endian.little);
    central.setUint32(38, original?.attributes ?? 0, Endian.little);
    central.setUint32(42, localOffset, Endian.little);
    directory.add(central.buffer.asUint8List());
    directory.add(filename);
    directory.add(centralExtra);
    directory.add(comment);
  }
  final directoryOffset = output.length;
  final directorySize = directory.length;
  output.add(directory.takeBytes());
  final end = ByteData(22);
  end.setUint32(0, 0x06054b50, Endian.little);
  end.setUint16(8, names.length, Endian.little);
  end.setUint16(10, names.length, Endian.little);
  end.setUint32(12, directorySize, Endian.little);
  end.setUint32(16, directoryOffset, Endian.little);
  end.setUint16(20, archiveComment?.length ?? 0, Endian.little);
  output.add(end.buffer.asUint8List());
  if (archiveComment != null) output.add(archiveComment);
  return output.takeBytes();
}

String _safeArchivePath(String value, {bool directory = false}) {
  final name = directory && value.endsWith('/')
      ? value.substring(0, value.length - 1)
      : value;
  if (name.isEmpty ||
      name.startsWith('/') ||
      name.contains('\\') ||
      name.contains('\u0000') ||
      name.contains(':') ||
      name
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..') ||
      utf8.encode(value).length > 4096 ||
      name.codeUnits.any((c) => c < 32 || c == 127)) {
    throw EpubException(
      'unsafe_path',
      'Unsafe archive resource path.',
      path: value,
    );
  }
  return value;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _validateZipExtra(Uint8List bytes, String name) {
  final data = ByteData.sublistView(bytes);
  var offset = 0;
  while (offset < bytes.length) {
    if (offset + 4 > bytes.length) {
      throw EpubException(
        'invalid_zip',
        'A ZIP extra field is truncated.',
        path: name,
      );
    }
    final type = data.getUint16(offset, Endian.little);
    final length = data.getUint16(offset + 2, Endian.little);
    if (offset + 4 + length > bytes.length) {
      throw EpubException(
        'invalid_zip',
        'A ZIP extra field exceeds its bounds.',
        path: name,
      );
    }
    if (type == 0x0001) {
      throw EpubException(
        'zip64',
        'ZIP64 entries are outside the bounded editing profile.',
        path: name,
      );
    }
    if (type == 0x7075) {
      // Different ZIP readers may prefer this Unicode path over the filename.
      // Reject alternate interpretations instead of preserving a hidden path.
      if (length < 5) {
        throw EpubException(
          'invalid_zip',
          'A Unicode ZIP path is truncated.',
          path: name,
        );
      }
      try {
        final alternate = utf8.decode(
          Uint8List.sublistView(bytes, offset + 9, offset + 4 + length),
        );
        if (alternate != name) {
          throw EpubException(
            'unsafe_path',
            'Conflicting Unicode ZIP path.',
            path: name,
          );
        }
      } on FormatException {
        throw EpubException(
          'zip_encoding',
          'A Unicode ZIP path is malformed.',
          path: name,
        );
      }
    }
    offset += length + 4;
  }
}
