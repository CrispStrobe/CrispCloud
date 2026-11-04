import 'dart:math' as math;
import 'dart:typed_data';

/// Intrinsic pixel size of a raster image.
class ImageSize {
  /// ImageSize API.
  const ImageSize(this.widthPx, this.heightPx);

  /// widthPx API.
  final int widthPx;

  /// heightPx API.
  final int heightPx;

  /// isValid API.
  bool get isValid => widthPx > 0 && heightPx > 0;
}

/// Raster contain-fit helpers shared by Word, PPTX, and PDF writers.
abstract final class ImageFit {
  /// EMUs per CSS/pixel (96 dpi).
  static const int emuPerPx = 9525;

  /// readSize API.
  static ImageSize? readSize(Uint8List bytes) {
    return readPngSize(bytes) ?? readJpegSize(bytes);
  }

  /// readPngSize API.
  static ImageSize? readPngSize(Uint8List bytes) {
    if (bytes.length < 24) {
      return null;
    }
    if (bytes[0] != 0x89 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x4E ||
        bytes[3] != 0x47) {
      return null;
    }
    final int width = _u32be(bytes, 16);
    final int height = _u32be(bytes, 20);
    if (width <= 0 || height <= 0) {
      return null;
    }
    return ImageSize(width, height);
  }

  /// Reads SOF0 / SOF1 / SOF2 dimensions from a JPEG bitstream.
  static ImageSize? readJpegSize(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return null;
    }
    var i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final int marker = bytes[i + 1];
      if (marker == 0xD8 || marker == 0xD9 || marker == 0x01) {
        i += 2;
        continue;
      }
      if (marker >= 0xD0 && marker <= 0xD7) {
        i += 2;
        continue;
      }
      if (i + 3 >= bytes.length) {
        break;
      }
      final int len = (bytes[i + 2] << 8) | bytes[i + 3];
      if (len < 2) {
        break;
      }
      final bool sof =
          marker == 0xC0 || marker == 0xC1 || marker == 0xC2 || marker == 0xC3;
      if (sof && i + 8 < bytes.length) {
        final int height = (bytes[i + 5] << 8) | bytes[i + 6];
        final int width = (bytes[i + 7] << 8) | bytes[i + 8];
        if (width > 0 && height > 0) {
          return ImageSize(width, height);
        }
      }
      i += 2 + len;
    }
    return null;
  }

  /// Scales `srcWidthPx`×`srcHeightPx` into [maxCx]×[maxCy] EMUs (contain).
  static ({int cx, int cy}) containEmu({
    required int srcWidthPx,
    required int srcHeightPx,
    required int maxCx,
    required int maxCy,
  }) {
    if (srcWidthPx <= 0 || srcHeightPx <= 0 || maxCx <= 0 || maxCy <= 0) {
      return (cx: math.max(0, maxCx), cy: math.max(0, maxCy));
    }
    final int srcCx = srcWidthPx * emuPerPx;
    final int srcCy = srcHeightPx * emuPerPx;
    final double scale = math.min(maxCx / srcCx, maxCy / srcCy);
    return (
      cx: math.max(1, (srcCx * scale).round()),
      cy: math.max(1, (srcCy * scale).round()),
    );
  }

  /// When only one of [maxWidthPx]/[maxHeightPx] is set, fill the missing side.
  static ({int widthPx, int heightPx}) fitPixels({
    required int srcWidthPx,
    required int srcHeightPx,
    int? maxWidthPx,
    int? maxHeightPx,
    int fallbackWidthPx = 480,
    int fallbackHeightPx = 320,
  }) {
    final int srcW = srcWidthPx > 0 ? srcWidthPx : fallbackWidthPx;
    final int srcH = srcHeightPx > 0 ? srcHeightPx : fallbackHeightPx;
    if (maxWidthPx != null && maxHeightPx != null) {
      final ({int cx, int cy}) boxed = containEmu(
        srcWidthPx: srcW,
        srcHeightPx: srcH,
        maxCx: maxWidthPx * emuPerPx,
        maxCy: maxHeightPx * emuPerPx,
      );
      return (
        widthPx: math.max(1, (boxed.cx / emuPerPx).round()),
        heightPx: math.max(1, (boxed.cy / emuPerPx).round()),
      );
    }
    if (maxWidthPx != null) {
      return (
        widthPx: maxWidthPx,
        heightPx: math.max(1, (srcH * maxWidthPx / srcW).round()),
      );
    }
    if (maxHeightPx != null) {
      return (
        widthPx: math.max(1, (srcW * maxHeightPx / srcH).round()),
        heightPx: maxHeightPx,
      );
    }
    return (widthPx: srcW, heightPx: srcH);
  }

  static int _u32be(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }
}
