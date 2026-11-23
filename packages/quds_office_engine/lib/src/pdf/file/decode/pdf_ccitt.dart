import 'dart:typed_data';

import '../cos/pdf_cos.dart';
import '../cos/pdf_open_error.dart';

/// ISO 32000-1 §7.4.6 `/CCITTFaxDecode` (Group 3 1-D and Group 4).
abstract final class PdfCcitt {
  static final _whiteRuns = _runTable(_whiteCodes);
  static final _blackRuns = _runTable(_blackCodes);

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
      final List<int>? changes = k < 0
          ? _g4(bits, columns, ref)
          : _g3(bits, columns, byteAlign);
      if (changes == null) {
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

  static List<int>? _g3(_BitIn bits, int columns, bool align) {
    bits.skipEndOfLine();
    final List<int> ch = <int>[];
    var a0 = 0;
    var white = true;
    while (a0 < columns) {
      final int? run = _run(bits, white);
      if (run == null) {
        if (!bits.seekEndOfLine()) return null;
        // Some encoders end short rows at EOL. Unwritten pixels stay white.
        if (!white) ch.removeLast();
        break;
      }
      a0 += run;
      // A zero-length initial white run means the first pixel is black.
      if (a0 < columns) {
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
    final table = white ? _whiteRuns : _blackRuns;
    var total = 0;
    while (true) {
      final int? code = _match(bits, table);
      if (code == null) {
        return null;
      }
      total += code;
      if (code < 64) {
        return total;
      }
    }
  }

  static Map<int, int> _runTable(List<(int, int, int)> codes) => {
    for (final (code, length, run) in codes) (1 << length) | code: run,
  };

  static int? _match(_BitIn bits, Map<int, int> table) {
    final int lookahead = bits.peek(13);
    final int remaining = bits.remaining;
    for (int len = 2; len <= 13 && len <= remaining; len++) {
      final int? run = table[(1 << len) | (lookahead >> (13 - len))];
      if (run != null) {
        bits.skip(len);
        return run;
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
      if (end > x) {
        out.fillRange(x, end, tone);
        x = end;
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

  int get remaining => (data.length - _i) * 8 - _bit;

  bool skipEndOfLine() {
    if (remaining < 12 || peek(12) > 1) return false;
    return seekEndOfLine();
  }

  bool seekEndOfLine() {
    // Fax encoders can insert zero fill bits before the 11-zero EOL marker.
    var zeros = 0;
    while (!done) {
      final bit = (data[_i] >> (7 - _bit)) & 1;
      skip(1);
      if (bit == 0) {
        zeros++;
      } else {
        if (zeros >= 11) return true;
        zeros = 0;
      }
    }
    return false;
  }

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
  (0x13, 7, 26),
  (0x24, 7, 27),
  (0x18, 7, 28),
  (0x2, 8, 29),
  (0x3, 8, 30),
  (0x1A, 8, 31),
  (0x1B, 8, 32),
  (0x12, 8, 33),
  (0x13, 8, 34),
  (0x14, 8, 35),
  (0x15, 8, 36),
  (0x16, 8, 37),
  (0x17, 8, 38),
  (0x28, 8, 39),
  (0x29, 8, 40),
  (0x2A, 8, 41),
  (0x2B, 8, 42),
  (0x2C, 8, 43),
  (0x2D, 8, 44),
  (0x4, 8, 45),
  (0x5, 8, 46),
  (0xA, 8, 47),
  (0xB, 8, 48),
  (0x52, 8, 49),
  (0x53, 8, 50),
  (0x54, 8, 51),
  (0x55, 8, 52),
  (0x24, 8, 53),
  (0x25, 8, 54),
  (0x58, 8, 55),
  (0x59, 8, 56),
  (0x5A, 8, 57),
  (0x5B, 8, 58),
  (0x4A, 8, 59),
  (0x4B, 8, 60),
  (0x32, 8, 61),
  (0x33, 8, 62),
  (0x34, 8, 63),
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
  ..._longMakeupCodes,
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
  (0xCA, 12, 26),
  (0xCB, 12, 27),
  (0xCC, 12, 28),
  (0xCD, 12, 29),
  (0x68, 12, 30),
  (0x69, 12, 31),
  (0x6A, 12, 32),
  (0x6B, 12, 33),
  (0xD2, 12, 34),
  (0xD3, 12, 35),
  (0xD4, 12, 36),
  (0xD5, 12, 37),
  (0xD6, 12, 38),
  (0xD7, 12, 39),
  (0x6C, 12, 40),
  (0x6D, 12, 41),
  (0xDA, 12, 42),
  (0xDB, 12, 43),
  (0x54, 12, 44),
  (0x55, 12, 45),
  (0x56, 12, 46),
  (0x57, 12, 47),
  (0x64, 12, 48),
  (0x65, 12, 49),
  (0x52, 12, 50),
  (0x53, 12, 51),
  (0x24, 12, 52),
  (0x37, 12, 53),
  (0x38, 12, 54),
  (0x27, 12, 55),
  (0x28, 12, 56),
  (0x58, 12, 57),
  (0x59, 12, 58),
  (0x2B, 12, 59),
  (0x2C, 12, 60),
  (0x5A, 12, 61),
  (0x66, 12, 62),
  (0x67, 12, 63),
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
  ..._longMakeupCodes,
];

// ITU-T T.4 Table 3b. These make-up codes are shared by both colors.
const List<(int, int, int)> _longMakeupCodes = <(int, int, int)>[
  (0x8, 11, 1792),
  (0xC, 11, 1856),
  (0xD, 11, 1920),
  (0x12, 12, 1984),
  (0x13, 12, 2048),
  (0x14, 12, 2112),
  (0x15, 12, 2176),
  (0x16, 12, 2240),
  (0x17, 12, 2304),
  (0x1C, 12, 2368),
  (0x1D, 12, 2432),
  (0x1E, 12, 2496),
  (0x1F, 12, 2560),
];
