import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:image/image.dart' as image;

/// Small, deterministic pixels; fixtures never depend on network images.
Uint8List buildImageEditorFixture({
  ImageFileFormat format = ImageFileFormat.png,
  int width = 24,
  int height = 16,
  int seed = 0,
  bool transparent = true,
}) {
  final pixels = image.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      pixels.setPixelRgba(
        x,
        y,
        (x * 17 + seed * 31) % 256,
        (y * 23 + seed * 13) % 256,
        ((x + y) * 7 + seed * 47) % 256,
        transparent && x == 0 ? 0 : 255,
      );
    }
  }
  return format == ImageFileFormat.png
      ? image.encodePng(pixels)
      : image.encodeJpg(pixels, quality: 95);
}

Uint8List imageTestPngChunk(String type, List<int> payload) {
  final result = Uint8List(payload.length + 12);
  final data = ByteData.sublistView(result);
  data.setUint32(0, payload.length);
  result.setRange(4, 8, type.codeUnits);
  result.setRange(8, 8 + payload.length, payload);
  data.setUint32(
    payload.length + 8,
    getCrc32(Uint8List.sublistView(result, 4, payload.length + 8)),
  );
  return result;
}

Uint8List imageTestAnimatedPng() {
  final png = buildImageEditorFixture();
  final animation = ByteData(8)
    ..setUint32(0, 2)
    ..setUint32(4, 0);
  return Uint8List.fromList([
    ...png.sublist(0, 33),
    ...imageTestPngChunk('acTL', animation.buffer.asUint8List()),
    ...png.sublist(33),
  ]);
}

Uint8List imageTestPngWithDimensions(int width, int height) {
  final png = buildImageEditorFixture();
  final header = Uint8List.fromList(png.sublist(16, 29));
  ByteData.sublistView(header)
    ..setUint32(0, width)
    ..setUint32(4, height);
  return Uint8List.fromList([
    ...png.sublist(0, 8),
    ...imageTestPngChunk('IHDR', header),
    ...png.sublist(33),
  ]);
}

/// Valid container checksums with invalid compressed pixels, used to prove
/// that header checks alone cannot authorize a save.
Uint8List imageTestUndecodablePng() {
  final png = buildImageEditorFixture();
  final data = ByteData.sublistView(png);
  var offset = 8;
  while (offset < png.length) {
    final length = data.getUint32(offset);
    final type = String.fromCharCodes(png.sublist(offset + 4, offset + 8));
    if (type == 'IDAT') {
      return Uint8List.fromList([
        ...png.sublist(0, offset),
        ...imageTestPngChunk('IDAT', List<int>.filled(length, 0)),
        ...png.sublist(offset + length + 12),
      ]);
    }
    offset += length + 12;
  }
  throw StateError('The PNG fixture has no IDAT.');
}
