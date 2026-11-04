/// Minimal QR Code (byte mode, ECC-M) encoder and PDF widget.
library;

import 'dart:typed_data';

import '../../pdf/pdf_canvas.dart';
import 'pw_core.dart';
import 'pw_flutter.dart';
import 'pw_types.dart';

/// QR error-correction level.
enum QrEcc { l, m, q, h }

/// Encodes UTF-8/Latin bytes into a QR module matrix (true = dark).
class QrEncoder {
  /// QrEncoder API.
  const QrEncoder({this.ecc = QrEcc.m});

  /// ecc API. Only [QrEcc.m] is fully tabled for versions 1–10.
  final QrEcc ecc;

  /// Returns a square matrix of modules.
  List<List<bool>> encode(String data) {
    final Uint8List bytes = Uint8List.fromList(data.codeUnits);
    final int version = _pickVersion(bytes.length);
    final _RsParams params = _rsParams(version);
    final List<int> codewords = _buildData(bytes, version, params);
    final List<int> full = _addEcc(codewords, params);
    final int size = _moduleCount(version);
    final List<List<int>> grid = List<List<int>>.generate(
      size,
      (_) => List<int>.filled(size, -1),
    );
    final List<List<bool>> locked = List<List<bool>>.generate(
      size,
      (_) => List<bool>.filled(size, false),
    );
    _drawFunctionPatterns(grid, locked, version);
    _drawCodewords(grid, locked, full);
    final int mask = _bestMask(grid, locked, version);
    _applyMask(grid, locked, mask);
    _drawFormat(grid, locked, mask);
    if (version >= 7) {
      _drawVersion(grid, locked, version);
    }
    return <List<bool>>[
      for (final List<int> row in grid)
        <bool>[for (final int cell in row) cell == 1],
    ];
  }

  int _pickVersion(int byteLen) {
    for (int v = 1; v <= 10; v++) {
      final _RsParams p = _rsParams(v);
      // mode(4) + length(8|16) + data + terminator.
      final int lenBits = v <= 9 ? 8 : 16;
      final int payloadBits = 4 + lenBits + byteLen * 8 + 4;
      if (payloadBits <= p.dataCodewords * 8) {
        return v;
      }
    }
    throw ArgumentError('QR data too long for versions 1–10 ECC-M');
  }

  static int _moduleCount(int version) => 17 + 4 * version;

  List<int> _buildData(Uint8List bytes, int version, _RsParams params) {
    final _BitBuffer bits = _BitBuffer()
      ..put(4, 4)
      ..put(bytes.length, version <= 9 ? 8 : 16);
    for (final int b in bytes) {
      bits.put(b, 8);
    }
    final int capacityBits = params.dataCodewords * 8;
    final int remain = capacityBits - bits.length;
    bits.put(0, remain.clamp(0, 4));
    while (bits.length % 8 != 0) {
      bits.put(0, 1);
    }
    final List<int> words = bits.toBytes();
    var pad = 0;
    while (words.length < params.dataCodewords) {
      words.add(pad.isEven ? 0xEC : 0x11);
      pad++;
    }
    return words;
  }

  List<int> _addEcc(List<int> data, _RsParams params) {
    final List<List<int>> dataBlocks = <List<int>>[];
    final List<List<int>> eccBlocks = <List<int>>[];
    int offset = 0;
    for (int i = 0; i < params.blocks; i++) {
      final int n = i < params.shortBlocks
          ? params.shortBlockData
          : params.shortBlockData + 1;
      final List<int> block = data.sublist(offset, offset + n);
      offset += n;
      dataBlocks.add(block);
      eccBlocks.add(_reedSolomon(block, params.eccPerBlock));
    }
    final List<int> result = <int>[];
    final int maxData = dataBlocks
        .map((List<int> b) => b.length)
        .reduce((int a, int b) => a > b ? a : b);
    for (int i = 0; i < maxData; i++) {
      for (final List<int> block in dataBlocks) {
        if (i < block.length) {
          result.add(block[i]);
        }
      }
    }
    for (int i = 0; i < params.eccPerBlock; i++) {
      for (final List<int> block in eccBlocks) {
        result.add(block[i]);
      }
    }
    return result;
  }

  static List<int> _reedSolomon(List<int> data, int eccLen) {
    final List<int> gen = _rsGenerator(eccLen);
    final List<int> res = List<int>.from(data)
      ..addAll(List<int>.filled(eccLen, 0));
    for (int i = 0; i < data.length; i++) {
      final int factor = res[i];
      if (factor == 0) {
        continue;
      }
      for (int j = 0; j < gen.length; j++) {
        res[i + j] ^= _gfMul(gen[j], factor);
      }
    }
    return res.sublist(data.length);
  }

  static List<int> _rsGenerator(int degree) {
    List<int> g = <int>[1];
    for (int i = 0; i < degree; i++) {
      final List<int> next = List<int>.filled(g.length + 1, 0);
      for (int j = 0; j < g.length; j++) {
        next[j] ^= g[j];
        next[j + 1] ^= _gfMul(g[j], _exp[i]);
      }
      g = next;
    }
    return g;
  }

  static int _gfMul(int a, int b) {
    if (a == 0 || b == 0) {
      return 0;
    }
    return _exp[(_log[a] + _log[b]) % 255];
  }

  void _set(
    List<List<int>> grid,
    List<List<bool>> locked,
    int r,
    int c,
    int value,
  ) {
    grid[r][c] = value;
    locked[r][c] = true;
  }

  void _drawFunctionPatterns(
    List<List<int>> grid,
    List<List<bool>> locked,
    int version,
  ) {
    final int size = grid.length;
    _finder(grid, locked, 0, 0);
    _finder(grid, locked, size - 7, 0);
    _finder(grid, locked, 0, size - 7);
    for (int i = 8; i < size - 8; i++) {
      final int bit = i.isEven ? 1 : 0;
      if (!locked[6][i]) {
        _set(grid, locked, 6, i, bit);
      }
      if (!locked[i][6]) {
        _set(grid, locked, i, 6, bit);
      }
    }
    for (int i = 0; i < 9; i++) {
      if (!locked[8][i]) {
        _set(grid, locked, 8, i, 0);
      }
      if (!locked[i][8]) {
        _set(grid, locked, i, 8, 0);
      }
      if (!locked[8][size - 1 - i]) {
        _set(grid, locked, 8, size - 1 - i, 0);
      }
      if (i < 8 && !locked[size - 1 - i][8]) {
        _set(grid, locked, size - 1 - i, 8, 0);
      }
    }
    if (version >= 7) {
      for (int i = 0; i < 6; i++) {
        for (int j = 0; j < 3; j++) {
          _set(grid, locked, i, size - 11 + j, 0);
          _set(grid, locked, size - 11 + j, i, 0);
        }
      }
    }
    for (final (int r, int c) in _alignments(version)) {
      if (locked[r][c]) {
        continue;
      }
      _alignment(grid, locked, r, c);
    }
    _set(grid, locked, size - 8, 8, 1);
  }

  void _finder(
    List<List<int>> grid,
    List<List<bool>> locked,
    int row,
    int col,
  ) {
    for (int r = -1; r <= 7; r++) {
      for (int c = -1; c <= 7; c++) {
        final int rr = row + r;
        final int cc = col + c;
        if (rr < 0 || cc < 0 || rr >= grid.length || cc >= grid.length) {
          continue;
        }
        final bool dark = r == -1 ||
            r == 7 ||
            c == -1 ||
            c == 7 ||
            (r >= 0 && r <= 6 && (c == 0 || c == 6)) ||
            (c >= 0 && c <= 6 && (r == 0 || r == 6)) ||
            (r >= 2 && r <= 4 && c >= 2 && c <= 4);
        _set(grid, locked, rr, cc, dark ? 1 : 0);
      }
    }
  }

  void _alignment(
    List<List<int>> grid,
    List<List<bool>> locked,
    int row,
    int col,
  ) {
    for (int r = -2; r <= 2; r++) {
      for (int c = -2; c <= 2; c++) {
        final bool dark =
            r == -2 || r == 2 || c == -2 || c == 2 || (r == 0 && c == 0);
        _set(grid, locked, row + r, col + c, dark ? 1 : 0);
      }
    }
  }

  void _drawCodewords(
    List<List<int>> grid,
    List<List<bool>> locked,
    List<int> codewords,
  ) {
    final int size = grid.length;
    var bitIndex = 0;
    final int totalBits = codewords.length * 8;
    var upward = true;
    for (int col = size - 1; col > 0; col -= 2) {
      if (col == 6) {
        col--;
      }
      for (int i = 0; i < size; i++) {
        final int row = upward ? size - 1 - i : i;
        for (int c = 0; c < 2; c++) {
          final int cc = col - c;
          if (locked[row][cc]) {
            continue;
          }
          var dark = false;
          if (bitIndex < totalBits) {
            final int byte = codewords[bitIndex >> 3];
            dark = ((byte >> (7 - (bitIndex & 7))) & 1) == 1;
            bitIndex++;
          }
          grid[row][cc] = dark ? 1 : 0;
        }
      }
      upward = !upward;
    }
  }

  int _bestMask(
    List<List<int>> grid,
    List<List<bool>> locked,
    int version,
  ) {
    var best = 0;
    var bestScore = 1 << 30;
    for (int mask = 0; mask < 8; mask++) {
      final List<List<int>> copy = <List<int>>[
        for (final List<int> row in grid) List<int>.from(row),
      ];
      _applyMask(copy, locked, mask);
      _drawFormat(copy, locked, mask);
      if (version >= 7) {
        _drawVersion(copy, locked, version);
      }
      final int score = _penalty(copy);
      if (score < bestScore) {
        bestScore = score;
        best = mask;
      }
    }
    return best;
  }

  void _applyMask(
    List<List<int>> grid,
    List<List<bool>> locked,
    int mask,
  ) {
    final int size = grid.length;
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (locked[r][c]) {
          continue;
        }
        if (_maskBit(mask, r, c)) {
          grid[r][c] ^= 1;
        }
      }
    }
  }

  static bool _maskBit(int mask, int r, int c) {
    switch (mask) {
      case 0:
        return (r + c).isEven;
      case 1:
        return r.isEven;
      case 2:
        return c % 3 == 0;
      case 3:
        return (r + c) % 3 == 0;
      case 4:
        return ((r ~/ 2) + (c ~/ 3)).isEven;
      case 5:
        return (r * c) % 2 + (r * c) % 3 == 0;
      case 6:
        return ((r * c) % 2 + (r * c) % 3).isEven;
      case 7:
        return ((r + c) % 2 + (r * c) % 3).isEven;
      default:
        return false;
    }
  }

  void _drawFormat(
    List<List<int>> grid,
    List<List<bool>> locked,
    int mask,
  ) {
    final int data = (0x00 << 3) | mask; // ECC-M
    int bits = data << 10;
    const int poly = 0x537;
    for (int i = 4; i >= 0; i--) {
      if (((bits >> (i + 10)) & 1) != 0) {
        bits ^= poly << i;
      }
    }
    final int format = (data << 10 | bits) ^ 0x5412;
    final int size = grid.length;
    void put(int r, int c, int i) {
      grid[r][c] = (format >> i) & 1;
      locked[r][c] = true;
    }

    for (int i = 0; i < 6; i++) {
      put(i, 8, i);
    }
    put(7, 8, 6);
    put(8, 8, 7);
    put(8, 7, 8);
    for (int i = 9; i < 15; i++) {
      put(8, 14 - i, i);
    }
    for (int i = 0; i < 8; i++) {
      put(8, size - 1 - i, i);
    }
    for (int i = 0; i < 7; i++) {
      put(size - 7 + i, 8, i + 8);
    }
  }

  void _drawVersion(
    List<List<int>> grid,
    List<List<bool>> locked,
    int version,
  ) {
    int bits = version << 12;
    const int poly = 0x1F25;
    for (int i = 5; i >= 0; i--) {
      if (((bits >> (i + 12)) & 1) != 0) {
        bits ^= poly << i;
      }
    }
    final int vbits = version << 12 | bits;
    final int size = grid.length;
    for (int i = 0; i < 18; i++) {
      final int bit = (vbits >> i) & 1;
      final int a = i ~/ 3;
      final int b = i % 3;
      grid[a][size - 11 + b] = bit;
      locked[a][size - 11 + b] = true;
      grid[size - 11 + b][a] = bit;
      locked[size - 11 + b][a] = true;
    }
  }

  int _penalty(List<List<int>> grid) {
    final int size = grid.length;
    var score = 0;
    for (int r = 0; r < size; r++) {
      var run = 1;
      for (int c = 1; c < size; c++) {
        if (grid[r][c] == grid[r][c - 1]) {
          run++;
        } else {
          if (run >= 5) {
            score += 3 + (run - 5);
          }
          run = 1;
        }
      }
      if (run >= 5) {
        score += 3 + (run - 5);
      }
    }
    for (int c = 0; c < size; c++) {
      var run = 1;
      for (int r = 1; r < size; r++) {
        if (grid[r][c] == grid[r - 1][c]) {
          run++;
        } else {
          if (run >= 5) {
            score += 3 + (run - 5);
          }
          run = 1;
        }
      }
      if (run >= 5) {
        score += 3 + (run - 5);
      }
    }
    for (int r = 0; r < size - 1; r++) {
      for (int c = 0; c < size - 1; c++) {
        final int v = grid[r][c];
        if (v == grid[r][c + 1] &&
            v == grid[r + 1][c] &&
            v == grid[r + 1][c + 1]) {
          score += 3;
        }
      }
    }
    var dark = 0;
    for (final List<int> row in grid) {
      for (final int cell in row) {
        if (cell == 1) {
          dark++;
        }
      }
    }
    final int percent = ((dark * 100) / (size * size)).round();
    score += ((percent - 50).abs() ~/ 5) * 10;
    return score;
  }

  static List<(int, int)> _alignments(int version) {
    if (version == 1) {
      return const <(int, int)>[];
    }
    final List<int> pos = _alignPos[version]!;
    final List<(int, int)> out = <(int, int)>[];
    for (final int r in pos) {
      for (final int c in pos) {
        if ((r == 6 && c == 6) ||
            (r == 6 && c == pos.last) ||
            (r == pos.last && c == 6)) {
          continue;
        }
        out.add((r, c));
      }
    }
    return out;
  }

  _RsParams _rsParams(int version) {
    const List<(int data, int ecc, int blocks)> table =
        <(int, int, int)>[
      (0, 0, 0),
      (16, 10, 1),
      (28, 16, 1),
      (44, 26, 1),
      (64, 18, 2),
      (86, 24, 2),
      (108, 16, 4),
      (124, 18, 4),
      (154, 22, 4),
      (182, 22, 5),
      (216, 26, 5),
    ];
    final (int data, int ecc, int blocks) = table[version];
    final int shortBlockData = data ~/ blocks;
    final int shortBlocks = blocks - (data % blocks);
    return _RsParams(
      dataCodewords: data,
      eccPerBlock: ecc,
      blocks: blocks,
      shortBlockData: shortBlockData,
      shortBlocks: shortBlocks,
    );
  }

  static final List<int> _exp = _buildExp();
  static final List<int> _log = _buildLog();

  static List<int> _buildExp() {
    final List<int> exp = List<int>.filled(512, 0);
    var x = 1;
    for (int i = 0; i < 255; i++) {
      exp[i] = x;
      x <<= 1;
      if (x >= 0x100) {
        x ^= 0x11d;
      }
    }
    for (int i = 255; i < 512; i++) {
      exp[i] = exp[i - 255];
    }
    return exp;
  }

  static List<int> _buildLog() {
    final List<int> log = List<int>.filled(256, 0);
    for (int i = 0; i < 255; i++) {
      log[_exp[i]] = i;
    }
    return log;
  }

  static const Map<int, List<int>> _alignPos = <int, List<int>>{
    2: <int>[6, 18],
    3: <int>[6, 22],
    4: <int>[6, 26],
    5: <int>[6, 30],
    6: <int>[6, 34],
    7: <int>[6, 22, 38],
    8: <int>[6, 24, 42],
    9: <int>[6, 26, 46],
    10: <int>[6, 28, 50],
  };
}

class _RsParams {
  const _RsParams({
    required this.dataCodewords,
    required this.eccPerBlock,
    required this.blocks,
    required this.shortBlockData,
    required this.shortBlocks,
  });

  final int dataCodewords;
  final int eccPerBlock;
  final int blocks;
  final int shortBlockData;
  final int shortBlocks;
}

class _BitBuffer {
  final List<int> _bytes = <int>[];
  var _length = 0;

  int get length => _length;

  void put(int value, int bits) {
    for (int i = bits - 1; i >= 0; i--) {
      if (_length == _bytes.length * 8) {
        _bytes.add(0);
      }
      if (((value >> i) & 1) != 0) {
        _bytes[_length >> 3] |= 0x80 >> (_length & 7);
      }
      _length++;
    }
  }

  List<int> toBytes() => List<int>.from(_bytes);
}

/// QR Code widget (byte mode, ECC-M by default).
class QrCode extends Widget {
  /// QrCode API.
  const QrCode(
    this.data, {
    this.size = 96,
    this.color = '000000',
    this.backgroundColor = 'FFFFFF',
    this.ecc = QrEcc.m,
    this.padding = 2,
  });

  /// data API.
  final String data;

  /// size API (points, square).
  final double size;

  /// color API.
  final String color;

  /// backgroundColor API.
  final String backgroundColor;

  /// ecc API.
  final QrEcc ecc;

  /// Quiet-zone modules around the matrix.
  final int padding;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final List<List<bool>> matrix = QrEncoder(ecc: ecc).encode(data);
    final int n = matrix.length + padding * 2;
    final PwSize box = constraints.constrain(PwSize(size, size));
    return CustomPaint(
      size: box,
      painter: (PdfCanvas canvas, PwSize painted) {
        canvas.endText();
        canvas.fillRect(0, 0, painted.width, painted.height, backgroundColor);
        final double module = painted.width / n;
        canvas.setFillColor(color);
        for (int r = 0; r < matrix.length; r++) {
          for (int c = 0; c < matrix[r].length; c++) {
            if (!matrix[r][c]) {
              continue;
            }
            canvas.rect(
              (c + padding) * module,
              (r + padding) * module,
              module + 0.05,
              module + 0.05,
            );
            canvas.fill();
          }
        }
      },
    ).layout(context, constraints);
  }
}
