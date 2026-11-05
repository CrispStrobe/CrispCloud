import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'image_edit_session.dart';

enum ImageExportFormat { png, jpeg, webp }

ImageExportFormat imageExportFormatForSource(ImageFileFormat format) =>
    format == ImageFileFormat.png
    ? ImageExportFormat.png
    : ImageExportFormat.jpeg;

String imageExportExtension(ImageExportFormat format) => switch (format) {
  ImageExportFormat.png => 'png',
  ImageExportFormat.jpeg => 'jpg',
  ImageExportFormat.webp => 'webp',
};

/// Options for an independent raster copy. The source save format is unchanged.
class ImageExportOptions {
  const ImageExportOptions({
    required this.format,
    this.width,
    this.height,
    this.jpegQuality = 90,
  });

  final ImageExportFormat format;
  final int? width;
  final int? height;
  final int jpegQuality;
}

/// Converts a validated capture into a separately saved image.
/// Transparent pixels are composited on white for JPEG.
Uint8List encodeImageExport(
  Uint8List source,
  ImageFileFormat sourceFormat,
  ImageExportOptions options,
) {
  validateImageEditorOutput(source, sourceFormat);
  final requestedWidth = options.width;
  final requestedHeight = options.height;
  if ((requestedWidth != null &&
          (requestedWidth < 1 || requestedWidth > kImageEditorMaxDimension)) ||
      (requestedHeight != null &&
          (requestedHeight < 1 ||
              requestedHeight > kImageEditorMaxDimension)) ||
      options.jpegQuality < 1 ||
      options.jpegQuality > 100) {
    throw ArgumentError('Invalid image export options');
  }
  var pixels = image.decodeImage(source);
  if (pixels == null) {
    throw const ImageEditException(ImageEditFailure.invalidImage);
  }
  final width =
      requestedWidth ??
      (requestedHeight == null
          ? pixels.width
          : (pixels.width * requestedHeight / pixels.height).round().clamp(
              1,
              kImageEditorMaxDimension + 1,
            ));
  final height =
      requestedHeight ??
      (requestedWidth == null
          ? pixels.height
          : (pixels.height * requestedWidth / pixels.width).round().clamp(
              1,
              kImageEditorMaxDimension + 1,
            ));
  if (width > kImageEditorMaxDimension ||
      height > kImageEditorMaxDimension ||
      width * height > kImageEditorMaxPixels) {
    throw ArgumentError('Invalid image export dimensions');
  }
  if (width != pixels.width || height != pixels.height) {
    pixels = image.copyResize(
      pixels,
      width: width,
      height: height,
      interpolation: image.Interpolation.cubic,
    );
  }
  final Uint8List output;
  if (options.format == ImageExportFormat.jpeg) {
    final opaque = image.Image(
      width: pixels.width,
      height: pixels.height,
      numChannels: 3,
    );
    image.fill(opaque, color: image.ColorRgb8(255, 255, 255));
    image.compositeImage(opaque, pixels);
    output = image.encodeJpg(opaque, quality: options.jpegQuality);
  } else if (options.format == ImageExportFormat.webp) {
    output = image.encodeWebP(pixels);
  } else {
    output = image.encodePng(pixels);
  }
  validateImageExport(output, options.format);
  return output;
}

/// Validate exported WebP independently, including the RIFF length and frame
/// count. Other export formats use the existing strict raster validator.
void validateImageExport(Uint8List bytes, ImageExportFormat format) {
  if (format != ImageExportFormat.webp) {
    validateImageEditorOutput(
      bytes,
      format == ImageExportFormat.png
          ? ImageFileFormat.png
          : ImageFileFormat.jpeg,
    );
    return;
  }
  if (bytes.length > kImageEditorOutputLimitBytes)
    throw const ImageEditException(ImageEditFailure.outputTooLarge);
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WEBP' ||
      ByteData.sublistView(bytes).getUint32(4, Endian.little) + 8 !=
          bytes.length) {
    throw const ImageEditException(ImageEditFailure.invalidImage);
  }
  try {
    final decoder = image.WebPDecoder()..maxPixels = kImageEditorMaxPixels;
    final info = decoder.startDecode(bytes);
    if (info?.hasAnimation == true) {
      throw const ImageEditException(ImageEditFailure.animatedImage);
    }
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width > kImageEditorMaxDimension ||
        info.height > kImageEditorMaxDimension ||
        info.width * info.height > kImageEditorMaxPixels ||
        decoder.decode(bytes) == null) {
      throw const ImageEditException(ImageEditFailure.invalidImage);
    }
  } on ImageEditException {
    rethrow;
  } catch (_) {
    throw const ImageEditException(ImageEditFailure.invalidImage);
  }
}
