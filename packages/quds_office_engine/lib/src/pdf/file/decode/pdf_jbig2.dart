import 'dart:typed_data';

import 'package:jbig2/jbig2.dart' as jb;

import '../cos/pdf_cos.dart';
import '../cos/pdf_open_error.dart';

/// PDF JBIG2 adapter. Keeps the engine's existing expanded gray convention:
/// 0x00 is black and 0xFF is white.
abstract final class PdfJbig2 {
  static Uint8List decode(
    Uint8List data,
    PdfCosDict dict, {
    Uint8List? globals,
  }) {
    if (data.length + (globals?.length ?? 0) > 16 * 1024 * 1024) {
      throw const PdfFilterUnsupported('JBIG2Decode');
    }
    const options = jb.Jbig2DecodeOptions(
      maxPixels: 16 * 1024 * 1024,
      maxDimension: 8192,
    );
    try {
      final jb.Jbig2Image image = jb.isJbig2File(data) && globals == null
          ? jb.decodeJbig2(data, options: options)
          : jb.decodeJbig2Embedded(data, globals: globals, options: options);
      final int? width = pdfCosInt(dict['Width']);
      final int? height = pdfCosInt(dict['Height']);
      if ((width != null && image.width != width) ||
          (height != null && image.height != height)) {
        throw const PdfFilterUnsupported('JBIG2Decode');
      }
      return image.toGrayscale();
    } on jb.Jbig2Exception {
      throw const PdfFilterUnsupported('JBIG2Decode');
    } on Exception {
      // Segment parsing in jbig2 1.0.0 can also throw a plain Exception.
      throw const PdfFilterUnsupported('JBIG2Decode');
    } on ArgumentError {
      throw const PdfFilterUnsupported('JBIG2Decode');
    } on StateError {
      throw const PdfFilterUnsupported('JBIG2Decode');
    } on UnsupportedError {
      // Legal/unknown-length JBIG2 segments and some 32-bit header forms are
      // rejected by the current codec with an Error. Degrade to a typed image
      // placeholder instead of aborting the whole page/open.
      throw const PdfFilterUnsupported('JBIG2Decode');
    }
  }
}
