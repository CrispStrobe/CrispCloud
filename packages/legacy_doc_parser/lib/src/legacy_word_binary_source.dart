// SPDX-License-Identifier: MPL-2.0

part of 'legacy_word_structured_parser.dart';

class _Bytes {
  _Bytes(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  int get length => bytes.length;
  void require(int offset, int count) {
    if (offset < 0 || count < 0 || offset > length - count) {
      throw const FormatException('Truncated Word binary document.');
    }
  }

  int u8(int offset) {
    require(offset, 1);
    return bytes[offset];
  }

  int u16(int offset) {
    require(offset, 2);
    return data.getUint16(offset, Endian.little);
  }

  int i16(int offset) {
    require(offset, 2);
    return data.getInt16(offset, Endian.little);
  }

  int u32(int offset) {
    require(offset, 4);
    return data.getUint32(offset, Endian.little);
  }

  int i32(int offset) {
    require(offset, 4);
    return data.getInt32(offset, Endian.little);
  }

  Uint8List slice(int offset, int count) {
    require(offset, count);
    return Uint8List.sublistView(bytes, offset, offset + count);
  }
}

class _Piece {
  const _Piece(
    this.startCp,
    this.endCp,
    this.offset,
    this.compressed,
    this.prm,
  );
  final int startCp;
  final int endCp;
  final int offset;
  final bool compressed;
  final int prm;
  int fc(int cp) => offset + (cp - startCp) * (compressed ? 1 : 2);
}

class _BinarySource {
  _BinarySource(Uint8List bytes) {
    compound = BoundedCfbReader(bytes);
    final stream = compound.readPath('WordDocument');
    if (stream == null || stream.length < 32) {
      throw const FormatException('The WordDocument stream is missing.');
    }
    word = _Bytes(stream);
    if (word.u16(0) != 0xa5ec) {
      throw const FormatException('This is not a Word binary document.');
    }
    version = word.u16(2);
    if (!const {0xc1, 0xd9, 0x101, 0x10c, 0x112}.contains(version)) {
      throw const FormatException(
        'This older Word binary version is not supported. Save it as DOCX.',
      );
    }
    final flags = word.u16(10);
    if ((flags & 0x8100) != 0) {
      throw const FormatException(
        'This Word document is encrypted. Open it in Word and save an unlocked copy.',
      );
    }
    if (word.u16(32) != 14 || word.u16(62) != 22) {
      throw const FormatException('Invalid Word FIB array lengths.');
    }
    final declaredExtent = word.u32(64);
    if (declaredExtent != 0) {
      word = _Bytes(word.slice(0, declaredExtent));
    } else {
      // Historical minimal exports sometimes omit cbMac. Retain their text
      // compatibility, but surface that the full physical extent was needed.
      missingDeclaredExtent = true;
    }
    bodyLength = word.u32(76);
    if (bodyLength > 4 * 1024 * 1024) {
      throw const FormatException('Word text exceeds the preview size limit.');
    }
    storyLengths = [
      for (final index in [4, 5, 7, 8, 9, 10]) word.u32(64 + index * 4),
    ];
    totalLength = storyLengths.fold(bodyLength, (sum, count) => sum + count);
    if (totalLength > 8 * 1024 * 1024 || storyLengths.any((count) => count > 4 * 1024 * 1024)) {
      throw const FormatException('Word stories exceed the text size limit.');
    }
    pairCount = word.u16(152);
    if (pairCount < 34 || pairCount > 183) {
      throw const FormatException('Invalid Word FIB offset count.');
    }
    word.require(154, pairCount * 8);
    final selected = compound.readPath(
      (flags & 0x0200) != 0 ? '1Table' : '0Table',
    );
    if (selected == null) {
      throw const FormatException('The selected Word text table is missing.');
    }
    table = _Bytes(selected);
    // An empty main story is valid, including older files whose otherwise
    // unused CLX contains a zero-length CP range. No body data is consulted.
    if (totalLength == 0) return;
    final clx = pair(33);
    var cursor = clx.$1;
    final end = cursor + clx.$2;
    while (cursor < end && table.u8(cursor) == 1) {
      if (cursor > end - 3) {
        throw const FormatException('Truncated Word text properties.');
      }
      final count = table.u16(cursor + 1);
      if (count > end - cursor - 3 || prcs.length >= 32768) {
        throw const FormatException('Invalid Word piece properties.');
      }
      prcs.add(table.slice(cursor + 3, count));
      cursor += 3 + count;
    }
    if (cursor > end - 5 || table.u8(cursor) != 2) {
      throw const FormatException('Word has no valid text piece table.');
    }
    final size = table.u32(cursor + 1);
    cursor += 5;
    if (size < 16 || (size - 4) % 12 != 0 || size != end - cursor) {
      throw const FormatException('Invalid Word text piece table size.');
    }
    final count = (size - 4) ~/ 12;
    if (count > 100000 || table.u32(cursor) != 0) {
      throw const FormatException('Invalid Word text piece count or start.');
    }
    final records = cursor + (count + 1) * 4;
    for (var index = 0; index < count; index++) {
      final start = table.u32(cursor + index * 4);
      final finish = table.u32(cursor + (index + 1) * 4);
      if (finish <= start || finish > 0x7fffffff) {
        throw const FormatException('Word text positions are not ordered.');
      }
      final packed = table.u32(records + index * 8 + 2);
      if ((packed & 0x80000000) != 0) {
        throw const FormatException('Invalid Word text piece offset.');
      }
      final compressed = (packed & 0x40000000) != 0;
      final raw = packed & 0x3fffffff;
      if (compressed && raw.isOdd) {
        throw const FormatException('Invalid compressed Word text offset.');
      }
      final offset = compressed ? raw ~/ 2 : raw;
      word.require(offset, (finish - start) * (compressed ? 1 : 2));
      final prm = table.u16(records + index * 8 + 6);
      if ((prm & 1) != 0 && (prm >> 1) >= prcs.length) {
        throw const FormatException('Invalid Word piece-property reference.');
      }
      pieces.add(_Piece(start, finish, offset, compressed, prm));
    }
    final storyTotal = storyLengths.fold(
      bodyLength,
      (sum, count) => sum + count,
    );
    final limit = pieces.last.endCp;
    if (storyTotal > 0x7fffffff ||
        limit < bodyLength ||
        (limit != storyTotal && limit != storyTotal + 1)) {
      throw const FormatException('Word text is incomplete.');
    }
  }

  late final BoundedCfbReader compound;
  late _Bytes word;
  late final _Bytes table;
  late final int version;
  late final int bodyLength;
  late final int totalLength;
  late final int pairCount;
  late final List<int> storyLengths;
  final pieces = <_Piece>[];
  final prcs = <Uint8List>[];
  bool missingDeclaredExtent = false;
  _Bytes? _data;

  (int, int) pair(int index) {
    if (index >= pairCount) return (0, 0);
    final offset = word.u32(154 + index * 8);
    final length = word.u32(158 + index * 8);
    if (length > 0) table.require(offset, length);
    return (offset, length);
  }

  _Bytes get data {
    final existing = _data;
    if (existing != null) return existing;
    final stream = compound.readPath('Data');
    if (stream == null) {
      throw const FormatException('Referenced Word data stream is missing.');
    }
    return _data = _Bytes(stream);
  }

  _Piece pieceAt(int cp) {
    var low = 0;
    var high = pieces.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final piece = pieces[mid];
      if (cp < piece.startCp) {
        high = mid;
      } else if (cp >= piece.endCp) {
        low = mid + 1;
      } else {
        return piece;
      }
    }
    throw const FormatException('Word character has no text piece.');
  }

  int unitAt(int cp) {
    final piece = pieceAt(cp);
    final fc = piece.fc(cp);
    if (!piece.compressed) return word.u16(fc);
    final unit = word.u8(fc);
    return _wordCompressedUnicode[unit] ?? unit;
  }
}

// [MS-DOC] FcCompressed mapping; the remaining bytes map to their own Unicode
// code points, not to a locale-dependent encoding or full Windows-1252.
const _wordCompressedUnicode = <int, int>{
  0x82: 0x201a,
  0x83: 0x0192,
  0x84: 0x201e,
  0x85: 0x2026,
  0x86: 0x2020,
  0x87: 0x2021,
  0x88: 0x02c6,
  0x89: 0x2030,
  0x8a: 0x0160,
  0x8b: 0x2039,
  0x8c: 0x0152,
  0x91: 0x2018,
  0x92: 0x2019,
  0x93: 0x201c,
  0x94: 0x201d,
  0x95: 0x2022,
  0x96: 0x2013,
  0x97: 0x2014,
  0x98: 0x02dc,
  0x99: 0x2122,
  0x9a: 0x0161,
  0x9b: 0x203a,
  0x9c: 0x0153,
  0x9f: 0x0178,
};
