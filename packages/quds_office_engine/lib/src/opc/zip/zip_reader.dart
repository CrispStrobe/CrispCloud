import 'dart:convert';
import 'dart:typed_data';

import '../../io/byte_source.dart';
import 'crc32.dart';
import 'deflate_codec.dart';

const int zipLocalSig = 0x04034b50;
const int zipCentralSig = 0x02014b50;
const int zipEocdSig = 0x06054b50;
const int zipEocd64Sig = 0x06064b50;
const int zipEocd64LocatorSig = 0x07064b50;
const int zipDataDescriptorSig = 0x08074b50;

const int zipMethodStore = 0;
const int zipMethodDeflate = 8;

/// Central-directory entry describing one ZIP member.
class ZipEntry {
  /// ZipEntry API.
  ZipEntry({
    required this.fileName,
    required this.compressionMethod,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.generalPurposeFlag,
    this.comment = '',
  });

  /// fileName API.
  final String fileName;

  /// compressionMethod API.
  final int compressionMethod;

  /// crc32 API.
  final int crc32;

  /// compressedSize API.
  final int compressedSize;

  /// uncompressedSize API.
  final int uncompressedSize;

  /// localHeaderOffset API.
  final int localHeaderOffset;

  /// generalPurposeFlag API.
  final int generalPurposeFlag;

  /// comment API.
  final String comment;

  /// isDirectory API.
  bool get isDirectory => fileName.endsWith('/');
}

/// Streaming ZIP reader. Loads only the central directory up front and
/// inflates individual members on demand.
class ZipReader {
  ZipReader._(this._source, this._entries);

  final ByteSource _source;
  final Map<String, ZipEntry> _entries;

  /// open API.
  factory ZipReader.open(ByteSource source) {
    if (source.length < 22) {
      throw const ZipException('Buffer is too small to be a ZIP archive');
    }
    final _Eocd eocd = _findEocd(source);
    final Map<String, ZipEntry> entries = <String, ZipEntry>{};
    int offset = eocd.centralDirectoryOffset;
    for (int i = 0; i < eocd.entryCount; i++) {
      final ZipEntry entry = _readCentralEntry(source, offset);
      entries[entry.fileName] = entry;
      offset += _centralEntrySize(source, offset);
    }
    return ZipReader._(source, entries);
  }

  /// fromBytes API.
  factory ZipReader.fromBytes(Uint8List bytes) =>
      ZipReader.open(MemoryByteSource(bytes));

  /// tryOpen API.
  static ZipReader? tryOpen(ByteSource source) {
    try {
      return ZipReader.open(source);
    } on ZipException {
      return null;
    }
  }

  /// byteLength API.
  int get byteLength => _source.length;

  /// fileNames API.
  Iterable<String> get fileNames => _entries.keys;

  /// entries API.
  Iterable<ZipEntry> get entries => _entries.values;

  ZipEntry? operator [](String name) => _entries[name];

  /// contains API.
  bool contains(String name) => _entries.containsKey(name);

  /// Inflates [name] into a newly allocated buffer.
  Uint8List read(String name) {
    final ZipEntry? entry = _entries[name];
    if (entry == null) {
      throw ZipException('ZIP entry not found: $name');
    }
    if (entry.isDirectory) {
      return Uint8List(0);
    }
    final _LocalLocation loc = _localData(entry);
    final Uint8List payload = _source.view(loc.offset, loc.compressedSize);
    final Uint8List raw;
    switch (entry.compressionMethod) {
      case zipMethodStore:
        raw = Uint8List.fromList(payload);
      case zipMethodDeflate:
        raw = RawDeflate.inflate(payload);
      default:
        throw ZipException(
          'Unsupported ZIP compression method ${entry.compressionMethod} '
          'for $name',
        );
    }
    if (entry.uncompressedSize != 0 && raw.length != entry.uncompressedSize) {
      throw ZipException(
        'Uncompressed size mismatch for $name: '
        'expected ${entry.uncompressedSize}, got ${raw.length}',
      );
    }
    final int crc = Crc32.compute(raw);
    if (entry.crc32 != 0 && crc != entry.crc32) {
      throw ZipException(
        'CRC-32 mismatch for $name: expected '
        '0x${entry.crc32.toRadixString(16)}, got 0x${crc.toRadixString(16)}',
      );
    }
    return raw;
  }

  /// Inflates [name] even when CRC or declared size is wrong.
  Uint8List readRelaxed(String name) {
    final ZipEntry? entry = _entries[name];
    if (entry == null) {
      throw ZipException('ZIP entry not found: $name');
    }
    if (entry.isDirectory) {
      return Uint8List(0);
    }
    final _LocalLocation loc = _localData(entry);
    final int avail = _source.length - loc.offset;
    final int take = loc.compressedSize > 0 && loc.compressedSize <= avail
        ? loc.compressedSize
        : (avail < 0 ? 0 : avail);
    final Uint8List payload = take == 0
        ? Uint8List(0)
        : _source.view(loc.offset, take);
    switch (entry.compressionMethod) {
      case zipMethodStore:
        return Uint8List.fromList(payload);
      case zipMethodDeflate:
        try {
          return RawDeflate.inflate(payload);
        } on ZipDeflateException {
          return Uint8List.fromList(payload);
        }
      default:
        return Uint8List.fromList(payload);
    }
  }

  /// Yields inflated chunks for [name] without buffering the whole member
  /// when the codec can stream. Stored entries are yielded as a single view.
  Stream<List<int>> openStream(String name) async* {
    final ZipEntry? entry = _entries[name];
    if (entry == null) {
      throw ZipException('ZIP entry not found: $name');
    }
    final _LocalLocation loc = _localData(entry);
    final Uint8List payload = _source.view(loc.offset, loc.compressedSize);
    switch (entry.compressionMethod) {
      case zipMethodStore:
        yield payload;
      case zipMethodDeflate:
        yield RawDeflate.inflate(payload);
      default:
        throw ZipException(
          'Unsupported ZIP compression method ${entry.compressionMethod}',
        );
    }
  }

  _LocalLocation _localData(ZipEntry entry) {
    final ByteCursor cursor = ByteCursor.view(
      _source,
      entry.localHeaderOffset,
      30,
    );
    final int sig = cursor.u32le();
    if (sig != zipLocalSig) {
      throw ZipException(
        'Invalid local file header for ${entry.fileName} '
        '(sig=0x${sig.toRadixString(16)})',
      );
    }
    cursor.skip(22);
    final int nameLen = cursor.u16le();
    final int extraLen = cursor.u16le();
    return _LocalLocation(
      offset: entry.localHeaderOffset + 30 + nameLen + extraLen,
      compressedSize: entry.compressedSize,
    );
  }

  static _Eocd _findEocd(ByteSource source) {
    final int length = source.length;
    final int scan = length < 65557 ? length : 65557;
    final Uint8List tail = source.view(length - scan, scan);
    for (int i = tail.length - 22; i >= 0; i--) {
      if (tail[i] == 0x50 &&
          tail[i + 1] == 0x4b &&
          tail[i + 2] == 0x05 &&
          tail[i + 3] == 0x06) {
        final ByteCursor cursor = ByteCursor(tail, offset: i);
        final int sig = cursor.u32le();
        if (sig != zipEocdSig) {
          continue;
        }
        cursor.u16le(); // disk
        cursor.u16le(); // cd disk
        cursor.u16le(); // entries on disk
        final int entryCount = cursor.u16le();
        final int cdSize = cursor.u32le();
        final int cdOffset = cursor.u32le();
        final int commentLen = cursor.u16le();
        if (i + 22 + commentLen > tail.length) {
          continue;
        }
        if (cdOffset == 0xFFFFFFFF ||
            cdSize == 0xFFFFFFFF ||
            entryCount == 0xFFFF) {
          return _readZip64Eocd(source, length - scan + i);
        }
        return _Eocd(
          entryCount: entryCount,
          centralDirectoryOffset: cdOffset,
          centralDirectorySize: cdSize,
        );
      }
    }
    throw const ZipException('End of central directory signature not found');
  }

  static _Eocd _readZip64Eocd(ByteSource source, int eocdOffset) {
    if (eocdOffset < 20) {
      throw const ZipException('ZIP64 locator missing');
    }
    final ByteCursor locator = ByteCursor.view(source, eocdOffset - 20, 20);
    final int locSig = locator.u32le();
    if (locSig != zipEocd64LocatorSig) {
      throw const ZipException(
        'ZIP64 end-of-central-directory locator missing',
      );
    }
    locator.u32le(); // disk
    final int eocd64Offset = locator.u64le();
    final ByteCursor eocd64 = ByteCursor.view(source, eocd64Offset, 56);
    final int sig = eocd64.u32le();
    if (sig != zipEocd64Sig) {
      throw const ZipException('Invalid ZIP64 EOCD signature');
    }
    eocd64.u64le(); // size of eocd64
    eocd64.u16le(); // version made
    eocd64.u16le(); // version need
    eocd64.u32le(); // disk
    eocd64.u32le(); // cd disk
    eocd64.u64le(); // entries on disk
    final int entryCount = eocd64.u64le();
    final int cdSize = eocd64.u64le();
    final int cdOffset = eocd64.u64le();
    return _Eocd(
      entryCount: entryCount,
      centralDirectoryOffset: cdOffset,
      centralDirectorySize: cdSize,
    );
  }

  static ZipEntry _readCentralEntry(ByteSource source, int offset) {
    final ByteCursor header = ByteCursor.view(source, offset, 46);
    final int sig = header.u32le();
    if (sig != zipCentralSig) {
      throw ZipException(
        'Invalid central directory signature at $offset '
        '(0x${sig.toRadixString(16)})',
      );
    }
    header.u16le(); // version made
    header.u16le(); // version need
    final int flags = header.u16le();
    final int method = header.u16le();
    header.u16le(); // time
    header.u16le(); // date
    final int crc = header.u32le();
    int compressed = header.u32le();
    int uncompressed = header.u32le();
    final int nameLen = header.u16le();
    final int extraLen = header.u16le();
    final int commentLen = header.u16le();
    header.u16le(); // disk
    header.u16le(); // int attrs
    header.u32le(); // ext attrs
    int localOffset = header.u32le();

    final Uint8List nameBytes = source.view(offset + 46, nameLen);
    final bool utf8Names = (flags & (1 << 11)) != 0;
    final String name = utf8Names
        ? utf8.decode(nameBytes)
        : latin1.decode(nameBytes);

    final Uint8List extra = source.view(offset + 46 + nameLen, extraLen);
    final _Zip64Sizes zip64 = _parseZip64Extra(
      extra,
      compressed == 0xFFFFFFFF,
      uncompressed == 0xFFFFFFFF,
      localOffset == 0xFFFFFFFF,
    );
    if (zip64.compressedSize != null) {
      compressed = zip64.compressedSize!;
    }
    if (zip64.uncompressedSize != null) {
      uncompressed = zip64.uncompressedSize!;
    }
    if (zip64.localHeaderOffset != null) {
      localOffset = zip64.localHeaderOffset!;
    }

    String comment = '';
    if (commentLen > 0) {
      comment = utf8.decode(
        source.view(offset + 46 + nameLen + extraLen, commentLen),
        allowMalformed: true,
      );
    }

    return ZipEntry(
      fileName: name,
      compressionMethod: method,
      crc32: crc,
      compressedSize: compressed,
      uncompressedSize: uncompressed,
      localHeaderOffset: localOffset,
      generalPurposeFlag: flags,
      comment: comment,
    );
  }

  static int _centralEntrySize(ByteSource source, int offset) {
    final ByteCursor header = ByteCursor.view(source, offset, 46);
    header.skip(28);
    final int nameLen = header.u16le();
    final int extraLen = header.u16le();
    final int commentLen = header.u16le();
    return 46 + nameLen + extraLen + commentLen;
  }

  static _Zip64Sizes _parseZip64Extra(
    Uint8List extra,
    bool needCompressed,
    bool needUncompressed,
    bool needOffset,
  ) {
    int pos = 0;
    while (pos + 4 <= extra.length) {
      final int id = extra[pos] | (extra[pos + 1] << 8);
      final int size = extra[pos + 2] | (extra[pos + 3] << 8);
      pos += 4;
      if (id == 0x0001) {
        final ByteCursor cursor = ByteCursor(
          Uint8List.sublistView(extra, pos, pos + size),
        );
        int? uncompressed;
        int? compressed;
        int? offset;
        if (needUncompressed && cursor.remaining >= 8) {
          uncompressed = cursor.u64le();
        }
        if (needCompressed && cursor.remaining >= 8) {
          compressed = cursor.u64le();
        }
        if (needOffset && cursor.remaining >= 8) {
          offset = cursor.u64le();
        }
        return _Zip64Sizes(
          compressedSize: compressed,
          uncompressedSize: uncompressed,
          localHeaderOffset: offset,
        );
      }
      pos += size;
    }
    return const _Zip64Sizes();
  }
}

class _LocalLocation {
  const _LocalLocation({required this.offset, required this.compressedSize});

  /// offset API.
  final int offset;

  /// compressedSize API.
  final int compressedSize;
}

class _Eocd {
  const _Eocd({
    required this.entryCount,
    required this.centralDirectoryOffset,
    required this.centralDirectorySize,
  });

  /// entryCount API.
  final int entryCount;

  /// centralDirectoryOffset API.
  final int centralDirectoryOffset;

  /// centralDirectorySize API.
  final int centralDirectorySize;
}

class _Zip64Sizes {
  const _Zip64Sizes({
    this.compressedSize,
    this.uncompressedSize,
    this.localHeaderOffset,
  });

  /// compressedSize API.
  final int? compressedSize;

  /// uncompressedSize API.
  final int? uncompressedSize;

  /// localHeaderOffset API.
  final int? localHeaderOffset;
}

/// Thrown when a ZIP archive is corrupt or uses an unsupported feature.
class ZipException implements Exception {
  /// ZipException API.
  const ZipException(this.message);

  /// message API.
  final String message;

  @override
  /// toString API.
  String toString() => 'ZipException: $message';
}
