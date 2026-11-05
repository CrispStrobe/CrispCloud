import 'dart:typed_data';

import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:crisp_cloud/services/image_raster_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  for (final format in AdditionalRasterFormat.values) {
    test('$format round trip preserves opaque and transparent pixels', () {
      final pixels = image.Image(width: 3, height: 2, numChannels: 4);
      image.fill(pixels, color: image.ColorRgba8(10, 20, 30, 255));
      pixels.setPixelRgba(0, 0, 0, 0, 0, 0);
      pixels.setPixelRgba(2, 1, 80, 90, 100, 128);
      final bytes = encodeAdditionalRaster(pixels, format);
      final decoded = decodeAdditionalRaster(bytes, format);
      expect((decoded.width, decoded.height), (3, 2));
      expect(decoded.getPixel(0, 0).a, 0);
      expect(decoded.getPixel(1, 1).r, 10);
      expect(decoded.getPixel(2, 1).a, 128);
    });
    test('$format rejects invalid and truncated data', () {
      expect(
        () => decodeAdditionalRaster(Uint8List(20), format),
        throwsA(isA<ImageEditException>()),
      );
    });
  }
  test('multi-page TIFF is rejected before editing', () {
    final source = image.encodeTiff(image.Image(width: 2, height: 2));
    final header = ByteData.sublistView(source);
    final littleEndian = source[0] == 0x49;
    final endian = littleEndian ? Endian.little : Endian.big;
    final firstIfd = header.getUint32(4, endian);
    final count = header.getUint16(firstIfd, endian);
    final length = 2 + count * 12 + 4;
    final appended = Uint8List(source.length + length);
    appended.setRange(0, source.length, source);
    appended.setRange(
      source.length,
      appended.length,
      source.sublist(firstIfd, firstIfd + length),
    );
    final data = ByteData.sublistView(appended);
    data.setUint32(firstIfd + length - 4, source.length, endian);
    data.setUint32(source.length + length - 4, 0, endian);
    expect(
      () => decodeAdditionalRaster(appended, AdditionalRasterFormat.tiff),
      throwsA(
        isA<ImageEditException>().having(
          (e) => e.reason,
          'reason',
          ImageEditFailure.multiPageImage,
        ),
      ),
    );
  });
}
