import 'dart:typed_data';

/// Raw DEFLATE (RFC 1951) inflate / deflate used by ZIP method 8.
///
/// No `dart:io` dependency — safe on CLI, server, web, and native.
abstract final class RawDeflate {
  /// Output bound used when a caller does not supply a tighter one.
  ///
  /// The limit is checked before growing the output, including backreferences
  /// and stored blocks. It does not depend on an untrusted ZIP size header.
  static const int defaultMaxOutputBytes = 256 * 1024 * 1024;

  /// Inflates a raw stream, limiting the bytes produced.
  ///
  /// A caller can pass a tighter bound from its format or allocation budget.
  /// Omitting it still applies [defaultMaxOutputBytes], so a future caller
  /// cannot reintroduce an unbounded expansion path by accident.
  static Uint8List inflate(List<int> data, {int? maxOutputBytes}) {
    final int limit = maxOutputBytes ?? defaultMaxOutputBytes;
    if (limit < 0) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
    return _Inflater(data, maxOutputBytes: limit).run();
  }

  /// Inflates one stream and reports its byte boundary, including bit padding.
  static ({Uint8List bytes, int consumed}) inflatePrefix(
    Uint8List data, {
    required int maxOutputBytes,
    int windowBytes = 32768,
  }) {
    if (maxOutputBytes < 0) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
    RangeError.checkValueInInterval(windowBytes, 256, 32768, 'windowBytes');
    final inflater = _Inflater(
      data,
      maxOutputBytes: maxOutputBytes,
      windowBytes: windowBytes,
    );
    final bytes = inflater.run();
    return (bytes: bytes, consumed: inflater._pos);
  }

  /// deflate API.
  static Uint8List deflate(List<int> data, {int level = 6}) {
    final input = data is Uint8List ? data : Uint8List.fromList(data);
    return _Deflater(input, level: level).run();
  }
}

class _Inflater {
  _Inflater(List<int> data, {required this.maxOutputBytes, this.windowBytes = 32768})
    : _src = data is Uint8List ? data : Uint8List.fromList(data);

  final Uint8List _src;
  final int maxOutputBytes;
  final int windowBytes;
  int _pos = 0;
  int _bitBuf = 0;
  int _bitCount = 0;
  Uint8List _out = Uint8List(0);
  int _length = 0;

  static final _fixedLiteralTable = _fixedLit();
  static final _fixedDistanceTable = _fixedDist();

  void _reserveOutput(int additionalBytes) {
    final required = _length + additionalBytes;
    final limit = maxOutputBytes;
    if (required > limit) {
      throw const ZipDeflateLimitException('DEFLATE output exceeds its limit');
    }
    if (required <= _out.length) {
      return;
    }
    var capacity = _out.isEmpty ? 256 : _out.length * 2;
    if (capacity < required) {
      capacity = required;
    }
    if (capacity > limit) {
      capacity = limit;
    }
    _out = Uint8List(capacity)..setRange(0, _length, _out);
  }

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
          _huffman(_fixedLiteralTable, _fixedDistanceTable);
        case 2:
          final _Tables tables = _dynamicTables();
          _huffman(tables.lit, tables.dist);
        default:
          throw const ZipDeflateException('Invalid DEFLATE block type');
      }
    }
    return _length == _out.length ? _out : _out.sublist(0, _length);
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
    _reserveOutput(len);
    _out.setRange(_length, _length + len, _src, _pos);
    _length += len;
    _pos += len;
  }

  void _huffman(_Huffman lit, _Huffman dist) {
    while (true) {
      final int sym = lit.decode(this);
      if (sym < 256) {
        _reserveOutput(1);
        _out[_length++] = sym;
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
      if (distance <= 0 || distance > _length || distance > windowBytes) {
        throw const ZipDeflateException('Invalid backreference distance');
      }
      _reserveOutput(length);
      final out = _out;
      final end = _length + length;
      if (length >= 32 && distance >= length) {
        out.setRange(_length, end, out, _length - distance);
      } else {
        // Overlapping references read from the bytes just written.
        for (var offset = _length; offset < end; offset++) {
          out[offset] = out[offset - distance];
        }
      }
      _length = end;
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
        if (index == 0 || repeat > lengths.length - index) {
          throw const ZipDeflateException('Invalid DEFLATE code-length repeat');
        }
        lengths.fillRange(index, index + repeat, prev);
        index += repeat;
      } else if (sym == 17) {
        final int repeat = 3 + _bits(3);
        if (repeat > lengths.length - index) {
          throw const ZipDeflateException('Code-length repeat overruns table');
        }
        index += repeat;
        prev = 0;
      } else if (sym == 18) {
        final int repeat = 11 + _bits(7);
        if (repeat > lengths.length - index) {
          throw const ZipDeflateException('Code-length repeat overruns table');
        }
        index += repeat;
        prev = 0;
      } else {
        throw const ZipDeflateException('Invalid code-length symbol');
      }
    }
    if (index != lengths.length) {
      throw const ZipDeflateException('Invalid DEFLATE code-length repeat');
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
  late final ByteData _words = ByteData.sublistView(_src);
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
    final index = _MatchIndex(_src.length, window);
    final int maxChain = _level >= 7 ? 1024 : 128;
    final int tripleEnd = _src.length - 2;
    int cursor = 0;
    while (cursor < tripleEnd) {
      final key = _triple(_src, cursor);
      final match = _findMatch(cursor, window, maxChain, index, key);
      index.add(cursor, key);
      if (match.length >= 3) {
        _emitLengthDistance(match.length, match.distance);
        final end = cursor + match.length;
        for (var pos = cursor + 1; pos < end && pos < tripleEnd; pos++) {
          index.add(pos, _triple(_src, pos));
        }
        cursor = end;
      } else {
        _emitLiteral(_src[cursor++]);
      }
    }
    while (cursor < _src.length) {
      _emitLiteral(_src[cursor++]);
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

  static final _literalCodes = Uint16List.fromList([
    for (var symbol = 0; symbol < 288; symbol++) _packedLiteral(symbol),
  ]);
  static final _lengthCodes = _buildLengthCodes();
  static final _distanceCodes = _buildDistanceCodes();

  void _emitLiteral(int symbol) => _emitCode(_literalCodes[symbol]);

  void _emitLengthDistance(int length, int distance) {
    _emitCode(_lengthCodes[length]);
    _emitCode(_distanceCodes[distance]);
  }

  void _emitCode(int code) => _writeBits(code >>> 5, code & 31);

  static int _packedLiteral(int symbol) {
    final code = _fixedLiteralCode(symbol);
    return _packCode(code.bits, code.length);
  }

  // Keep the wire-order bits above a five-bit count. A packed length or
  // distance includes its extra bits, so emitting it needs one buffer write.
  static int _packCode(int bits, int count) => (bits << 5) | count;

  static Uint32List _buildLengthCodes() {
    final codes = Uint32List(259);
    for (var i = 0; i < _lengthBase.length; i++) {
      final base = _lengthBase[i];
      final end = i + 1 < _lengthBase.length
          ? _lengthBase[i + 1]
          : codes.length;
      final prefix = _fixedLiteralCode(257 + i);
      for (var length = base; length < end; length++) {
        codes[length] = _packCode(
          prefix.bits | ((length - base) << prefix.length),
          prefix.length + _lengthExtra[i],
        );
      }
    }
    return codes;
  }

  static Uint32List _buildDistanceCodes() {
    final codes = Uint32List(32769);
    for (var i = 0; i < _distBase.length; i++) {
      final base = _distBase[i];
      final end = i + 1 < _distBase.length ? _distBase[i + 1] : codes.length;
      final prefix = _reverseBits(i, 5);
      for (var distance = base; distance < end; distance++) {
        codes[distance] = _packCode(
          prefix | ((distance - base) << 5),
          5 + _distExtra[i],
        );
      }
    }
    return codes;
  }

  _Match _findMatch(
    int cursor,
    int window,
    int maxChain,
    _MatchIndex index,
    int key,
  ) {
    final int minPos = cursor > window ? cursor - window : 0;
    final int remaining = _src.length - cursor;
    final int limit = remaining < 258 ? remaining : 258;
    int bestLen = 0;
    int bestDist = 0;
    int pos = index.latest(key);
    final words = _words;
    for (var seen = 0; seen < maxChain && pos >= minPos; seen++) {
      // The triple already matches. After finding a candidate, a mismatch
      // at its end rules out any strictly longer match at this position.
      if (bestLen == 0 || _src[pos + bestLen] == _src[cursor + bestLen]) {
        var len = 3;
        // Probe intact four-byte ranges first, then locate an exact mismatch.
        // Reading the source permits overlapping matches at any alignment.
        while (len + 4 <= limit &&
            words.getUint32(pos + len, Endian.little) ==
                words.getUint32(cursor + len, Endian.little)) {
          len += 4;
        }
        while (len < limit && _src[pos + len] == _src[cursor + len]) {
          len++;
        }
        if (len > bestLen) {
          bestLen = len;
          bestDist = cursor - pos;
          if (bestLen == limit) break;
        }
      }
      pos = index.previous(pos);
    }
    return _Match(bestLen, bestDist);
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

/// Keeps the latest position for each triple and links previous matches with
/// distances in a ring. The oldest slot remains available for the search at
/// exactly one window of distance and is evicted on the following insertion.
class _MatchIndex {
  _MatchIndex(int inputLength, int window) {
    var capacity = 1;
    while (capacity < inputLength && capacity < window) {
      capacity <<= 1;
    }
    _keys = Uint32List(capacity);
    _links = Uint16List(capacity);
    _mask = capacity - 1;
  }

  final _heads = <int, int>{};
  late final Uint32List _keys;
  late final Uint16List _links;
  late final int _mask;

  int latest(int key) => _heads[key] ?? -1;

  int previous(int position) {
    final distance = _links[position & _mask];
    return distance == 0 ? -1 : position - distance;
  }

  void add(int position, int key) {
    final slot = position & _mask;
    final expired = position - _keys.length;
    if (expired >= 0) {
      final oldKey = _keys[slot];
      if (_heads[oldKey] == expired) _heads.remove(oldKey);
    }
    final head = _heads[key];
    _keys[slot] = key;
    _links[slot] = head == null ? 0 : position - head;
    _heads[key] = position;
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
    var buffer = inflater._bitBuf;
    var count = inflater._bitCount;
    var position = inflater._pos;
    final source = inflater._src;
    while (count < _fastBits && position < source.length) {
      buffer |= source[position++] << count;
      count += 8;
    }
    final index = buffer & _fastMask;
    final int fast = _bits[index];
    if (fast > 0 && fast <= _fastBits) {
      if (fast > count) {
        throw const ZipDeflateException('Unexpected end of DEFLATE stream');
      }
      // Lookahead can include a whole byte beyond this symbol. Leave it
      // unread so stored blocks and prefix inflation see the true boundary.
      final unused = count - fast;
      final remaining = unused & 7;
      inflater._pos = position - (unused >>> 3);
      inflater._bitCount = remaining;
      inflater._bitBuf = (buffer >>> fast) & ((1 << remaining) - 1);
      return _symbols[index];
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

/// Inflation would exceed the caller's maximum expanded byte count.
class ZipDeflateLimitException extends ZipDeflateException {
  const ZipDeflateLimitException(super.message);
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
