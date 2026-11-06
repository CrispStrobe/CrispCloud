import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'image_edit_session.dart';

/// Decode a single-frame GIF without silently flattening an animation.
image.Image decodeStaticGif(
  Uint8List bytes, {
  int maxBytes = kImageEditorInputLimitBytes,
}) {
  if (bytes.length > maxBytes)
    throw ImageEditException(
      maxBytes == kImageEditorInputLimitBytes
          ? ImageEditFailure.inputTooLarge
          : ImageEditFailure.outputTooLarge,
    );
  if (bytes.length < 14 ||
      !const [
        'GIF87a',
        'GIF89a',
      ].contains(String.fromCharCodes(bytes.sublist(0, 6))) ||
      bytes.last != 0x3b) {
    throw const ImageEditException(ImageEditFailure.invalidImage);
  }
  try {
    final decoder = image.GifDecoder()..maxPixels = kImageEditorMaxPixels;
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
      throw const ImageEditException(ImageEditFailure.animatedImage);
    final pixels = decoder.decode(bytes);
    if (pixels == null)
      throw const ImageEditException(ImageEditFailure.invalidImage);
    return pixels;
  } on ImageEditException {
    rethrow;
  } catch (_) {
    throw const ImageEditException(ImageEditFailure.invalidImage);
  }
}

/// Encode only if every visible pixel can be represented without quantization.
/// GIF supports one fully transparent palette entry and at most 256 colors.
Uint8List encodeExactGif(image.Image pixels) {
  final palette = image.PaletteUint8(256, 4);
  for (var i = 0; i < 256; i++) {
    palette.setRgba(i, 0, 0, 0, 255);
  }
  final indexed = image.Image(
    width: pixels.width,
    height: pixels.height,
    numChannels: 1,
    withPalette: true,
    palette: palette,
  );
  final colors = <int, int>{};
  for (final pixel in pixels) {
    final a = pixel.a.toInt();
    if (a != 0 && a != 255)
      throw const ImageEditException(ImageEditFailure.gifColorLimit);
    final key = a == 0
        ? 0
        : (0xff000000 |
              (pixel.r.toInt() << 16) |
              (pixel.g.toInt() << 8) |
              pixel.b.toInt());
    var index = colors[key];
    if (index == null) {
      if (colors.length == 256)
        throw const ImageEditException(ImageEditFailure.gifColorLimit);
      index = colors.length;
      colors[key] = index;
      palette.setRgba(
        index,
        a == 0 ? 0 : pixel.r,
        a == 0 ? 0 : pixel.g,
        a == 0 ? 0 : pixel.b,
        a,
      );
    }
    indexed.setPixelIndex(pixel.x, pixel.y, index);
  }
  final bytes = image.encodeGif(indexed, singleFrame: true);
  final decoded = decodeStaticGif(
    bytes,
    maxBytes: kImageEditorOutputLimitBytes,
  );
  for (final pixel in pixels) {
    final actual = decoded.getPixel(pixel.x, pixel.y);
    if (pixel.a != actual.a ||
        (pixel.a != 0 &&
            (pixel.r != actual.r ||
                pixel.g != actual.g ||
                pixel.b != actual.b))) {
      throw const ImageEditException(ImageEditFailure.gifColorLimit);
    }
  }
  return bytes;
}
