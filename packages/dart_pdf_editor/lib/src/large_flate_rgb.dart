import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// Returns dimensions only for a large, simple RGB sample plane. Masks,
/// prediction, custom decode arrays and other color models use the PDF decoder.
(int, int)? largeUnpredictedRgbSize(CosDocument cos, CosDictionary dict) {
  final width = cos.resolve(dict['Width']);
  final height = cos.resolve(dict['Height']);
  if (width is! CosInteger ||
      height is! CosInteger ||
      width.value <= 0 ||
      height.value <= 0 ||
      width.value * height.value * 3 <= 64 * 1024 * 1024 ||
      cos.resolve(dict['BitsPerComponent']) != const CosInteger(8) ||
      const ['DecodeParms', 'Decode', 'Mask', 'SMask', 'ImageMask']
          .any(dict.containsKey)) {
    return null;
  }
  final filters = pdfImageFilters(cos, dict);
  if (filters.length != 1 ||
      !const {'FlateDecode', 'Fl'}.contains(filters.single)) {
    return null;
  }
  final color = cos.resolve(dict['ColorSpace']);
  if (color != const CosName('DeviceRGB')) {
    if (color is! CosArray ||
        color.length != 2 ||
        cos.resolve(color[0]) != const CosName('ICCBased')) {
      return null;
    }
    final profile = cos.resolve(color[1]);
    if (profile is! CosStream ||
        cos.resolve(profile.dictionary['N']) != const CosInteger(3)) {
      return null;
    }
  }
  return (width.value, height.value);
}

/// Downsamples an unpredicted, opaque 8-bit RGB Flate image without storing
/// its whole decoded plane. Storage depends on the preview size and one row.
({Uint8List rgb, int width, int height}) decodeLargePdfRgb(
  Uint8List compressed,
  int width,
  int height, {
  int maxSide = 2560,
}) {
  if (compressed.length > 64 * 1024 * 1024) {
    throw const FormatException('Oversize compressed RGB stream');
  }
  const maxSourcePixels = 32 * 1024 * 1024;
  if (width < 1 ||
      height < 1 ||
      width > 16384 ||
      height > 16384 ||
      width * height > maxSourcePixels ||
      maxSide < 1 ||
      maxSide > 2560) {
    throw const FormatException('Oversize RGB image dimensions');
  }
  final longest = width > height ? width : height;
  final scale = longest > maxSide ? maxSide / longest : 1.0;
  final targetWidth = (width * scale).round().clamp(1, width);
  final targetHeight = (height * scale).round().clamp(1, height);
  final rgb = Uint8List(targetWidth * targetHeight * 3);
  final columns = List<int>.generate(
    targetWidth,
    (x) => ((2 * x + 1) * width ~/ (2 * targetWidth)) * 3,
    growable: false,
  );
  final decoded = const ZLibDecoder().decodeLazy(
    InputMemoryStream(compressed),
    verify: true,
  );
  var targetY = 0;
  var targetOffset = 0;
  final rowBytes = width * 3;
  try {
    for (var row = 0; row < height; row++) {
      final pixels = decoded.readBytes(rowBytes).toUint8List();
      if (pixels.length != rowBytes) {
        throw const FormatException('Truncated RGB image stream');
      }
      if (row != (2 * targetY + 1) * height ~/ (2 * targetHeight)) continue;
      for (final x in columns) {
        rgb[targetOffset++] = pixels[x];
        rgb[targetOffset++] = pixels[x + 1];
        rgb[targetOffset++] = pixels[x + 2];
      }
      targetY++;
    }
    if (!decoded.isEOS || targetOffset != rgb.length) {
      throw const FormatException('RGB image length differs from dimensions');
    }
    return (rgb: rgb, width: targetWidth, height: targetHeight);
  } finally {
    decoded.closeSync();
  }
}
