import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'image_edit_session.dart';

/// Options for an independent raster copy. The source save format is unchanged.
class ImageExportOptions {
  const ImageExportOptions({
    required this.format,
    this.width,
    this.height,
    this.jpegQuality = 90,
  });

  final ImageFileFormat format;
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
  final width = options.width;
  final height = options.height;
  if ((width == null) != (height == null) ||
      (width != null &&
          (width < 1 ||
              height! < 1 ||
              width > kImageEditorMaxDimension ||
              height > kImageEditorMaxDimension ||
              width * height > kImageEditorMaxPixels)) ||
      options.jpegQuality < 1 ||
      options.jpegQuality > 100) {
    throw ArgumentError('Invalid image export options');
  }
  var pixels = image.decodeImage(source);
  if (pixels == null)
    throw const ImageEditException(ImageEditFailure.invalidImage);
  if (width != null &&
      height != null &&
      (width != pixels.width || height != pixels.height)) {
    pixels = image.copyResize(
      pixels,
      width: width,
      height: height,
      interpolation: image.Interpolation.cubic,
    );
  }
  final Uint8List output;
  if (options.format == ImageFileFormat.jpeg) {
    final opaque = image.Image(
      width: pixels.width,
      height: pixels.height,
      numChannels: 3,
    );
    image.fill(opaque, color: image.ColorRgb8(255, 255, 255));
    image.compositeImage(opaque, pixels);
    output = image.encodeJpg(opaque, quality: options.jpegQuality);
  } else {
    output = image.encodePng(pixels);
  }
  validateImageEditorOutput(output, options.format);
  return output;
}
