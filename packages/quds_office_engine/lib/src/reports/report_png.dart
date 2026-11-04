/// Tiny RGBA PNG encoder for barcodes and shapes in Office export.
library;

import 'dart:typed_data';

import '../pdf/pdf_stream.dart';

/// Uncompressed-filter PNG of [rgba] (row-major, 4 bytes per pixel).
Uint8List encodeRgbaPng(int width, int height, Uint8List rgba) {
  final BytesBuilder raw = BytesBuilder(copy: false);
  for (int y = 0; y < height; y++) {
    raw.addByte(0);
    raw.add(rgba.sublist(y * width * 4, (y + 1) * width * 4));
  }
  final Uint8List idat = PdfFlate.compress(raw.toBytes());
  final BytesBuilder out = BytesBuilder(copy: false)
    ..add(const <int>[137, 80, 78, 71, 13, 10, 26, 10])
    ..add(_chunk('IHDR', _ihdr(width, height)))
    ..add(_chunk('IDAT', idat))
    ..add(_chunk('IEND', Uint8List(0)));
  return out.toBytes();
}

/// Black modules of a QR matrix, with a quiet border of 4 cells.
Uint8List encodeMatrixPng(List<List<bool>> matrix) {
  final int n = matrix.isEmpty ? 1 : matrix.length;
  final int side = n + 8;
  final Uint8List rgba = Uint8List(side * side * 4);
  for (int i = 0; i < rgba.length; i += 4) {
    rgba[i] = 255;
    rgba[i + 1] = 255;
    rgba[i + 2] = 255;
    rgba[i + 3] = 255;
  }
  for (int r = 0; r < matrix.length; r++) {
    final List<bool> row = matrix[r];
    for (int c = 0; c < row.length && c < n; c++) {
      if (!row[c]) {
        continue;
      }
      final int i = ((r + 4) * side + (c + 4)) * 4;
      rgba[i] = 0;
      rgba[i + 1] = 0;
      rgba[i + 2] = 0;
    }
  }
  return encodeRgbaPng(side, side, rgba);
}

/// Black bars on white, one pixel wide per module and [barHeight] tall.
Uint8List encodeBarcodePng(List<bool> modules, {int barHeight = 40}) {
  final int width = modules.isEmpty ? 1 : modules.length;
  final int height = barHeight < 1 ? 1 : barHeight;
  final Uint8List rgba = Uint8List(width * height * 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int i = (y * width + x) * 4;
      final bool dark = x < modules.length && modules[x];
      rgba[i] = dark ? 0 : 255;
      rgba[i + 1] = dark ? 0 : 255;
      rgba[i + 2] = dark ? 0 : 255;
      rgba[i + 3] = 255;
    }
  }
  return encodeRgbaPng(width, height, rgba);
}

/// Filled rectangle or ellipse used when a shape has no paragraph equivalent.
Uint8List encodeShapePng({
  required int width,
  required int height,
  required int rgb,
  required bool ellipse,
}) {
  final int w = width < 1 ? 1 : width;
  final int h = height < 1 ? 1 : height;
  final int r = (rgb >> 16) & 0xFF;
  final int g = (rgb >> 8) & 0xFF;
  final int b = rgb & 0xFF;
  final Uint8List rgba = Uint8List(w * h * 4);
  final double cx = (w - 1) / 2;
  final double cy = (h - 1) / 2;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final bool inside = !ellipse ||
          ((x - cx) * (x - cx)) / (cx * cx + 0.01) +
                  ((y - cy) * (y - cy)) / (cy * cy + 0.01) <=
              1;
      final int i = (y * w + x) * 4;
      rgba[i] = r;
      rgba[i + 1] = g;
      rgba[i + 2] = b;
      rgba[i + 3] = inside ? 255 : 0;
    }
  }
  return encodeRgbaPng(w, h, rgba);
}

Uint8List _ihdr(int width, int height) {
  final ByteData data = ByteData(13);
  data.setUint32(0, width);
  data.setUint32(4, height);
  data.setUint8(8, 8);
  data.setUint8(9, 6);
  return data.buffer.asUint8List();
}

Uint8List _chunk(String type, Uint8List data) {
  final Uint8List name = Uint8List.fromList(type.codeUnits);
  final ByteData len = ByteData(4)..setUint32(0, data.length);
  final Uint8List body = Uint8List(name.length + data.length)
    ..setRange(0, name.length, name)
    ..setRange(name.length, name.length + data.length, data);
  final ByteData crc = ByteData(4)..setUint32(0, _crc(body));
  final Uint8List out = Uint8List(4 + body.length + 4);
  out.setRange(0, 4, len.buffer.asUint8List());
  out.setRange(4, 4 + body.length, body);
  out.setRange(4 + body.length, out.length, crc.buffer.asUint8List());
  return out;
}

int _crc(Uint8List data) {
  var c = 0xFFFFFFFF;
  for (final int byte in data) {
    c ^= byte;
    for (var i = 0; i < 8; i++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
  }
  return c ^ 0xFFFFFFFF;
}
