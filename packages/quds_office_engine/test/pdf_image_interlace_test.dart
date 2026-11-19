import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// 3x3 solid red, 8-bit RGBA, Adam7-interlaced PNG. The hand-written PNG
/// decoder does not deinterlace, so this must use the package fallback.
final String _interlacedRedPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAADCAYAAAEhL4UpAAAAIGNIUk0AAHomAACAhAAA'
    '+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGYktHRAD/AP8A/6C9p5MAAAAHdElN'
    'RQfqCxMTKg+vw5e0AAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTExLTE5VDE5OjQyOjE1'
    'KzAwOjAwphEl6QAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0xMS0xOVQxOTo0MjoxNSsw'
    'MDowMNdMnVUAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMTEtMTlUMTk6NDI6MTUr'
    'MDA6MDCAWbyKAAAAHElEQVQI10XIoQEAAAjAIPT/n2eUiEg0EYgWvnAMfQn7WnJRUwAA'
    'AABJRU5ErkJggg==';

void main() {
  test('interlaced RGBA PNG decodes through the image fallback', () {
    final PdfRaster? raster = PdfImageCodec.decode(
      base64Decode(_interlacedRedPngBase64),
    );
    expect(raster, isNotNull);
    expect(raster!.width, 3);
    expect(raster.height, 3);
    expect(raster.rgb.sublist(0, 3), <int>[255, 0, 0]);
    expect(raster.alpha, isNotNull);
    expect(raster.alpha!.first, 255);
  });
}
