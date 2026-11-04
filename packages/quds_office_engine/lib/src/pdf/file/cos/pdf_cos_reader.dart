import 'dart:typed_data';

import 'pdf_cos.dart';
import 'pdf_open_error.dart';

/// Byte-offset COS tokenizer and object parser.
class PdfCosReader {
  /// PdfCosReader API.
  PdfCosReader(this.bytes);

  /// bytes API.
  final Uint8List bytes;

  /// offset API.
  int offset = 0;

  /// remaining API.
  bool get hasMore => offset < bytes.length;

  int get _len => bytes.length;

  int _byte([int? at]) {
    final int i = at ?? offset;
    if (i < 0 || i >= _len) {
      return -1;
    }
    return bytes[i];
  }

  /// skipWsAndComments API.
  void skipWsAndComments() {
    while (offset < _len) {
      final int b = bytes[offset];
      if (b == 0x00 ||
          b == 0x09 ||
          b == 0x0A ||
          b == 0x0C ||
          b == 0x0D ||
          b == 0x20) {
        offset++;
        continue;
      }
      if (b == 0x25) {
        offset++;
        while (offset < _len) {
          final int c = bytes[offset++];
          if (c == 0x0A || c == 0x0D) {
            break;
          }
        }
        continue;
      }
      return;
    }
  }

  /// parseValue API.
  PdfCos parseValue() {
    skipWsAndComments();
    if (offset >= _len) {
      throw const PdfOpenException(PdfOpenError.badXref, 'Unexpected EOF');
    }
    final int b = bytes[offset];
    if (b == 0x3C) {
      if (offset + 1 < _len && bytes[offset + 1] == 0x3C) {
        return _parseDict();
      }
      return _parseHexString();
    }
    if (b == 0x5B) {
      return _parseArray();
    }
    if (b == 0x28) {
      return _parseLiteralString();
    }
    if (b == 0x2F) {
      return _parseName();
    }
    if (b == 0x74 && _startsWith('true')) {
      offset += 4;
      return const PdfCosBool(true);
    }
    if (b == 0x66 && _startsWith('false')) {
      offset += 5;
      return const PdfCosBool(false);
    }
    if (b == 0x6E && _startsWith('null')) {
      offset += 4;
      return const PdfCosNull();
    }
    if (_isNumberStart(b)) {
      return _parseNumberOrRef();
    }
    throw PdfOpenException(
      PdfOpenError.badXref,
      'Unexpected byte 0x${b.toRadixString(16)} at $offset',
    );
  }

  /// Parses `id gen obj` … `endobj` at [offset].
  PdfCos parseIndirectObject() {
    skipWsAndComments();
    parseValue(); // object number (consumed via number/ref path)
    // Re-parse header explicitly.
    return _parseIndirectBody();
  }

  PdfCos _parseIndirectBody() {
    skipWsAndComments();
    if (!_startsWith('obj')) {
      // Caller already consumed id/gen via seek; expect `obj`.
    }
    if (_startsWith('obj')) {
      offset += 3;
    }
    skipWsAndComments();
    final PdfCos value = parseValue();
    skipWsAndComments();
    if (_startsWith('stream')) {
      offset += 6;
      if (offset < _len && bytes[offset] == 0x0D) {
        offset++;
      }
      if (offset < _len && bytes[offset] == 0x0A) {
        offset++;
      }
      final PdfCosDict dict = value is PdfCosDict ? value : PdfCosDict();
      final int length = pdfCosInt(dict['Length']) ?? _scanEndstream() - offset;
      final int start = offset;
      final int end = (start + length).clamp(0, _len);
      offset = end;
      skipWsAndComments();
      if (_startsWith('endstream')) {
        offset += 9;
      }
      skipWsAndComments();
      if (_startsWith('endobj')) {
        offset += 6;
      }
      return PdfCosStream(dict, Uint8List.sublistView(bytes, start, end));
    }
    if (_startsWith('endobj')) {
      offset += 6;
    }
    return value;
  }

  /// parseObjectAt API.
  PdfCos parseObjectAt(int position) {
    offset = position;
    skipWsAndComments();
    _skipObjectHeader();
    return _parseIndirectBody();
  }

  void _skipObjectHeader() {
    skipWsAndComments();
    _readIntToken();
    skipWsAndComments();
    _readIntToken();
    skipWsAndComments();
  }

  int _readIntToken() {
    skipWsAndComments();
    final int start = offset;
    if (offset < _len && (bytes[offset] == 0x2B || bytes[offset] == 0x2D)) {
      offset++;
    }
    while (offset < _len && bytes[offset] >= 0x30 && bytes[offset] <= 0x39) {
      offset++;
    }
    return int.tryParse(
          String.fromCharCodes(bytes.sublist(start, offset)),
        ) ??
        0;
  }

  int _scanEndstream() {
    final int start = offset;
    final Uint8List needle = Uint8List.fromList('endstream'.codeUnits);
    for (int i = start; i + needle.length <= _len; i++) {
      var ok = true;
      for (int j = 0; j < needle.length; j++) {
        if (bytes[i + j] != needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        return i;
      }
    }
    return _len;
  }

  bool _startsWith(String text) {
    if (offset + text.length > _len) {
      return false;
    }
    for (int i = 0; i < text.length; i++) {
      if (bytes[offset + i] != text.codeUnitAt(i)) {
        return false;
      }
    }
    return true;
  }

  static bool _isNumberStart(int b) =>
      (b >= 0x30 && b <= 0x39) || b == 0x2B || b == 0x2D || b == 0x2E;

  PdfCos _parseNumberOrRef() {
    final int saved = offset;
    final String raw = _readNumberLexeme();
    skipWsAndComments();
    if (offset < _len && _isNumberStart(bytes[offset])) {
      final int afterFirst = offset;
      final String genLex = _readNumberLexeme();
      skipWsAndComments();
      if (_startsWith('R') && _isNameDelimiter(_byte(offset + 1))) {
        offset += 1;
        final int id = int.tryParse(raw) ?? 0;
        final int gen = int.tryParse(genLex) ?? 0;
        return PdfCosRef(id, gen);
      }
      offset = afterFirst;
    }
    offset = saved + raw.length;
    if (raw.contains('.')) {
      return PdfCosReal(double.tryParse(raw) ?? 0);
    }
    return PdfCosInt(int.tryParse(raw) ?? 0);
  }

  String _readNumberLexeme() {
    final int start = offset;
    if (offset < _len && (bytes[offset] == 0x2B || bytes[offset] == 0x2D)) {
      offset++;
    }
    var sawDot = false;
    while (offset < _len) {
      final int b = bytes[offset];
      if (b >= 0x30 && b <= 0x39) {
        offset++;
        continue;
      }
      if (b == 0x2E && !sawDot) {
        sawDot = true;
        offset++;
        continue;
      }
      break;
    }
    return String.fromCharCodes(bytes.sublist(start, offset));
  }

  static bool _isNameDelimiter(int b) =>
      b < 0 ||
      b == 0x00 ||
      b == 0x09 ||
      b == 0x0A ||
      b == 0x0C ||
      b == 0x0D ||
      b == 0x20 ||
      b == 0x2F ||
      b == 0x28 ||
      b == 0x29 ||
      b == 0x3C ||
      b == 0x3E ||
      b == 0x5B ||
      b == 0x5D ||
      b == 0x7B ||
      b == 0x7D ||
      b == 0x25;

  PdfCosName _parseName() {
    offset++; // /
    final StringBuffer buf = StringBuffer();
    while (offset < _len && !_isNameDelimiter(bytes[offset])) {
      final int b = bytes[offset];
      if (b == 0x23 && offset + 2 < _len) {
        final int hi = _hexVal(bytes[offset + 1]);
        final int lo = _hexVal(bytes[offset + 2]);
        if (hi >= 0 && lo >= 0) {
          buf.writeCharCode((hi << 4) | lo);
          offset += 3;
          continue;
        }
      }
      buf.writeCharCode(b);
      offset++;
    }
    return PdfCosName(buf.toString());
  }

  static int _hexVal(int b) {
    if (b >= 0x30 && b <= 0x39) {
      return b - 0x30;
    }
    if (b >= 0x41 && b <= 0x46) {
      return b - 0x41 + 10;
    }
    if (b >= 0x61 && b <= 0x66) {
      return b - 0x61 + 10;
    }
    return -1;
  }

  PdfCosString _parseHexString() {
    offset++; // <
    final List<int> nibbles = <int>[];
    while (offset < _len && bytes[offset] != 0x3E) {
      final int v = _hexVal(bytes[offset]);
      if (v >= 0) {
        nibbles.add(v);
      }
      offset++;
    }
    if (offset < _len && bytes[offset] == 0x3E) {
      offset++;
    }
    if (nibbles.length.isOdd) {
      nibbles.add(0);
    }
    final Uint8List out = Uint8List(nibbles.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = (nibbles[i * 2] << 4) | nibbles[i * 2 + 1];
    }
    return PdfCosString(out, hex: true);
  }

  PdfCosString _parseLiteralString() {
    offset++; // (
    var depth = 1;
    final BytesBuilder out = BytesBuilder(copy: false);
    while (offset < _len && depth > 0) {
      final int b = bytes[offset++];
      if (b == 0x5C && offset < _len) {
        final int n = bytes[offset++];
        switch (n) {
          case 0x6E:
            out.addByte(0x0A);
          case 0x72:
            out.addByte(0x0D);
          case 0x74:
            out.addByte(0x09);
          case 0x62:
            out.addByte(0x08);
          case 0x66:
            out.addByte(0x0C);
          case 0x28:
            out.addByte(0x28);
          case 0x29:
            out.addByte(0x29);
          case 0x5C:
            out.addByte(0x5C);
          case 0x0A:
          case 0x0D:
            if (n == 0x0D && offset < _len && bytes[offset] == 0x0A) {
              offset++;
            }
          default:
            if (n >= 0x30 && n <= 0x37) {
              var v = n - 0x30;
              for (int k = 0; k < 2 && offset < _len; k++) {
                final int o = bytes[offset];
                if (o < 0x30 || o > 0x37) {
                  break;
                }
                v = (v << 3) | (o - 0x30);
                offset++;
              }
              out.addByte(v & 0xFF);
            } else {
              out.addByte(n);
            }
        }
        continue;
      }
      if (b == 0x28) {
        depth++;
        out.addByte(b);
        continue;
      }
      if (b == 0x29) {
        depth--;
        if (depth > 0) {
          out.addByte(b);
        }
        continue;
      }
      out.addByte(b);
    }
    return PdfCosString(out.takeBytes());
  }

  PdfCosArray _parseArray() {
    offset++; // [
    final List<PdfCos> items = <PdfCos>[];
    while (true) {
      skipWsAndComments();
      if (offset >= _len) {
        throw const PdfOpenException(PdfOpenError.badXref, 'Unclosed array');
      }
      if (bytes[offset] == 0x5D) {
        offset++;
        return PdfCosArray(items);
      }
      items.add(parseValue());
    }
  }

  PdfCosDict _parseDict() {
    offset += 2; // <<
    final Map<String, PdfCos> values = <String, PdfCos>{};
    while (true) {
      skipWsAndComments();
      if (offset + 1 < _len &&
          bytes[offset] == 0x3E &&
          bytes[offset + 1] == 0x3E) {
        offset += 2;
        return PdfCosDict(values);
      }
      final PdfCos key = parseValue();
      if (key is! PdfCosName) {
        throw const PdfOpenException(
          PdfOpenError.badXref,
          'Dictionary key is not a name',
        );
      }
      values[key.value] = parseValue();
    }
  }

  /// Finds the last `startxref` offset, or `-1`.
  int findLastStartXref() {
    final Uint8List needle = Uint8List.fromList('startxref'.codeUnits);
    for (int i = _len - needle.length; i >= 0; i--) {
      var ok = true;
      for (int j = 0; j < needle.length; j++) {
        if (bytes[i + j] != needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        offset = i + needle.length;
        skipWsAndComments();
        return _readIntToken();
      }
    }
    return -1;
  }

  /// headerVersion API.
  String readHeaderVersion() {
    if (_len < 8) {
      throw const PdfOpenException(PdfOpenError.badHeader);
    }
    if (bytes[0] != 0x25 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x44 ||
        bytes[3] != 0x46 ||
        bytes[4] != 0x2D) {
      throw const PdfOpenException(PdfOpenError.badHeader);
    }
    final int start = 5;
    var end = start;
    while (end < _len &&
        bytes[end] != 0x0A &&
        bytes[end] != 0x0D &&
        bytes[end] != 0x20) {
      end++;
    }
    return String.fromCharCodes(bytes.sublist(start, end));
  }
}
