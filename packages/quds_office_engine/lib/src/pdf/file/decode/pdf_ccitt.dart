import 'dart:typed_data';

import '../cos/pdf_cos.dart';
import '../cos/pdf_open_error.dart';

/// ISO 32000-1 §7.4.6 `/CCITTFaxDecode` (Group 3 1-D and Group 4).
abstract final class PdfCcitt {
  /// Decodes to packed 1-bit rows (`Columns` bits, MSB first), then expands
  /// to 8-bit gray (`0x00` / `0xFF`).
  static Uint8List decode(Uint8List data, PdfCosDict parm) {
    final int columns = pdfCosInt(parm['Columns']) ?? 1728;
    final int rows = pdfCosInt(parm['Rows']) ?? 0;
    final int k = pdfCosInt(parm['K']) ?? 0;
    final bool blackIs1 = parm['BlackIs1'] is PdfCosBool
        ? (parm['BlackIs1'] as PdfCosBool).value
        : false;
    final bool byteAlign = parm['EncodedByteAlign'] is PdfCosBool
        ? (parm['EncodedByteAlign'] as PdfCosBool).value
        : false;
    if (columns <= 0 || columns > 8192) {
      throw const PdfFilterUnsupported('CCITTFaxDecode');
    }
    final _BitIn bits = _BitIn(data);
    final List<Uint8List> out = <Uint8List>[];
    List<int> ref = <int>[];
    final int maxRows = rows > 0 ? rows : 4096;
    for (int r = 0; r < maxRows; r++) {
      if (bits.done) {
        break;
      }
      // K < 0: Group 4. K == 0: Group 3 1-D. K > 0: mixed G3 2-D —
      // decode as 1-D (typed best-effort; see STANDARDS).
      final List<int> changes = k < 0
          ? _g4(bits, columns, ref)
          : _g3(bits, columns, byteAlign);
      if (changes.isEmpty && bits.done && out.isNotEmpty) {
        break;
      }
      ref = changes;
      out.add(_row(columns, changes, blackIs1));
    }
    if (out.isEmpty) {
      throw const PdfFilterUnsupported('CCITTFaxDecode');
    }
    final BytesBuilder gray = BytesBuilder(copy: false);
    for (final Uint8List row in out) {
      gray.add(row);
    }
    return gray.takeBytes();
  }

  static List<int> _g3(_BitIn bits, int columns, bool align) {
    if (bits.peek(12) == 1) {
      bits.skip(12);
    }
    final List<int> ch = <int>[];
    var a0 = 0;
    var white = true;
    while (a0 < columns) {
      final int? run = _run(bits, white);
      if (run == null) {
        break;
      }
      a0 += run;
      if (a0 > columns) {
        a0 = columns;
      }
      if (a0 > 0 && a0 < columns) {
        ch.add(a0);
      }
      white = !white;
    }
    if (align) {
      bits.byteAlign();
    }
    return ch;
  }

  static List<int> _g4(_BitIn bits, int columns, List<int> ref) {
    final List<int> ch = <int>[];
    var a0 = -1;
    var white = true;
    while (a0 < columns) {
      if (bits.peek(12) == 1) {
        bits.skip(12);
        break;
      }
      if (bits.peek(4) == 1) {
        bits.skip(4);
        a0 = _b2(ref, a0, white, columns);
        continue;
      }
      if (bits.peek(3) == 1) {
        bits.skip(3);
        final int r1 = _run(bits, white) ?? 0;
        final int r2 = _run(bits, !white) ?? 0;
        a0 = (a0 < 0 ? 0 : a0) + r1;
        _addChange(ch, a0, columns);
        a0 += r2;
        _addChange(ch, a0, columns);
        continue;
      }
      final int v = _vertical(bits);
      a0 = (_b1(ref, a0, white, columns) + v).clamp(0, columns);
      _addChange(ch, a0, columns);
      white = !white;
    }
    return ch;
  }

  static void _addChange(List<int> ch, int a0, int columns) {
    if (a0 > 0 && a0 < columns) {
      ch.add(a0);
    }
  }

  static int _vertical(_BitIn bits) {
    if (bits.peek(1) == 1) {
      bits.skip(1);
      return 0;
    }
    if (bits.peek(3) == 0x2) {
      bits.skip(3);
      return 1;
    }
    if (bits.peek(3) == 0x3) {
      bits.skip(3);
      return -1;
    }
    if (bits.peek(4) == 0x2) {
      bits.skip(4);
      return 2;
    }
    if (bits.peek(4) == 0x3) {
      bits.skip(4);
      return -2;
    }
    if (bits.peek(5) == 0x2) {
      bits.skip(5);
      return 3;
    }
    if (bits.peek(5) == 0x3) {
      bits.skip(5);
      return -3;
    }
    if (bits.peek(4) == 0x1) {
      bits.skip(4);
      return 0;
    }
    bits.skip(1);
    return 0;
  }

  /// First changing element on [ref] to the right of [a0] of opposite color.
  /// [ref] holds run boundaries; index 0 starts a black run (line starts white).
  static int _b1(List<int> ref, int a0, bool a0White, int columns) {
    final bool wantBlack = a0White;
    for (int i = 0; i < ref.length; i++) {
      if (ref[i] <= a0) {
        continue;
      }
      final bool startsBlack = i.isEven;
      if (startsBlack == wantBlack) {
        return ref[i];
      }
    }
    return columns;
  }

  static int _b2(List<int> ref, int a0, bool a0White, int columns) {
    final int b1 = _b1(ref, a0, a0White, columns);
    for (int i = 0; i < ref.length; i++) {
      if (ref[i] > b1) {
        return ref[i];
      }
    }
    return columns;
  }

  static int? _run(_BitIn bits, bool white) {
    var total = 0;
    while (true) {
      final int? code = white ? _white(bits) : _black(bits);
      if (code == null) {
        return total == 0 ? null : total;
      }
      total += code;
      if (code < 64) {
        return total;
      }
    }
  }

  static int? _white(_BitIn bits) {
    return _match(bits, _whiteCodes);
  }

  static int? _black(_BitIn bits) {
    return _match(bits, _blackCodes);
  }

  static int? _match(_BitIn bits, List<(int, int, int)> table) {
    for (int len = 2; len <= 13; len++) {
      final int v = bits.peek(len);
      for (final (int bitsv, int blen, int run) in table) {
        if (blen == len && bitsv == v) {
          bits.skip(len);
          return run;
        }
      }
    }
    return null;
  }

  static Uint8List _row(int columns, List<int> changes, bool blackIs1) {
    final Uint8List out = Uint8List(columns);
    var x = 0;
    var black = false;
    for (final int next in <int>[...changes, columns]) {
      final int end = next.clamp(0, columns);
      final int tone = black == blackIs1 ? 0xFF : 0x00;
      while (x < end) {
        out[x++] = tone;
      }
      black = !black;
    }
    return out;
  }
}

class _BitIn {
  _BitIn(this.data);
  final Uint8List data;
  var _i = 0;
  var _bit = 0;

  bool get done => _i >= data.length;

  int peek(int n) {
    var acc = 0;
    var i = _i;
    var bit = _bit;
    for (int k = 0; k < n; k++) {
      if (i >= data.length) {
        return acc << (n - k);
      }
      acc = (acc << 1) | ((data[i] >> (7 - bit)) & 1);
      bit++;
      if (bit == 8) {
        bit = 0;
        i++;
      }
    }
    return acc;
  }

  void skip(int n) {
    _bit += n;
    _i += _bit >> 3;
    _bit &= 7;
  }

  void byteAlign() {
    if (_bit != 0) {
      _bit = 0;
      _i++;
    }
  }
}

// (code, bitLength, runLength) — makeup (>=64) and terminating (<64).
const List<(int, int, int)> _whiteCodes = <(int, int, int)>[
  (0x35, 8, 0),
  (0x7, 6, 1),
  (0x7, 4, 2),
  (0x8, 4, 3),
  (0xB, 4, 4),
  (0xC, 4, 5),
  (0xE, 4, 6),
  (0xF, 4, 7),
  (0x13, 5, 8),
  (0x14, 5, 9),
  (0x7, 5, 10),
  (0x8, 5, 11),
  (0x8, 6, 12),
  (0x3, 6, 13),
  (0x34, 6, 14),
  (0x35, 6, 15),
  (0x2A, 6, 16),
  (0x2B, 6, 17),
  (0x27, 7, 18),
  (0xC, 7, 19),
  (0x8, 7, 20),
  (0x17, 7, 21),
  (0x3, 7, 22),
  (0x4, 7, 23),
  (0x28, 7, 24),
  (0x2B, 7, 25),
  (0x23, 7, 26),
  (0x24, 7, 27),
  (0x2, 7, 28),
  (0x3, 8, 29),
  (0x4, 8, 30),
  (0x5, 8, 31),
  (0x6, 8, 32),
  (0x7, 8, 33),
  (0x4, 8, 34),
  (0x5, 8, 35),
  (0x7, 8, 36),
  (0x4, 8, 37),
  (0x7, 8, 38),
  (0x18, 8, 39),
  (0x17, 8, 40),
  (0x18, 8, 41),
  (0x8, 8, 42),
  (0x67, 8, 43),
  (0x68, 8, 44),
  (0x6C, 8, 45),
  (0x37, 8, 46),
  (0x28, 8, 47),
  (0x17, 8, 48),
  (0x18, 8, 49),
  (0xCA, 8, 50),
  (0xCB, 8, 51),
  (0xCC, 8, 52),
  (0xCD, 8, 53),
  (0x68, 8, 54),
  (0x69, 8, 55),
  (0x6A, 8, 56),
  (0x6B, 8, 57),
  (0xD2, 8, 58),
  (0xD3, 8, 59),
  (0xD4, 8, 60),
  (0xD5, 8, 61),
  (0x6C, 8, 62),
  (0x6D, 8, 63),
  (0x1B, 5, 64),
  (0x12, 5, 128),
  (0x17, 6, 192),
  (0x37, 7, 256),
  (0x36, 8, 320),
  (0x37, 8, 384),
  (0x64, 8, 448),
  (0x65, 8, 512),
  (0x68, 8, 576),
  (0x67, 8, 640),
  (0xCC, 9, 704),
  (0xCD, 9, 768),
  (0xD2, 9, 832),
  (0xD3, 9, 896),
  (0xD4, 9, 960),
  (0xD5, 9, 1024),
  (0xD6, 9, 1088),
  (0xD7, 9, 1152),
  (0xD8, 9, 1216),
  (0xD9, 9, 1280),
  (0xDA, 9, 1344),
  (0xDB, 9, 1408),
  (0x98, 9, 1472),
  (0x99, 9, 1536),
  (0x9A, 9, 1600),
  (0x18, 6, 1664),
  (0x9B, 9, 1728),
];

const List<(int, int, int)> _blackCodes = <(int, int, int)>[
  (0x37, 10, 0),
  (0x2, 3, 1),
  (0x3, 2, 2),
  (0x2, 2, 3),
  (0x3, 3, 4),
  (0x3, 4, 5),
  (0x2, 4, 6),
  (0x3, 5, 7),
  (0x5, 6, 8),
  (0x4, 6, 9),
  (0x4, 7, 10),
  (0x5, 7, 11),
  (0x7, 7, 12),
  (0x4, 8, 13),
  (0x7, 8, 14),
  (0x18, 9, 15),
  (0x17, 10, 16),
  (0x18, 10, 17),
  (0x8, 10, 18),
  (0x67, 11, 19),
  (0x68, 11, 20),
  (0x6C, 11, 21),
  (0x37, 11, 22),
  (0x28, 11, 23),
  (0x17, 11, 24),
  (0x18, 11, 25),
  (0xCA, 11, 26),
  (0xCB, 11, 27),
  (0xCC, 11, 28),
  (0xCD, 11, 29),
  (0x68, 11, 30),
  (0x69, 11, 31),
  (0x6A, 11, 32),
  (0x6B, 11, 33),
  (0xD2, 11, 34),
  (0xD3, 11, 35),
  (0xD4, 11, 36),
  (0xD5, 11, 37),
  (0x6C, 11, 38),
  (0x6D, 11, 39),
  (0xDA, 11, 40),
  (0xDB, 11, 41),
  (0x54, 11, 42),
  (0x55, 11, 43),
  (0x56, 11, 44),
  (0x57, 11, 45),
  (0x64, 11, 46),
  (0x65, 11, 47),
  (0x52, 11, 48),
  (0x53, 11, 49),
  (0x24, 11, 50),
  (0x37, 11, 51),
  (0x38, 11, 52),
  (0x27, 11, 53),
  (0x28, 11, 54),
  (0x58, 11, 55),
  (0x59, 11, 56),
  (0x2B, 11, 57),
  (0x2C, 11, 58),
  (0x5A, 11, 59),
  (0x66, 11, 60),
  (0x67, 11, 61),
  (0x13, 10, 62),
  (0x14, 10, 63),
  (0xF, 10, 64),
  (0xC8, 12, 128),
  (0xC9, 12, 192),
  (0x5B, 12, 256),
  (0x33, 12, 320),
  (0x34, 12, 384),
  (0x35, 12, 448),
  (0x6C, 13, 512),
  (0x6D, 13, 576),
  (0x4A, 13, 640),
  (0x4B, 13, 704),
  (0x4C, 13, 768),
  (0x4D, 13, 832),
  (0x72, 13, 896),
  (0x73, 13, 960),
  (0x74, 13, 1024),
  (0x75, 13, 1088),
  (0x76, 13, 1152),
  (0x77, 13, 1216),
  (0x52, 13, 1280),
  (0x53, 13, 1344),
  (0x54, 13, 1408),
  (0x55, 13, 1472),
  (0x5A, 13, 1536),
  (0x5B, 13, 1600),
  (0x64, 13, 1664),
  (0x65, 13, 1728),
];
