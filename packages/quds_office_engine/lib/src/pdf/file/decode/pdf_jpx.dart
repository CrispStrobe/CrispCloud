import 'dart:typed_data';

import 'package:j2k/j2k.dart' as j2k;

import '../cos/pdf_cos.dart';
import '../cos/pdf_open_error.dart';

/// Normalized, straight-alpha RGB888 or RGBA8888 image for the display list.
final class PdfJpxImage {
  const PdfJpxImage(this.pixels, {
    required this.isGray,
    required this.hasAlpha,
  });

  final Uint8List pixels;
  final bool isGray;
  final bool hasAlpha;
}

/// PDF JPEG 2000 Part 1 adapter for JP2 and raw J2K codestreams.
/// Other PDF color spaces and JPEG 2000 extensions stay typed-unsupported.
abstract final class PdfJpx {
  static PdfJpxImage decode(
    Uint8List data,
    PdfCosDict dict, {
    PdfCos? colorSpace,
  }) {
    if (data.length > 16 * 1024 * 1024 ||
        (dict['ImageMask'] is PdfCosBool &&
            (dict['ImageMask'] as PdfCosBool).value)) {
      throw const PdfFilterUnsupported('JPXDecode');
    }
    final String? cs = pdfCosName(colorSpace);
    if (colorSpace != null &&
        cs != 'DeviceGray' && cs != 'DeviceRGB' && cs != 'DeviceCMYK') {
      throw const PdfFilterUnsupported('JPXDecode');
    }
    final int alphaMode = pdfCosInt(dict['SMaskInData']) ?? 0;
    if (alphaMode < 0 || alphaMode > 2 ||
        (alphaMode != 0 && dict['SMask'] != null)) {
      throw const PdfFilterUnsupported('JPXDecode');
    }
    try {
      final j2k.Jpeg2000Image image = j2k.decodeJpeg2000(
        data,
        options: j2k.Jpeg2000DecodeOptions(
          maxPixels: 16 * 1024 * 1024,
          maxDimension: 8192,
          // PDF's explicit device color space overrides JP2 metadata.
          applyColorSpace: cs == null,
        ),
      );
      final int? width = pdfCosInt(dict['Width']);
      final int? height = pdfCosInt(dict['Height']);
      if ((width != null && image.width != width) ||
          (height != null && image.height != height)) {
        throw const PdfFilterUnsupported('JPXDecode');
      }
      final int count = image.width * image.height;
      final int channels = image.components;
      final int colors = switch (cs) {
        'DeviceGray' => 1,
        'DeviceRGB' => 3,
        'DeviceCMYK' => 4,
        _ => image.colorComponents,
      };
      final bool alpha = alphaMode != 0;
      if ((colors != 1 && colors != 3 && colors != 4) ||
          (colors == 4 && cs != 'DeviceCMYK') ||
          (alpha && (channels != colors + 1 || !image.hasAlpha)) ||
          (!alpha && channels != colors &&
              !(channels == colors + 1 && image.hasAlpha)) ||
          image.pixels.length != count * channels) {
        throw const PdfFilterUnsupported('JPXDecode');
      }
      final int stride = alpha ? 4 : 3;
      final Uint8List out = Uint8List(count * stride);
      for (int i = 0; i < count; i++) {
        final int src = i * channels;
        final int dst = i * stride;
        final int a = channels > colors ? image.pixels[src + colors] : 255;
        int sample(int component) {
          final int value = image.pixels[src + component];
          if (alphaMode != 2) {
            return value;
          }
          return a == 0 ? 0 : ((value * 255 + a ~/ 2) ~/ a).clamp(0, 255);
        }
        if (colors == 1) {
          out[dst] = out[dst + 1] = out[dst + 2] = sample(0);
        } else if (colors == 3) {
          for (int c = 0; c < 3; c++) {
            out[dst + c] = sample(c);
          }
        } else {
          final int k = sample(3);
          for (int c = 0; c < 3; c++) {
            out[dst + c] = ((255 - sample(c)) * (255 - k) + 127) ~/ 255;
          }
        }
        if (alpha) {
          out[dst + 3] = a;
        }
      }
      return PdfJpxImage(out, isGray: colors == 1, hasAlpha: alpha);
    } on j2k.Jpeg2000Exception {
      throw const PdfFilterUnsupported('JPXDecode');
    }
  }
}
