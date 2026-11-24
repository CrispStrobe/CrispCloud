import 'dart:typed_data';

import '../cos/pdf_cos.dart';
import '../cos/pdf_open_error.dart';

/// ISO 32000-1 §7.4.6 /CCITTFaxDecode: T.4 one- and two-dimensional
/// Group 3 and T.6 Group 4. The engine uses expanded 8-bit gray samples.
abstract final class PdfCcitt {
  static const int _maxPixels = 16 * 1024 * 1024;
  static const int _maxDimension = 8192;

  static Uint8List decode(
    Uint8List data,
    PdfCosDict parm, {
    int? imageWidth,
    int? imageHeight,
  }) {
    final int columns = pdfCosInt(parm['Columns']) ?? 1728;
    final int declaredRows = pdfCosInt(parm['Rows']) ?? 0;
    final int rows = declaredRows == 0 ? imageHeight ?? 0 : declaredRows;
    final int k = pdfCosInt(parm['K']) ?? 0;
    final bool blackIs1 = _flag(parm, 'BlackIs1', false);
    final bool byteAlign = _flag(parm, 'EncodedByteAlign', false);
    final bool endOfLine = _flag(parm, 'EndOfLine', false);
    final bool endOfBlock = _flag(parm, 'EndOfBlock', true);
    if (columns <= 0 ||
        columns > _maxDimension ||
        rows < 0 ||
        rows > _maxDimension ||
        rows * columns > _maxPixels ||
        data.length > 16 * 1024 * 1024 ||
        (imageWidth != null && imageWidth != columns) ||
        (imageHeight != null && imageHeight != rows)) {
      _invalid();
    }
    final int pixelRows = _maxPixels ~/ columns;
    final int maxRows = rows > 0
        ? rows
        : (pixelRows < _maxDimension ? pixelRows : _maxDimension);
    final _BitIn bits = _BitIn(data);
    final BytesBuilder out = BytesBuilder(copy: false);
    List<int> ref = <int>[];
    var decodedRows = 0;
    // For a known image height, stop at its last complete row. Some PDF
    // producers omit the optional-in-practice trailing RTC/EOFB marker.
    while (decodedRows < maxRows) {
      if (endOfBlock && _takeEnd(bits, k)) {
        break;
      }
      if (rows == 0 && !endOfBlock && bits.onlyPadding) {
        break;
      }
      if (k >= 0 && !bits.takeEol() && endOfLine) {
        _invalid();
      }
      final bool oneDimensional = k == 0 || (k > 0 && bits.read(1) == 1);
      if (k > 0 && decodedRows == 0 && !oneDimensional) {
        _invalid();
      }
      ref = oneDimensional
          ? _g3(
              bits,
              columns,
              allowShortRow: k == 0 && rows > 0 && !endOfLine && !byteAlign,
            )
          : _g4(bits, columns, ref);
      out.add(_row(columns, ref, blackIs1));
      decodedRows++;
      if (byteAlign) {
        bits.align();
      }
    }
    if (decodedRows == 0 || (rows != 0 && decodedRows != rows)) {
      _invalid();
    }
    if (rows == 0 && decodedRows == maxRows &&
        !(endOfBlock ? _takeEnd(bits, k) : bits.onlyPadding)) {
      _invalid();
    }
    return out.takeBytes();
  }

  static bool _flag(PdfCosDict parm, String name, bool fallback) {
    final PdfCos? value = parm[name];
    return value is PdfCosBool ? value.value : fallback;
  }

  static Never _invalid() {
    throw const PdfFilterUnsupported('CCITTFaxDecode');
  }

  static bool _takeEnd(_BitIn bits, int k) {
    if (k < 0) {
      // Group 4 EOFB is two consecutive 12-bit EOL words.
      if (bits.peek(24) != 0x001001) {
        return false;
      }
      bits.read(24);
      return true;
    }
    // Group 3 RTC is six EOL words, each tagged 1 in mixed mode.
    final int start = bits.position;
    for (var i = 0; i < 6; i++) {
      if (!bits.takeEol() || (k > 0 && bits.peek(1) != 1)) {
        bits.position = start;
        return false;
      }
      if (k > 0) {
        bits.read(1);
      }
    }
    return true;
  }

  static List<int> _g3(
    _BitIn bits,
    int columns, {
    required bool allowShortRow,
  }) {
    final List<int> changes = <int>[];
    var a0 = 0;
    var white = true;
    while (a0 < columns) {
      // Some legacy Group 3 scans terminate a partial row with an EOL.
      // Require that marker at a run boundary and leave it for the next row.
      if (allowShortRow && a0 > 0 && bits.atEol) {
        if (!white) {
          changes.removeLast();
        }
        break;
      }
      final int run = _run(bits, white, columns - a0);
      // A black-leading line begins with a zero-length white run.
      if (run == 0 && !(a0 == 0 && white && changes.isEmpty)) {
        _invalid();
      }
      a0 += run;
      _addChange(changes, a0, columns);
      white = !white;
    }
    return changes;
  }

  static List<int> _g4(_BitIn bits, int columns, List<int> ref) {
    final List<int> changes = <int>[];
    // Imaginary white sample just before column zero.
    var a0 = -1;
    var white = true;
    var refIndex = 0;
    while (a0 < columns) {
      // The reference cursor is monotonic, so alternating-pixel rows
      // do not cause a quadratic scan over the reference line.
      while (refIndex < ref.length && ref[refIndex] <= a0) {
        refIndex++;
      }
      final int j = refIndex.isEven == white ? refIndex : refIndex + 1;
      final int b1 = j < ref.length ? ref[j] : columns;
      final int b2 = j + 1 < ref.length ? ref[j + 1] : columns;
      if (bits.peek(4) == 1) {
        bits.read(4); // Pass.
        if (b2 <= a0) {
          _invalid();
        }
        a0 = b2;
        continue;
      }
      if (bits.peek(3) == 1) {
        bits.read(3); // Horizontal: two terminating runs.
        final int start = a0 < 0 ? 0 : a0;
        final int a1 = start + _run(bits, white, columns - start);
        final int a2 = a1 + _run(bits, !white, columns - a1);
        if (a2 <= start ||
            (a1 == start && a0 != -1) ||
            (a1 == a2 && a2 != columns)) {
          _invalid();
        }
        _addChange(changes, a1, columns);
        _addChange(changes, a2, columns);
        a0 = a2;
        continue;
      }
      final int a1 = b1 + _vertical(bits);
      if (a1 <= a0 || a1 < 0 || a1 > columns) {
        _invalid();
      }
      a0 = a1;
      _addChange(changes, a0, columns);
      white = !white;
    }
    return changes;
  }

  static void _addChange(List<int> changes, int x, int columns) {
    if (x < columns) {
      if (changes.isNotEmpty && x <= changes.last) {
        _invalid();
      }
      changes.add(x);
    }
  }

  static int _vertical(_BitIn bits) {
    if (bits.peek(1) == 1) {
      bits.read(1);
      return 0;
    }
    if (bits.peek(3) == 3) {
      bits.read(3);
      return 1;
    }
    if (bits.peek(3) == 2) {
      bits.read(3);
      return -1;
    }
    if (bits.peek(6) == 3) {
      bits.read(6);
      return 2;
    }
    if (bits.peek(6) == 2) {
      bits.read(6);
      return -2;
    }
    if (bits.peek(7) == 3) {
      bits.read(7);
      return 3;
    }
    if (bits.peek(7) == 2) {
      bits.read(7);
      return -3;
    }
    // Uncompressed/extension codes and truncated/invalid modes are not
    // vertical-zero codes. Do not paint a fabricated successful row.
    _invalid();
  }

  static int _run(_BitIn bits, bool white, int remaining) {
    final Map<int, int> table = white ? _whiteCodes : _blackCodes;
    var total = 0;
    while (true) {
      var key = 1;
      int? run;
      for (var n = 1; n <= 13; n++) {
        key = (key << 1) | bits.read(1);
        run = table[key];
        if (run != null) {
          break;
        }
      }
      if (run == null) {
        _invalid();
      }
      total += run;
      if (total > remaining) {
        _invalid();
      }
      if (run < 64) {
        return total;
      }
    }
  }

  static Uint8List _row(int columns, List<int> changes, bool blackIs1) {
    final Uint8List out = Uint8List(columns);
    var x = 0;
    var black = false;
    for (final int end in <int>[...changes, columns]) {
      out.fillRange(x, end, black == blackIs1 ? 0xff : 0);
      x = end;
      black = !black;
    }
    return out;
  }
}

class _BitIn {
  _BitIn(this.data);
  final Uint8List data;
  int position = 0;

  int get remaining => data.length * 8 - position;
  bool get onlyPadding => remaining <= 7 && peek(remaining) == 0;

  int peek(int n) {
    if (n > remaining) {
      return -1;
    }
    var value = 0;
    for (int p = position; p < position + n; p++) {
      value = (value << 1) | ((data[p >> 3] >> (7 - (p & 7))) & 1);
    }
    return value;
  }

  int read(int n) {
    final int value = peek(n);
    if (value < 0) {
      PdfCcitt._invalid();
    }
    position += n;
    return value;
  }

  bool takeEol() {
    final int start = position;
    // T.4 permits zero fill before the EOL word.
    while (peek(1) == 0) {
      position++;
    }
    if (position - start >= 11 && peek(1) == 1) {
      position++;
      return true;
    }
    position = start;
    return false;
  }

  bool get atEol {
    final prefix = peek(12);
    if (prefix < 0 || prefix > 1) return false;
    final start = position;
    final found = takeEol();
    position = start;
    return found;
  }

  void align() {
    final int padding = (8 - (position & 7)) & 7;
    if (read(padding) != 0) {
      PdfCcitt._invalid();
    }
  }
}

// ITU-T T.4 terminating (0..63) and makeup (64..2560) code words.
// Each key prefixes a sentinel 1 to the actual word so leading zeros and
// lengths are preserved (e.g. key 0b1000111 represents the word 000111).
const Map<int, int> _whiteCodes = <int, int>{
  0x135: 0,
  0x47: 1,
  0x17: 2,
  0x18: 3,
  0x1b: 4,
  0x1c: 5,
  0x1e: 6,
  0x1f: 7,
  0x33: 8,
  0x34: 9,
  0x27: 10,
  0x28: 11,
  0x48: 12,
  0x43: 13,
  0x74: 14,
  0x75: 15,
  0x6a: 16,
  0x6b: 17,
  0xa7: 18,
  0x8c: 19,
  0x88: 20,
  0x97: 21,
  0x83: 22,
  0x84: 23,
  0xa8: 24,
  0xab: 25,
  0x93: 26,
  0xa4: 27,
  0x98: 28,
  0x102: 29,
  0x103: 30,
  0x11a: 31,
  0x11b: 32,
  0x112: 33,
  0x113: 34,
  0x114: 35,
  0x115: 36,
  0x116: 37,
  0x117: 38,
  0x128: 39,
  0x129: 40,
  0x12a: 41,
  0x12b: 42,
  0x12c: 43,
  0x12d: 44,
  0x104: 45,
  0x105: 46,
  0x10a: 47,
  0x10b: 48,
  0x152: 49,
  0x153: 50,
  0x154: 51,
  0x155: 52,
  0x124: 53,
  0x125: 54,
  0x158: 55,
  0x159: 56,
  0x15a: 57,
  0x15b: 58,
  0x14a: 59,
  0x14b: 60,
  0x132: 61,
  0x133: 62,
  0x134: 63,
  0x3b: 64,
  0x32: 128,
  0x57: 192,
  0xb7: 256,
  0x136: 320,
  0x137: 384,
  0x164: 448,
  0x165: 512,
  0x168: 576,
  0x167: 640,
  0x2cc: 704,
  0x2cd: 768,
  0x2d2: 832,
  0x2d3: 896,
  0x2d4: 960,
  0x2d5: 1024,
  0x2d6: 1088,
  0x2d7: 1152,
  0x2d8: 1216,
  0x2d9: 1280,
  0x2da: 1344,
  0x2db: 1408,
  0x298: 1472,
  0x299: 1536,
  0x29a: 1600,
  0x58: 1664,
  0x29b: 1728,
  0x808: 1792,
  0x80c: 1856,
  0x80d: 1920,
  0x1012: 1984,
  0x1013: 2048,
  0x1014: 2112,
  0x1015: 2176,
  0x1016: 2240,
  0x1017: 2304,
  0x101c: 2368,
  0x101d: 2432,
  0x101e: 2496,
  0x101f: 2560,
};

const Map<int, int> _blackCodes = <int, int>{
  0x437: 0,
  0xa: 1,
  0x7: 2,
  0x6: 3,
  0xb: 4,
  0x13: 5,
  0x12: 6,
  0x23: 7,
  0x45: 8,
  0x44: 9,
  0x84: 10,
  0x85: 11,
  0x87: 12,
  0x104: 13,
  0x107: 14,
  0x218: 15,
  0x417: 16,
  0x418: 17,
  0x408: 18,
  0x867: 19,
  0x868: 20,
  0x86c: 21,
  0x837: 22,
  0x828: 23,
  0x817: 24,
  0x818: 25,
  0x10ca: 26,
  0x10cb: 27,
  0x10cc: 28,
  0x10cd: 29,
  0x1068: 30,
  0x1069: 31,
  0x106a: 32,
  0x106b: 33,
  0x10d2: 34,
  0x10d3: 35,
  0x10d4: 36,
  0x10d5: 37,
  0x10d6: 38,
  0x10d7: 39,
  0x106c: 40,
  0x106d: 41,
  0x10da: 42,
  0x10db: 43,
  0x1054: 44,
  0x1055: 45,
  0x1056: 46,
  0x1057: 47,
  0x1064: 48,
  0x1065: 49,
  0x1052: 50,
  0x1053: 51,
  0x1024: 52,
  0x1037: 53,
  0x1038: 54,
  0x1027: 55,
  0x1028: 56,
  0x1058: 57,
  0x1059: 58,
  0x102b: 59,
  0x102c: 60,
  0x105a: 61,
  0x1066: 62,
  0x1067: 63,
  0x40f: 64,
  0x10c8: 128,
  0x10c9: 192,
  0x105b: 256,
  0x1033: 320,
  0x1034: 384,
  0x1035: 448,
  0x206c: 512,
  0x206d: 576,
  0x204a: 640,
  0x204b: 704,
  0x204c: 768,
  0x204d: 832,
  0x2072: 896,
  0x2073: 960,
  0x2074: 1024,
  0x2075: 1088,
  0x2076: 1152,
  0x2077: 1216,
  0x2052: 1280,
  0x2053: 1344,
  0x2054: 1408,
  0x2055: 1472,
  0x205a: 1536,
  0x205b: 1600,
  0x2064: 1664,
  0x2065: 1728,
  0x808: 1792,
  0x80c: 1856,
  0x80d: 1920,
  0x1012: 1984,
  0x1013: 2048,
  0x1014: 2112,
  0x1015: 2176,
  0x1016: 2240,
  0x1017: 2304,
  0x101c: 2368,
  0x101d: 2432,
  0x101e: 2496,
  0x101f: 2560,
};
