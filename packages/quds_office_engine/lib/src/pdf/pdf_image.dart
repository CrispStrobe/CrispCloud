import 'dart:typed_data';

import '../opc/zip/deflate_codec.dart';

/// Decoded raster ready for a PDF image XObject.
class PdfRaster {
  /// PdfRaster API.
  const PdfRaster({
    required this.width,
    required this.height,
    required this.rgb,
    this.jpegBytes,
    this.alpha,
  });

  /// width API.
  final int width;

  /// height API.
  final int height;

  /// rgb API.
  final Uint8List rgb;

  /// jpegBytes API.
  final Uint8List? jpegBytes;

  /// Per-pixel opacity when the source PNG had an alpha channel.
  final Uint8List? alpha;

  /// isJpeg API.
  bool get isJpeg => jpegBytes != null;
}

/// PNG (IHDR/IDAT) and JPEG embedding helpers. No Flutter / `dart:ui`.
abstract final class PdfImageCodec {
  /// decode API.
  static PdfRaster? decode(Uint8List bytes) {
    return decodePng(bytes) ?? decodeJpeg(bytes);
  }

  /// decodeJpeg API.
  static PdfRaster? decodeJpeg(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return null;
    }
    var i = 2;
    var width = 0;
    var height = 0;
    while (i + 9 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final int marker = bytes[i + 1];
      if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
        height = (bytes[i + 5] << 8) | bytes[i + 6];
        width = (bytes[i + 7] << 8) | bytes[i + 8];
        break;
      }
      if (i + 3 >= bytes.length) {
        break;
      }
      final int len = (bytes[i + 2] << 8) | bytes[i + 3];
      i += 2 + len;
    }
    if (width <= 0 || height <= 0) {
      return null;
    }
    return PdfRaster(
      width: width,
      height: height,
      rgb: Uint8List(0),
      jpegBytes: bytes,
    );
  }

  /// decodePng API.
  static PdfRaster? decodePng(Uint8List bytes) {
    if (bytes.length < 33 ||
        bytes[0] != 0x89 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x4E ||
        bytes[3] != 0x47) {
      return null;
    }
    var offset = 8;
    var width = 0;
    var height = 0;
    var bitDepth = 8;
    var colorType = 2;
    final BytesBuilder idat = BytesBuilder(copy: false);
    List<int>? palette;
    List<int>? trns;
    while (offset + 12 <= bytes.length) {
      final int len = _u32(bytes, offset);
      final String type = String.fromCharCodes(
        bytes.sublist(offset + 4, offset + 8),
      );
      final int dataAt = offset + 8;
      if (dataAt + len + 4 > bytes.length) {
        break;
      }
      final Uint8List data = bytes.sublist(dataAt, dataAt + len);
      if (type == 'IHDR') {
        width = _u32(data, 0);
        height = _u32(data, 4);
        bitDepth = data[8];
        colorType = data[9];
      } else if (type == 'PLTE') {
        palette = data;
      } else if (type == 'tRNS') {
        trns = data;
      } else if (type == 'IDAT') {
        idat.add(data);
      } else if (type == 'IEND') {
        break;
      }
      offset = dataAt + len + 4;
    }
    if (width <= 0 || height <= 0 || bitDepth != 8) {
      return null;
    }
    final Uint8List compressed = idat.takeBytes();
    if (compressed.length < 6) {
      return null;
    }
    final Uint8List raw = RawDeflate.inflate(
      compressed.sublist(2, compressed.length - 4),
    );
    final int channels = switch (colorType) {
      0 => 1,
      2 => 3,
      3 => 1,
      4 => 2,
      6 => 4,
      _ => 0,
    };
    if (channels == 0) {
      return null;
    }
    final int stride = width * channels;
    final Uint8List rgb = Uint8List(width * height * 3);
    final bool keyed =
        trns != null && (colorType == 0 || colorType == 2 || colorType == 3);
    final Uint8List? alpha = (colorType == 4 || colorType == 6 || keyed)
        ? Uint8List(width * height)
        : null;
    final List<int> prev = List<int>.filled(stride, 0);
      var src = 0;
    var dst = 0;
    var dstA = 0;
    for (int y = 0; y < height; y++) {
      if (src >= raw.length) {
        return null;
      }
      final int filter = raw[src++];
      if (src + stride > raw.length) {
        return null;
      }
      final List<int> row = List<int>.filled(stride, 0);
      for (int x = 0; x < stride; x++) {
        final int cur = raw[src++];
        final int a = x >= channels ? row[x - channels] : 0;
        final int b = prev[x];
        final int c = x >= channels ? prev[x - channels] : 0;
        row[x] =
            (cur +
                switch (filter) {
                  1 => a,
                  2 => b,
                  3 => (a + b) >> 1,
                  4 => _paeth(a, b, c),
                  _ => 0,
                }) &
            0xFF;
      }
      for (int x = 0; x < width; x++) {
        late int r, g, b;
        switch (colorType) {
          case 0:
            r = g = b = row[x];
            if (alpha != null && keyed && trns.length >= 2) {
              alpha[dstA++] = row[x] == trns[1] ? 0 : 255;
            }
          case 2:
            r = row[x * 3];
            g = row[x * 3 + 1];
            b = row[x * 3 + 2];
            if (alpha != null && keyed && trns.length >= 6) {
              final bool match =
                  r == trns[1] && g == trns[3] && b == trns[5];
              alpha[dstA++] = match ? 0 : 255;
            }
          case 3:
            final int idx = row[x] * 3;
            if (palette == null || idx + 2 >= palette.length) {
              r = g = b = 0;
            } else {
              r = palette[idx];
              g = palette[idx + 1];
              b = palette[idx + 2];
            }
            if (alpha != null && keyed) {
              alpha[dstA++] = row[x] < trns.length ? trns[row[x]] : 255;
            }
          case 4:
            r = g = b = row[x * 2];
            alpha?[dstA++] = row[x * 2 + 1];
          case 6:
            r = row[x * 4];
            g = row[x * 4 + 1];
            b = row[x * 4 + 2];
            alpha?[dstA++] = row[x * 4 + 3];
          default:
            r = g = b = 0;
        }
        rgb[dst++] = r;
        rgb[dst++] = g;
        rgb[dst++] = b;
      }
      prev.setAll(0, row);
    }
    Uint8List? mask = alpha;
    if (mask != null && mask.every((int a) => a == 255)) {
      mask = null;
    }
    return PdfRaster(width: width, height: height, rgb: rgb, alpha: mask);
  }

  static int _paeth(int a, int b, int c) {
    final int p = a + b - c;
    final int pa = (p - a).abs();
    final int pb = (p - b).abs();
    final int pc = (p - c).abs();
    if (pa <= pb && pa <= pc) {
      return a;
    }
    if (pb <= pc) {
      return b;
    }
    return c;
  }

  static int _u32(Uint8List b, int i) =>
      (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
}
