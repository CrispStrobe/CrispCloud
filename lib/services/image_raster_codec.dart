import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'image_edit_session.dart';

enum AdditionalRasterFormat { bmp, tiff }

/// Decode only a bounded, single-image container. Multi-page TIFF is never
/// flattened over the source by this editor.
image.Image decodeAdditionalRaster(
  Uint8List bytes,
  AdditionalRasterFormat format, {
  int maxBytes = kImageEditorInputLimitBytes,
}) {
  if (bytes.length > maxBytes)
    throw ImageEditException(
      maxBytes == kImageEditorInputLimitBytes
          ? ImageEditFailure.inputTooLarge
          : ImageEditFailure.outputTooLarge,
    );
  if (bytes.length < 14)
    throw const ImageEditException(ImageEditFailure.invalidImage);
  if (format == AdditionalRasterFormat.bmp) {
    if (bytes[0] != 0x42 ||
        bytes[1] != 0x4d ||
        ByteData.sublistView(bytes).getUint32(2, Endian.little) !=
            bytes.length) {
      throw const ImageEditException(ImageEditFailure.invalidImage);
    }
  } else {
    final signature = bytes.sublist(0, 4);
    if (!(signature[0] == 0x49 &&
            signature[1] == 0x49 &&
            signature[2] == 42 &&
            signature[3] == 0) &&
        !(signature[0] == 0x4d &&
            signature[1] == 0x4d &&
            signature[2] == 0 &&
            signature[3] == 42)) {
      throw const ImageEditException(ImageEditFailure.invalidImage);
    }
  }
  try {
    final image.Decoder decoder = format == AdditionalRasterFormat.bmp
        ? image.BmpDecoder(maxPixels: kImageEditorMaxPixels)
        : image.TiffDecoder(maxPixels: kImageEditorMaxPixels);
    final info = decoder.startDecode(bytes);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width > kImageEditorMaxDimension ||
        info.height > kImageEditorMaxDimension ||
        info.width * info.height > kImageEditorMaxPixels ||
        info.numFrames == 0) {
      throw const ImageEditException(ImageEditFailure.invalidImage);
    }
    if (info.numFrames != 1)
      throw const ImageEditException(ImageEditFailure.multiPageImage);
    final result = decoder.decode(bytes);
    if (result == null)
      throw const ImageEditException(ImageEditFailure.invalidImage);
    return result;
  } on ImageEditException {
    rethrow;
  } catch (_) {
    throw const ImageEditException(ImageEditFailure.invalidImage);
  }
}

/// Verify visible output pixels rather than assuming every encoder preserves
/// transparency and color. Invisible RGB under zero alpha is not significant.
Uint8List encodeAdditionalRaster(
  image.Image pixels,
  AdditionalRasterFormat format,
) {
  final output = format == AdditionalRasterFormat.bmp
      ? image.encodeBmp(pixels)
      : image.encodeTiff(pixels);
  final decoded = decodeAdditionalRaster(
    output,
    format,
    maxBytes: kImageEditorOutputLimitBytes,
  );
  if (decoded.width != pixels.width || decoded.height != pixels.height)
    throw const ImageEditException(ImageEditFailure.rasterEncodingLoss);
  for (final pixel in pixels) {
    final actual = decoded.getPixel(pixel.x, pixel.y);
    if (pixel.a != actual.a ||
        (pixel.a != 0 &&
            (pixel.r != actual.r ||
                pixel.g != actual.g ||
                pixel.b != actual.b))) {
      throw const ImageEditException(ImageEditFailure.rasterEncodingLoss);
    }
  }
  return output;
}
