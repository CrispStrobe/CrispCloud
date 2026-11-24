import 'dart:typed_data';

import '../opc/zip/deflate_codec.dart';
import 'file/cos/pdf_open_error.dart';

/// FlateDecode wrapper for PDF content and font streams.
abstract final class PdfFlate {
  /// compress API.
  static Uint8List compress(List<int> data) {
    final Uint8List raw = RawDeflate.deflate(data);
    // Wrap raw DEFLATE in a zlib container (CMF/FLG + Adler-32).
    return _zlibWrap(raw, data);
  }

  /// Maximum decoded bytes for a single Flate stream.
  ///
  /// Raw stream data is already capped before it reaches here; this bound is
  /// the second, ratio-independent guard against a DEFLATE expansion bomb.
  static const int maxDecodedBytes = 64 * 1024 * 1024;

  /// Inflates a FlateDecode stream (zlib, or raw DEFLATE if the wrapper is absent).
  ///
  /// Producers often omit or truncate the Adler-32 trailer. The inflater stops
  /// at BFINAL, so leftover checksum bytes are ignored — they must not be
  /// sliced off before inflate.
  static Uint8List decompress(
    Uint8List data, {
    int maxOutputBytes = maxDecodedBytes,
  }) {
    if (maxOutputBytes < 0) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
    if (data.length < 2) {
      throw const FormatException('Truncated Flate stream');
    }
    if (_isZlibHeader(data[0], data[1])) {
      var start = 2;
      if (data[1] & 0x20 != 0) {
        if (data.length < 6) {
          throw const FormatException('Truncated zlib dictionary');
        }
        start = 6;
      }
      try {
        return _inflate(Uint8List.sublistView(data, start), maxOutputBytes);
      } on ZipDeflateException {
        if (data.length > start + 4) {
          return _inflate(
            Uint8List.sublistView(data, start, data.length - 4),
            maxOutputBytes,
          );
        }
        rethrow;
      }
    }
    return _inflate(data, maxOutputBytes);
  }

  static Uint8List _inflate(Uint8List data, int maxOutputBytes) {
    try {
      return RawDeflate.inflate(data, maxOutputBytes: maxOutputBytes);
    } on ZipDeflateLimitException {
      throw const PdfOpenException(
        PdfOpenError.limit,
        'Decoded Flate stream exceeds its limit',
      );
    }
  }

  static bool _isZlibHeader(int cmf, int flg) {
    return (cmf & 0x0F) == 8 && ((cmf << 8) + flg) % 31 == 0;
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
    return ((b << 16) | a) & 0xFFFFFFFF;
  }
}
