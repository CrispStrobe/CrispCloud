// Original bounded CAB reader. Format references and independent fixtures are
// recorded in test/fixtures/archives/CAB_READERS.md. No member is executed and
// application-specific reserved data or publisher signatures are not verified.

import 'dart:convert';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:koni_codecs/koni_codecs.dart' as codecs;

import 'archive_types.dart';

const _maxMetadataBytes = 16 * 1024 * 1024;
const _maxNameBytes = 16 * 1024;
const _maxFolders = 4096;
const _maxBlocks = 100000;
const _blockSize = 32768;

/// Opens a single CAB containing stored or MSZIP-compressed folders.
///
/// Listing reads only bounded metadata. A member read verifies and decodes its
/// complete folder, retaining at most one [maxFolderBytes]-bounded folder. MSZIP
/// retains its 32 KiB history across data blocks. Spanned cabinets, split blocks,
/// Quantum and LZX are deliberately refused. The returned archive owns [source].
Future<ViewerArchive> openCabArchive(
  koni.ByteSource source, {
  required int maxMemberBytes,
  int maxFolderBytes = kArchiveReadLimit,
}) async {
  final reader = _CabReader(source, maxMemberBytes, maxFolderBytes);
  try {
    return await reader.open();
  } catch (error) {
    await reader.close();
    if (error is ArchiveViewException || error is ArgumentError) rethrow;
    throw _bad('Could not read the CAB container: $error');
  }
}

class _CabReader {
  _CabReader(this.source, this.maxMemberBytes, this.maxFolderBytes);

  final koni.ByteSource source;
  final int maxMemberBytes, maxFolderBytes;
  final folders = <_CabFolder>[];
  final locations = <({int folder, int offset})>[];
  var _metadataBytes = 0;
  var _cabinetSize = 0;
  var _closed = false;
  var _cachedFolder = -1;
  Uint8List? _cachedBytes;
  // Serialize reads so concurrent previews cannot retain several folder caches.
  Future<void> _pending = Future<void>.value();

  Future<ViewerArchive> open() async {
    if (maxMemberBytes <= 0 || maxFolderBytes <= 0) {
      throw ArgumentError('CAB limits must be positive.');
    }
    if (source.length < 36 || source.length > 9007199254740991) {
      throw _bad('Truncated or oversized CAB header.');
    }
    _cabinetSize = source.length;
    final headerBytes = await _metadata(0, 36);
    final header = ByteData.sublistView(headerBytes);
    if (ascii.decode(headerBytes.sublist(0, 4), allowInvalid: true) != 'MSCF' ||
        header.getUint32(4, Endian.little) != 0 ||
        header.getUint32(12, Endian.little) != 0 ||
        header.getUint32(20, Endian.little) != 0 ||
        headerBytes[24] != 3 ||
        headerBytes[25] != 1) {
      throw _bad('Only CAB version 1.3 with a valid header is supported.');
    }
    _cabinetSize = header.getUint32(8, Endian.little);
    if (_cabinetSize < 36 || _cabinetSize > source.length) {
      throw _bad('The CAB length extends beyond the available input.');
    }
    final fileOffset = header.getUint32(16, Endian.little);
    final folderCount = header.getUint16(26, Endian.little);
    final fileCount = header.getUint16(28, Endian.little);
    final flags = header.getUint16(30, Endian.little);
    if ((flags & ~4) != 0 || header.getUint16(34, Endian.little) != 0) {
      throw _bad(
        'Spanned cabinets and unknown CAB header flags are unavailable.',
      );
    }
    if (folderCount > _maxFolders || (fileCount > 0 && folderCount == 0)) {
      throw _bad('Invalid or oversized CAB folder table.');
    }
    var cursor = 36;
    var folderReserve = 0;
    var dataReserve = 0;
    if ((flags & 4) != 0) {
      final reserve = await _metadata(cursor, 4);
      final headerReserve = ByteData.sublistView(reserve)
          .getUint16(0, Endian.little);
      if (headerReserve > 60000) {
        throw _bad('The CAB header reserve exceeds its format limit.');
      }
      folderReserve = reserve[2];
      dataReserve = reserve[3];
      cursor += 4;
      await _metadata(cursor, headerReserve);
      cursor += headerReserve;
    }
    final folderBytes = await _metadata(
      cursor,
      folderCount * (8 + folderReserve),
    );
    cursor += folderBytes.length;
    if (fileOffset < cursor || fileOffset > _cabinetSize) {
      throw _bad('The CAB file table overlaps its header.');
    }
    var firstData = _cabinetSize;
    var blockCount = 0;
    final folderData = ByteData.sublistView(folderBytes);
    for (var i = 0; i < folderCount; i++) {
      final at = i * (8 + folderReserve);
      final offset = folderData.getUint32(at, Endian.little);
      final count = folderData.getUint16(at + 4, Endian.little);
      final method = folderData.getUint16(at + 6, Endian.little);
      if (method != 0 && method != 1) {
        throw _bad('Only stored and MSZIP CAB folders are supported.');
      }
      if (offset < fileOffset || offset > _cabinetSize) {
        throw _bad('A CAB folder overlaps metadata or exceeds the input.');
      }
      blockCount += count;
      if (blockCount > _maxBlocks) {
        throw _bad('The CAB exceeds the data-block count safety limit.');
      }
      if (offset < firstData) firstData = offset;
      folders.add(_CabFolder(offset, count, method));
    }

    final table = await _metadata(fileOffset, firstData - fileOffset);
    final files = ByteData.sublistView(table);
    final members = <ViewerArchiveMember>[];
    cursor = 0;
    for (var i = 0; i < fileCount; i++) {
      if (cursor > table.length - 16) {
        throw _bad('Truncated CAB file metadata.');
      }
      final size = files.getUint32(cursor, Endian.little);
      final offset = files.getUint32(cursor + 4, Endian.little);
      final folder = files.getUint16(cursor + 8, Endian.little);
      final date = files.getUint16(cursor + 10, Endian.little);
      final time = files.getUint16(cursor + 12, Endian.little);
      final attributes = files.getUint16(cursor + 14, Endian.little);
      if (folder >= folderCount || folder >= 0xfffd) {
        throw _bad(
          'Split CAB members and invalid folder references are unavailable.',
        );
      }
      if ((attributes & ~0xe7) != 0) {
        throw _bad('Unsupported CAB file attributes.');
      }
      cursor += 16;
      final start = cursor;
      while (cursor < table.length && table[cursor] != 0) {
        if (cursor - start >= _maxNameBytes) {
          throw _bad('The CAB member name exceeds the safety limit.');
        }
        cursor++;
      }
      if (cursor == table.length || cursor == start) {
        throw _bad('Missing or unterminated CAB member name.');
      }
      final nameBytes = Uint8List.sublistView(table, start, cursor++);
      final String storedName;
      if ((attributes & 0x80) != 0) {
        storedName = utf8.decode(nameBytes);
      } else {
        if (nameBytes.any((byte) => byte >= 128)) {
          throw _bad(
            'CAB names using an unspecified legacy code page are unavailable.',
          );
        }
        storedName = ascii.decode(nameBytes);
      }
      final path = _memberPath(storedName);
      members.add(
        ViewerArchiveMember(
          name: path.name,
          size: size,
          isFile: true,
          isEncrypted: false,
          modified: _dosDate(date, time),
          pathEscapedRoot: path.unsafe,
          index: members.length,
        ),
      );
      locations.add((folder: folder, offset: offset));
    }

    final ranges = <({int start, int end})>[];
    for (final folder in folders) {
      cursor = folder.offset;
      for (var i = 0; i < folder.count; i++) {
        final bytes = await _metadata(cursor, 8 + dataReserve);
        final data = ByteData.sublistView(bytes);
        final packedSize = data.getUint16(4, Endian.little);
        final size = data.getUint16(6, Endian.little);
        if (size == 0 ||
            size > _blockSize ||
            (i < folder.count - 1 && size != _blockSize) ||
            packedSize == 0 ||
            packedSize > _blockSize + 12 ||
            (folder.method == 0 && packedSize != size)) {
          throw _bad('Invalid or split CAB data block.');
        }
        if (size > maxFolderBytes - folder.size) {
          throw _bad('A CAB folder exceeds the decoded-folder safety limit.');
        }
        final payloadOffset = cursor + bytes.length;
        _checkRange(payloadOffset, packedSize);
        folder.blocks.add(
          _CabBlock(
            payloadOffset,
            packedSize,
            size,
            data.getUint32(0, Endian.little),
            _checksum(Uint8List.sublistView(bytes, 4)),
          ),
        );
        folder.size += size;
        cursor = payloadOffset + packedSize;
      }
      if (cursor > folder.offset) {
        ranges.add((start: folder.offset, end: cursor));
      }
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < ranges.length; i++) {
      if (ranges[i].start < ranges[i - 1].end) {
        throw _bad('CAB folder data ranges overlap.');
      }
    }
    for (var i = 0; i < members.length; i++) {
      final location = locations[i];
      final size = folders[location.folder].size;
      if (location.offset > size || members[i].size > size - location.offset) {
        throw _bad('A CAB member extends beyond its decoded folder.');
      }
    }
    return ViewerArchive.reader(
      formatName: 'cab',
      members: members,
      notices: const [
        'Single-cabinet stored and MSZIP files. Publisher signatures and '
            'application-specific reserved data are not verified. CAB times '
            'have no time-zone information.',
      ],
      read: read,
      close: close,
    );
  }

  Future<Uint8List> read(ViewerArchiveMember member, int requestedLimit) {
    final result = _pending.then((_) async {
      if (_closed) throw _bad('The CAB archive is closed.');
      if (member.size > maxMemberBytes || member.size > requestedLimit) {
        throw _bad('The CAB member exceeds the read safety limit.');
      }
      final location = locations[member.index];
      if (_cachedFolder != location.folder) {
        _cachedBytes = null;
        _cachedFolder = -1;
        final folder = folders[location.folder];
        final decoded = Uint8List(folder.size);
        var offset = 0;
        for (final block in folder.blocks) {
          final packed = await _read(block.offset, block.packedSize);
          if (block.checksum != 0 &&
              ((_checksum(packed) ^ block.headerChecksum) & 0xffffffff) !=
                  block.checksum) {
            throw _bad('CAB data-block checksum mismatch.');
          }
          final Uint8List bytes;
          if (folder.method == 0) {
            bytes = packed;
          } else {
            final start = offset > _blockSize ? offset - _blockSize : 0;
            bytes = _inflateMszip(
              packed,
              Uint8List.sublistView(decoded, start, offset),
              block.size,
            );
          }
          decoded.setRange(offset, offset + block.size, bytes);
          offset += block.size;
        }
        if (_closed) throw _bad('The CAB archive is closed.');
        _cachedBytes = decoded;
        _cachedFolder = location.folder;
      }
      return Uint8List.fromList(
        Uint8List.sublistView(
          _cachedBytes!,
          location.offset,
          location.offset + member.size,
        ),
      );
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  void _checkRange(int offset, int length) {
    if (offset < 0 ||
        length < 0 ||
        offset > _cabinetSize ||
        length > _cabinetSize - offset) {
      throw _bad('A CAB record extends beyond the available input.');
    }
  }

  Future<Uint8List> _read(int offset, int length) async {
    if (_closed) throw _bad('The CAB archive is closed.');
    _checkRange(offset, length);
    final bytes = await source.read(offset, length);
    if (_closed || bytes.length != length) {
      throw _bad('The CAB source closed or returned a truncated record.');
    }
    return bytes;
  }

  Future<Uint8List> _metadata(int offset, int length) {
    if (length < 0 || length > _maxMetadataBytes - _metadataBytes) {
      throw _bad('The CAB exceeds the metadata safety limit.');
    }
    _metadataBytes += length;
    return _read(offset, length);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _cachedBytes = null;
    _cachedFolder = -1;
    try {
      await source.close();
    } catch (_) {
      // Preserve parse errors and idempotent ownership on cleanup failure.
    }
  }
}

class _CabFolder {
  _CabFolder(this.offset, this.count, this.method);
  final int offset, count, method;
  final blocks = <_CabBlock>[];
  var size = 0;
}

class _CabBlock {
  const _CabBlock(
    this.offset,
    this.packedSize,
    this.size,
    this.checksum,
    this.headerChecksum,
  );
  final int offset, packedSize, size, checksum, headerChecksum;
}

Uint8List _inflateMszip(Uint8List packed, Uint8List history, int size) {
  if (packed.length < 3 || packed[0] != 0x43 || packed[1] != 0x4b) {
    throw _bad('Missing MSZIP block signature.');
  }
  // A non-final stored DEFLATE block seeds the public inflater's dictionary.
  // This preserves exactly the preceding 32 KiB without changing codec state
  // or sharing Huffman tables between independent MSZIP streams. Its emitted
  // prefix is excluded from the result and included in the hard output bound.
  final prefix = Uint8List(history.length + 5);
  ByteData.sublistView(prefix)
    ..setUint16(1, history.length, Endian.little)
    ..setUint16(3, 0xffff ^ history.length, Endian.little);
  prefix.setRange(5, prefix.length, history);
  final output = Uint8List(history.length + size);
  var received = 0;
  final inflater = codecs.RawInflater(
    onOutput: (chunk) {
      if (chunk.length > output.length - received) {
        throw _bad('An MSZIP block exceeds its declared decoded length.');
      }
      output.setRange(received, received + chunk.length, chunk);
      received += chunk.length;
    },
  );
  try {
    inflater.addInput(prefix);
    final compressed = Uint8List.sublistView(packed, 2);
    final consumed = inflater.addInput(compressed);
    inflater.finish();
    if (consumed != compressed.length ||
        inflater.takeLeftoverBytes().isNotEmpty ||
        received != output.length) {
      throw _bad('An MSZIP block has trailing bytes or an incorrect length.');
    }
  } on FormatException catch (error) {
    throw _bad('Invalid MSZIP compression: ${error.message}');
  }
  return Uint8List.sublistView(output, history.length);
}

int _checksum(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var sum = 0;
  var offset = 0;
  for (; offset + 4 <= bytes.length; offset += 4) {
    sum ^= data.getUint32(offset, Endian.little);
  }
  // CAB's final 1–3 bytes are folded high byte first, unlike full words.
  var tail = 0;
  for (; offset < bytes.length; offset++) {
    tail = (tail << 8) | bytes[offset];
  }
  return (sum ^ tail) & 0xffffffff;
}

({String name, bool unsafe}) _memberPath(String stored) {
  final path = stored.replaceAll('\\', '/');
  var unsafe =
      path.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(path) ||
      path.codeUnits.any((c) => c < 32 || c == 127);
  final parts = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      unsafe = true;
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      if (part.contains(':')) unsafe = true;
      parts.add(part);
    }
  }
  if (parts.isEmpty) throw _bad('A CAB member has an empty normalized name.');
  return (name: parts.join('/'), unsafe: unsafe);
}

DateTime? _dosDate(int date, int time) {
  if (date == 0 && time == 0) return null;
  final year = 1980 + (date >> 9);
  final month = (date >> 5) & 15;
  final day = date & 31;
  final hour = time >> 11;
  final minute = (time >> 5) & 63;
  final second = (time & 31) * 2;
  // Validate the calendar without the host's daylight-saving rules: a CAB
  // timestamp need not have originated in the current machine's time zone.
  final result = DateTime.utc(year, month, day, hour, minute, second);
  if (result.year != year ||
      result.month != month ||
      result.day != day ||
      result.hour != hour ||
      result.minute != minute ||
      result.second != second) {
    throw _bad('Invalid CAB date or time.');
  }
  return DateTime(year, month, day, hour, minute, second);
}

ArchiveViewException _bad(String message) => ArchiveViewException(
  message,
  code: ArchiveMessageCode.corrupt,
  arguments: {'detail': message},
);
