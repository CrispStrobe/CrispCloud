import 'dart:typed_data';

import '../opc/zip/deflate_codec.dart';
import 'file/cos/pdf_open_error.dart';

/// FlateDecode wrapper for PDF content and font streams.
abstract final class PdfFlate {
  /// Maximum decoded bytes in a PDF Flate stream.
  static const int maxDecodedBytes = 64 * 1024 * 1024;

  /// compress API.
  static Uint8List compress(List<int> data) {
    final Uint8List raw = RawDeflate.deflate(data);
    // Wrap raw DEFLATE in a zlib container (CMF/FLG + Adler-32).
    return _zlibWrap(raw, data);
  }

  /// Inflates an RFC 1950 wrapped PDF Flate stream and verifies its checksum.
  static Uint8List decompress(
    Uint8List data, {
    int maxOutputBytes = maxDecodedBytes,
  }) => decompressZlibPrefix(data, maxOutputBytes: maxOutputBytes).bytes;

  /// Decode a checksummed zlib stream followed by unrelated PDF content.
  static ({Uint8List bytes, int consumed}) decompressZlibPrefix(
    Uint8List data, {
    required int maxOutputBytes,
  }) {
    if (maxOutputBytes < 0) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
    if (data.length < 8) {
      throw const FormatException('Truncated zlib stream');
    }
    final int cmf = data[0];
    final int flg = data[1];
    final int cinfo = cmf >> 4;
    if ((cmf & 15) != 8 || cinfo > 7 || ((cmf << 8) + flg) % 31 != 0) {
      throw const FormatException('Invalid zlib header');
    }
    if ((flg & 0x20) != 0) {
      throw const FormatException('Preset zlib dictionaries are unsupported');
    }
    final ({Uint8List bytes, int consumed}) result;
    try {
      result = RawDeflate.inflatePrefix(
        Uint8List.sublistView(data, 2),
        maxOutputBytes: maxOutputBytes.clamp(0, maxDecodedBytes),
        windowBytes: 1 << (cinfo + 8),
      );
    } on ZipDeflateLimitException {
      throw const PdfOpenException(
        PdfOpenError.limit,
        'Decoded Flate stream exceeds its limit',
      );
    }
    final tail = 2 + result.consumed;
    if (tail + 4 > data.length ||
        ByteData.sublistView(data, tail, tail + 4).getUint32(0) !=
            _adler32(result.bytes)) {
      throw const FormatException('Missing or invalid zlib Adler-32 checksum');
    }
    return (bytes: result.bytes, consumed: tail + 4);
  }

  static Uint8List _zlibWrap(Uint8List rawDeflate, List<int> original) {
    final Uint8List out = Uint8List(rawDeflate.length + 6);
    out[0] = 0x78; // CMF: deflate, 32k window
    out[1] = 0x9C; // FLG: default check bits
    out.setRange(2, 2 + rawDeflate.length, rawDeflate);
    final int adler = _adler32(original);
    final int tail = out.length - 4;
    out[tail] = (adler >> 24) & 0xFF;
    out[tail + 1] = (adler >> 16) & 0xFF;
    out[tail + 2] = (adler >> 8) & 0xFF;
    out[tail + 3] = adler & 0xFF;
    return out;
  }

  static int _adler32(List<int> data) {
    var a = 1;
    var b = 0;
    for (final int byte in data) {
      a = (a + byte) % 65521;
      b = (b + a) % 65521;
    }
    return b * 65536 + a;
  }
}
