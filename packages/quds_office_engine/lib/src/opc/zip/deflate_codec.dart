import 'dart:typed_data';

/// Raw DEFLATE (RFC 1951) inflate / deflate used by ZIP method 8.
///
/// No `dart:io` dependency — safe on CLI, server, web, and native.
abstract final class RawDeflate {
  /// inflate API.
  static Uint8List inflate(List<int> data) => _Inflater(data).run();

  /// deflate API.
  static Uint8List deflate(List<int> data, {int level = 6}) {
    return _Deflater(Uint8List.fromList(data), level: level).run();
  }
}

class _Inflater {
  _Inflater(List<int> data)
    : _src = data is Uint8List ? data : Uint8List.fromList(data);

  final Uint8List _src;
  int _pos = 0;
  int _bitBuf = 0;
  int _bitCount = 0;
  final List<int> _out = <int>[];

  /// run API.
  Uint8List run() {
    var finalBlock = false;
    while (!finalBlock) {
      finalBlock = _bits(1) == 1;
      final int type = _bits(2);
      switch (type) {
        case 0:
          _stored();
        case 1:
          _huffman(_fixedLit(), _fixedDist());
        case 2:
          final _Tables tables = _dynamicTables();
          _huffman(tables.lit, tables.dist);
        default:
          throw const ZipDeflateException('Invalid DEFLATE block type');
      }
    }
    return Uint8List.fromList(_out);
  }

  void _stored() {
    _bitBuf = 0;
    _bitCount = 0;
    if (_pos + 4 > _src.length) {
      throw const ZipDeflateException('Truncated stored block');
    }
    final int len = _src[_pos] | (_src[_pos + 1] << 8);
    final int nlen = _src[_pos + 2] | (_src[_pos + 3] << 8);
    _pos += 4;
    if ((len ^ 0xFFFF) != nlen) {
      throw const ZipDeflateException('Stored block length mismatch');
    }
    if (_pos + len > _src.length) {
      throw const ZipDeflateException('Stored block overruns input');
    }
    _out.addAll(Uint8List.sublistView(_src, _pos, _pos + len));
    _pos += len;
  }

  void _huffman(_Huffman lit, _Huffman dist) {
    while (true) {
      final int sym = lit.decode(this);
      if (sym < 256) {
        _out.add(sym);
        continue;
      }
      if (sym == 256) {
        return;
      }
      if (sym > 285) {
        throw ZipDeflateException('Invalid length symbol $sym');
      }
      final int length =
          _lengthBase[sym - 257] + _bits(_lengthExtra[sym - 257]);
      final int dsym = dist.decode(this);
      if (dsym > 29) {
        throw ZipDeflateException('Invalid distance symbol $dsym');
      }
      final int distance = _distBase[dsym] + _bits(_distExtra[dsym]);
      if (distance <= 0 || distance > _out.length) {
        throw const ZipDeflateException('Invalid backreference distance');
      }
      final int start = _out.length - distance;
      for (int i = 0; i < length; i++) {
        _out.add(_out[start + i]);
      }
    }
  }

  _Tables _dynamicTables() {
    final int hlit = _bits(5) + 257;
    final int hdist = _bits(5) + 1;
    final int hclen = _bits(4) + 4;
    final List<int> clens = List<int>.filled(19, 0);
    for (int i = 0; i < hclen; i++) {
      clens[_codeLengthOrder[i]] = _bits(3);
    }
    final _Huffman clen = _Huffman.fromLengths(clens);
    final List<int> lengths = List<int>.filled(hlit + hdist, 0);
    int index = 0;
    int prev = 0;
    while (index < lengths.length) {
      final int sym = clen.decode(this);
      if (sym < 16) {
        lengths[index++] = sym;
        prev = sym;
      } else if (sym == 16) {
        final int repeat = 3 + _bits(2);
        for (int i = 0; i < repeat; i++) {
          lengths[index++] = prev;
        }
      } else if (sym == 17) {
        final int repeat = 3 + _bits(3);
        index += repeat;
        prev = 0;
      } else if (sym == 18) {
        final int repeat = 11 + _bits(7);
        index += repeat;
        prev = 0;
      } else {
        throw const ZipDeflateException('Invalid code-length symbol');
      }
    }
    return _Tables(
      lit: _Huffman.fromLengths(lengths.sublist(0, hlit)),
      dist: _Huffman.fromLengths(lengths.sublist(hlit)),
    );
  }

  int _bits(int count) {
    if (count == 0) {
      return 0;
    }
    while (_bitCount < count) {
      if (_pos >= _src.length) {
        throw const ZipDeflateException('Unexpected end of DEFLATE stream');
      }
      _bitBuf |= _src[_pos++] << _bitCount;
      _bitCount += 8;
    }
    final int value = _bitBuf & ((1 << count) - 1);
    _bitBuf >>= count;
    _bitCount -= count;
    return value;
  }

  static _Huffman _fixedLit() {
    final List<int> lengths = List<int>.filled(288, 8);
    for (int i = 144; i <= 255; i++) {
      lengths[i] = 9;
    }
    for (int i = 256; i <= 279; i++) {
      lengths[i] = 7;
    }
    for (int i = 280; i <= 287; i++) {
      lengths[i] = 8;
    }
    return _Huffman.fromLengths(lengths);
  }

  /// fromLengths API.
  static _Huffman _fixedDist() => _Huffman.fromLengths(List<int>.filled(32, 5));
}

class _Deflater {
  _Deflater(this._src, {required this._level});

  final Uint8List _src;
  final int _level;
  int _bitBuf = 0;
  int _bitCount = 0;

  /// BytesBuilder API.
  final BytesBuilder _out = BytesBuilder(copy: false);

  /// run API.
  Uint8List run() {
    if (_src.isEmpty || _level <= 0) {
      _stored();
      return _out.takeBytes();
    }
    _writeBits(1, 1); // BFINAL
    _writeBits(1, 2); // fixed Huffman
    final int window = _level >= 7 ? 32768 : 4096;
    final Map<int, List<int>> index = <int, List<int>>{};
    int cursor = 0;
    while (cursor < _src.length) {
      final _Match match = _findMatch(cursor, window, index);
      _indexTriple(index, cursor);
      if (match.length >= 3) {
        _emitLengthDistance(match.length, match.distance);
        for (int i = 1; i < match.length; i++) {
          _indexTriple(index, cursor + i);
        }
        cursor += match.length;
      } else {
        _emitLiteral(_src[cursor]);
        cursor++;
      }
    }
    _emitLiteral(256); // EOB
    _flushBits();
    return _out.takeBytes();
  }

  void _stored() {
    int offset = 0;
    while (offset < _src.length || offset == 0 && _src.isEmpty) {
      final int remaining = _src.length - offset;
      final int take = remaining > 65535 ? 65535 : remaining;
      final bool last = offset + take >= _src.length;
      _writeBits(last ? 1 : 0, 1);
      _writeBits(0, 2);
      _flushBits();
      _out.addByte(take & 0xFF);
      _out.addByte((take >> 8) & 0xFF);
      final int nlen = take ^ 0xFFFF;
      _out.addByte(nlen & 0xFF);
      _out.addByte((nlen >> 8) & 0xFF);
      if (take > 0) {
        _out.add(Uint8List.sublistView(_src, offset, offset + take));
      }
      offset += take;
      if (_src.isEmpty) {
        break;
      }
    }
  }

  void _emitLiteral(int symbol) {
    final _Code code = _fixedLiteralCode(symbol);
    _writeBits(code.bits, code.length);
  }

  void _emitLengthDistance(int length, int distance) {
    final int lenSym = _lengthSymbol(length);
    final _Code lit = _fixedLiteralCode(lenSym);
    _writeBits(lit.bits, lit.length);
    final int lenExtraBits = _lengthExtra[lenSym - 257];
    if (lenExtraBits > 0) {
      _writeBits(length - _lengthBase[lenSym - 257], lenExtraBits);
    }
    final int distSym = _distanceSymbol(distance);
    _writeBits(_reverseBits(distSym, 5), 5);
    final int distExtra = _distExtra[distSym];
    if (distExtra > 0) {
      _writeBits(distance - _distBase[distSym], distExtra);
    }
  }

  _Match _findMatch(int cursor, int window, Map<int, List<int>> index) {
    if (cursor + 2 >= _src.length) {
      return const _Match(0, 0);
    }
    final int key = _triple(_src, cursor);
    final List<int>? candidates = index[key];
    if (candidates == null) {
      return const _Match(0, 0);
    }
    int bestLen = 0;
    int bestDist = 0;
    final int minPos = cursor > window ? cursor - window : 0;
    final int maxChain = _level >= 7 ? 1024 : 128;
    final int stop = candidates.length > maxChain
        ? candidates.length - maxChain
        : 0;
    for (int i = candidates.length - 1; i >= stop; i--) {
      final int pos = candidates[i];
      if (pos < minPos) {
        break;
      }
      int len = 0;
      while (cursor + len < _src.length &&
          _src[pos + len] == _src[cursor + len] &&
          len < 258) {
        len++;
      }
      if (len > bestLen) {
        bestLen = len;
        bestDist = cursor - pos;
        if (bestLen == 258) {
          break;
        }
      }
    }
    return _Match(bestLen, bestDist);
  }

  void _indexTriple(Map<int, List<int>> index, int cursor) {
    if (cursor + 2 >= _src.length) {
      return;
    }
    index.putIfAbsent(_triple(_src, cursor), () => <int>[]).add(cursor);
  }

  void _writeBits(int value, int count) {
    _bitBuf |= (value & ((1 << count) - 1)) << _bitCount;
    _bitCount += count;
    while (_bitCount >= 8) {
      _out.addByte(_bitBuf & 0xFF);
      _bitBuf >>= 8;
      _bitCount -= 8;
    }
  }

  void _flushBits() {
    if (_bitCount > 0) {
      _out.addByte(_bitBuf & 0xFF);
      _bitBuf = 0;
      _bitCount = 0;
    }
  }
}

class _Huffman {
  _Huffman._(this._symbols, this._bits);

  final Int32List _symbols;
  final Int8List _bits;
  static const int _fastBits = 9;
  static const int _fastMask = (1 << _fastBits) - 1;

  /// fromLengths API.
  factory _Huffman.fromLengths(List<int> lengths) {
    var maxBits = 0;
    for (final int len in lengths) {
      if (len > maxBits) {
        maxBits = len;
      }
    }
    if (maxBits == 0) {
      return _Huffman._(Int32List(1 << _fastBits), Int8List(1 << _fastBits));
    }
    final List<int> blCount = List<int>.filled(maxBits + 1, 0);
    for (final int len in lengths) {
      if (len != 0) {
        blCount[len]++;
      }
    }
    final List<int> nextCode = List<int>.filled(maxBits + 1, 0);
    var code = 0;
    for (int bits = 1; bits <= maxBits; bits++) {
      code = (code + blCount[bits - 1]) << 1;
      nextCode[bits] = code;
    }
    final int tableSize = 1 << (maxBits > _fastBits ? maxBits : _fastBits);
    final Int32List symbols = Int32List(tableSize);
    final Int8List bits = Int8List(tableSize);
    for (int sym = 0; sym < lengths.length; sym++) {
      final int len = lengths[sym];
      if (len == 0) {
        continue;
      }
      final int c = nextCode[len];
      nextCode[len]++;
      final int reversed = _reverseBits(c, len);
      if (len <= _fastBits) {
        final int stride = 1 << len;
        for (int i = reversed; i < (1 << _fastBits); i += stride) {
          symbols[i] = sym;
          bits[i] = len;
        }
      } else {
        symbols[reversed] = sym;
        bits[reversed] = len;
      }
    }
    return _Huffman._(symbols, bits);
  }

  /// decode API.
  int decode(_Inflater inflater) {
    final int peek = inflater._bitBuf | _peekAhead(inflater);
    final int fast = _bits[peek & _fastMask];
    if (fast > 0 && fast <= _fastBits) {
      inflater._bits(fast);
      return _symbols[peek & _fastMask];
    }
    var code = 0;
    var len = 0;
    while (true) {
      // Bits are accumulated in stream order (LSB first), matching how
      // [fromLengths] indexes the table with reversed canonical codes.
      code |= inflater._bits(1) << len;
      len++;
      if (code < _bits.length && _bits[code] == len) {
        return _symbols[code];
      }
      if (len > 15) {
        throw const ZipDeflateException('Invalid Huffman code');
      }
    }
  }

  int _peekAhead(_Inflater inflater) {
    var buf = inflater._bitBuf;
    var count = inflater._bitCount;
    var pos = inflater._pos;
    while (count < 15 && pos < inflater._src.length) {
      buf |= inflater._src[pos++] << count;
      count += 8;
    }
    return buf;
  }
}

class _Tables {
  const _Tables({required this.lit, required this.dist});

  /// lit API.
  final _Huffman lit;

  /// dist API.
  final _Huffman dist;
}

class _Code {
  const _Code(this.bits, this.length);

  /// bits API.
  final int bits;

  /// length API.
  final int length;
}

class _Match {
  const _Match(this.length, this.distance);

  /// length API.
  final int length;

  /// distance API.
  final int distance;
}

_Code _fixedLiteralCode(int symbol) {
  if (symbol <= 143) {
    return _Code(_reverseBits(0x30 + symbol, 8), 8);
  }
  if (symbol <= 255) {
    return _Code(_reverseBits(0x190 + (symbol - 144), 9), 9);
  }
  if (symbol <= 279) {
    return _Code(_reverseBits(symbol - 256, 7), 7);
  }
  return _Code(_reverseBits(0xC0 + (symbol - 280), 8), 8);
}

int _lengthSymbol(int length) {
  for (int i = _lengthBase.length - 1; i >= 0; i--) {
    if (length >= _lengthBase[i]) {
      return 257 + i;
    }
  }
  return 257;
}

int _distanceSymbol(int distance) {
  for (int i = _distBase.length - 1; i >= 0; i--) {
    if (distance >= _distBase[i]) {
      return i;
    }
  }
  return 0;
}

int _triple(Uint8List data, int offset) =>
    data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16);

int _reverseBits(int value, int bits) {
  /// v API.
  var v = value;

  /// r API.
  var r = 0;
  for (int i = 0; i < bits; i++) {
    r = (r << 1) | (v & 1);
    v >>= 1;
  }
  return r;
}

/// Thrown when a DEFLATE stream is corrupt.
class ZipDeflateException implements Exception {
  /// ZipDeflateException API.
  const ZipDeflateException(this.message);

  /// message API.
  final String message;

  @override
  /// toString API.
  String toString() => 'ZipDeflateException: $message';
}

const List<int> _codeLengthOrder = <int>[
  16,
  17,
  18,
  0,
  8,
  7,
  9,
  6,
  10,
  5,
  11,
  4,
  12,
  3,
  13,
  2,
  14,
  1,
  15,
];

const List<int> _lengthBase = <int>[
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  13,
  15,
  17,
  19,
  23,
  27,
  31,
  35,
  43,
  51,
  59,
  67,
  83,
  99,
  115,
  131,
  163,
  195,
  227,
  258,
];

const List<int> _lengthExtra = <int>[
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  1,
  1,
  1,
  1,
  2,
  2,
  2,
  2,
  3,
  3,
  3,
  3,
  4,
  4,
  4,
  4,
  5,
  5,
  5,
  5,
  0,
];

const List<int> _distBase = <int>[
  1,
  2,
  3,
  4,
  5,
  7,
  9,
  13,
  17,
  25,
  33,
  49,
  65,
  97,
  129,
  193,
  257,
  385,
  513,
  769,
  1025,
  1537,
  2049,
  3073,
  4097,
  6145,
  8193,
  12289,
  16385,
  24577,
];

const List<int> _distExtra = <int>[
  0,
  0,
  0,
  0,
  1,
  1,
  2,
  2,
  3,
  3,
  4,
  4,
  5,
  5,
  6,
  6,
  7,
  7,
  8,
  8,
  9,
  9,
  10,
  10,
  11,
  11,
  12,
  12,
  13,
  13,
];
