// Decode picture input before embedding it and preserve its intrinsic ratio.
// Word/PPTX writers currently emit native PNG, JPEG and GIF package parts.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

const officePictureMaxBytes = 32 * 1024 * 1024;
const officePictureMaxPixels = 40 * 1000 * 1000;

class OfficePictureInfo {
  const OfficePictureInfo(this.widthPixels, this.heightPixels);

  final int widthPixels;
  final int heightPixels;

  /// Fit at 96 dpi, reducing large pictures to the available document box.
  /// The current writers use one point as the smallest representable side.
  /// Reject impossible boxes instead of stretching a very thin picture.
  ({double width, double height})? fit({
    required double maxWidth,
    required double maxHeight,
  }) {
    if (widthPixels < 1 ||
        heightPixels < 1 ||
        !maxWidth.isFinite ||
        !maxHeight.isFinite ||
        maxWidth < 1 ||
        maxHeight < 1) {
      return null;
    }
    final limit = math.min(maxWidth / widthPixels, maxHeight / heightPixels);
    final minimum = 1 / math.min(widthPixels, heightPixels);
    if (limit < minimum) return null;
    final scale = math.max(minimum, math.min(72 / 96, limit));
    return (width: widthPixels * scale, height: heightPixels * scale);
  }
}

/// Inspect a supported raster on a worker isolate. Decode the first frame to
/// reject damaged input; sniffing a valid signature alone is insufficient.
/// The caller retains the original bytes, including GIF animation and metadata.
OfficePictureInfo? inspectOfficePicture(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > officePictureMaxBytes) return null;
  try {
    final decoders = <image.Decoder>[
      image.PngDecoder(maxPixels: officePictureMaxPixels),
      image.JpegDecoder(maxPixels: officePictureMaxPixels),
      image.GifDecoder()..maxPixels = officePictureMaxPixels,
    ];
    final decoder = decoders
        .where((candidate) => candidate.isValidFile(bytes))
        .firstOrNull;
    if (decoder == null) return null;
    final info = decoder.startDecode(bytes);
    if (info == null ||
        info.width < 1 ||
        info.height < 1 ||
        info.width * info.height > officePictureMaxPixels) {
      return null;
    }
    final frame = decoder.decodeFrame(0);
    if (frame == null) return null;
    // JPEG decoding applies EXIF rotation; GIF first frames may occupy only a
    // portion of the full canvas, so use the GIF canvas dimensions instead.
    return decoder is image.JpegDecoder
        ? OfficePictureInfo(frame.width, frame.height)
        : OfficePictureInfo(info.width, info.height);
  } catch (_) {
    return null;
  }
}
