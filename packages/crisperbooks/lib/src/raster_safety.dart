import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

/// Bound both encoded bytes and decoded pixels before allocating image buffers.
const kImageEditorInputLimitBytes = 32 * 1024 * 1024;
const kImageEditorOutputLimitBytes = 64 * 1024 * 1024;
const kImageEditorMaxPixels = 40 * 1000 * 1000;
const kImageEditorMaxDimension = 16384;

enum ImageFileFormat { png, jpeg }

enum ImageEditFailure {
  unsupportedFormat,
  formatMismatch,
  invalidImage,
  animatedImage,
  inputTooLarge,
  outputTooLarge,
  dimensionsTooLarge,
  staleExport,
  gifColorLimit,
  multiPageImage,
  rasterEncodingLoss,
}

/// Machine-readable failures are translated by the host, never shown verbatim.
class ImageEditException implements Exception {
  const ImageEditException(this.reason);

  final ImageEditFailure reason;

  @override
  String toString() => 'ImageEditException(${reason.name})';
}

class ImageSaveInProgressException implements Exception {
  const ImageSaveInProgressException();

  @override
  String toString() => 'ImageSaveInProgressException';
}

class ImageFileInfo {
  const ImageFileInfo({
    required this.format,
    required this.width,
    required this.height,
  });

  final ImageFileFormat format;
  final int width;
  final int height;
}

ImageFileFormat? imageFileFormatForName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return ImageFileFormat.png;
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return ImageFileFormat.jpeg;
  }
  return null;
}

/// Formats for which the editor can preserve the original container on save.
/// Animated and mismatched inputs are rejected after reading their bytes.
bool isEditableImageFileName(String name) =>
    imageFileFormatForName(name) != null;

/// Formats decoded into a PNG editing surface and restored on save.
bool isTranscodedRasterFileName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.webp') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.tif') ||
      lower.endsWith('.tiff');
}

/// Raster files and CrispCloud editable image projects share the F4 editor.
bool isImageEditorFileName(String name) =>
    isEditableImageFileName(name) ||
    isTranscodedRasterFileName(name) ||
    name.toLowerCase().endsWith('.ccimage');

/// Inspect structure and dimensions without allocating a full pixel buffer.
///
/// A filename alone is not evidence of its encoding. PNG animation chunks and
/// JPEG multi-picture/trailing data are rejected rather than flattening them
/// over the source. PNG CRCs and JPEG marker boundaries are checked before the
/// engine sees the bytes. The renderer still has to decode the compressed
/// pixels; exported bytes are independently decoded before persistence.
ImageFileInfo inspectEditableImage(
  Uint8List bytes, {
  required String fileName,
  int maxBytes = kImageEditorInputLimitBytes,
}) {
  if (bytes.length > maxBytes) {
    throw ImageEditException(
      maxBytes == kImageEditorInputLimitBytes
          ? ImageEditFailure.inputTooLarge
          : ImageEditFailure.outputTooLarge,
    );
  }
  final expected = imageFileFormatForName(fileName);
  if (expected == null) {
    throw const ImageEditException(ImageEditFailure.unsupportedFormat);
  }
  final ImageFileFormat actual;
  if (_startsWith(bytes, const [137, 80, 78, 71, 13, 10, 26, 10])) {
    actual = ImageFileFormat.png;
  } else if (_startsWith(bytes, const [0xff, 0xd8])) {
    actual = ImageFileFormat.jpeg;
  } else {
    throw const ImageEditException(ImageEditFailure.invalidImage);
  }
  if (actual != expected) {
    throw const ImageEditException(ImageEditFailure.formatMismatch);
  }
  return actual == ImageFileFormat.png
      ? _inspectPng(bytes)
      : _inspectJpeg(bytes);
}

ImageFileInfo _inspectPng(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 8;
  var width = 0;
  var height = 0;
  var sawData = false;
  var endedData = false;
  while (offset < bytes.length) {
    if (bytes.length - offset < 12) _invalid();
    final length = data.getUint32(offset);
    if (length > 0x7fffffff || length > bytes.length - offset - 12) {
      _invalid();
    }
    final typeStart = offset + 4;
    final payload = offset + 8;
    final end = payload + length;
    final typeBytes = Uint8List.sublistView(bytes, typeStart, payload);
    if (typeBytes.any(
          (b) => !((b >= 65 && b <= 90) || (b >= 97 && b <= 122)),
        ) ||
        (typeBytes[2] & 0x20) != 0) {
      _invalid();
    }
    final type = String.fromCharCodes(typeBytes);
    if (getCrc32(Uint8List.sublistView(bytes, typeStart, end)) !=
        data.getUint32(end)) {
      _invalid();
    }
    if (offset == 8 && type != 'IHDR') _invalid();
    if (type == 'IHDR') {
      if (offset != 8 || length != 13) _invalid();
      width = data.getUint32(payload);
      height = data.getUint32(payload + 4);
      _assertDimensions(width, height);
      final depth = bytes[payload + 8];
      final color = bytes[payload + 9];
      final depths = switch (color) {
        0 => const [1, 2, 4, 8, 16],
        2 || 4 || 6 => const [8, 16],
        3 => const [1, 2, 4, 8],
        _ => const <int>[],
      };
      if (!depths.contains(depth) ||
          bytes[payload + 10] != 0 ||
          bytes[payload + 11] != 0 ||
          bytes[payload + 12] > 1) {
        _invalid();
      }
    } else if (type == 'acTL' || type == 'fcTL' || type == 'fdAT') {
      // Even a single-frame APNG can carry timing/disposal semantics.
      throw const ImageEditException(ImageEditFailure.animatedImage);
    } else if (type == 'IDAT') {
      if (endedData) _invalid();
      sawData = true;
    } else {
      if (sawData) endedData = true;
      if (type == 'IEND') {
        if (length != 0 || !sawData || end + 4 != bytes.length) _invalid();
        return ImageFileInfo(
          format: ImageFileFormat.png,
          width: width,
          height: height,
        );
      }
      // Unknown critical chunks are not safe to discard on re-encoding.
      if ((typeBytes[0] & 0x20) == 0 && type != 'PLTE') _invalid();
    }
    offset = end + 4;
  }
  _invalid();
}

ImageFileInfo _inspectJpeg(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 2;
  var width = 0;
  var height = 0;
  var sawFrame = false;
  var sawScan = false;
  while (offset < bytes.length) {
    if (bytes[offset++] != 0xff) _invalid();
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) _invalid();
    final marker = bytes[offset++];
    if (marker == 0xd9) {
      // Appended frames/video in MPO and motion photos must not be destroyed.
      if (!sawFrame || !sawScan || offset != bytes.length) _invalid();
      return ImageFileInfo(
        format: ImageFileFormat.jpeg,
        width: width,
        height: height,
      );
    }
    if (marker == 0 || marker == 0xd8 || (marker >= 0xd0 && marker <= 0xd7)) {
      _invalid();
    }
    if (marker == 0x01) continue; // Standalone TEM marker.
    if (bytes.length - offset < 2) _invalid();
    final length = data.getUint16(offset);
    if (length < 2 || length > bytes.length - offset) _invalid();
    final payload = offset + 2;
    final end = offset + length;
    if (marker == 0xe2 &&
        end - payload >= 4 &&
        _startsWith(Uint8List.sublistView(bytes, payload, end), const [
          77,
          80,
          70,
          0,
        ])) {
      throw const ImageEditException(ImageEditFailure.animatedImage);
    }
    if (marker == 0xc0 || marker == 0xc1 || marker == 0xc2) {
      if (sawFrame || length < 8 || bytes[payload] != 8) _invalid();
      height = data.getUint16(payload + 1);
      width = data.getUint16(payload + 3);
      _assertDimensions(width, height);
      final components = bytes[payload + 5];
      if (components == 0 || length != 8 + components * 3) _invalid();
      sawFrame = true;
    }
    offset = end;
    if (marker == 0xda) {
      if (!sawFrame || length < 6) _invalid();
      sawScan = true;
      // Entropy data escapes FF as FF00; restart markers are standalone.
      // Stop at the next non-escaped marker to support progressive scans.
      while (offset < bytes.length) {
        if (bytes[offset] != 0xff) {
          offset++;
          continue;
        }
        final markerStart = offset++;
        while (offset < bytes.length && bytes[offset] == 0xff) {
          offset++;
        }
        if (offset >= bytes.length) _invalid();
        final code = bytes[offset];
        if (code == 0 || (code >= 0xd0 && code <= 0xd7)) {
          offset++;
          continue;
        }
        offset = markerStart;
        break;
      }
    }
  }
  _invalid();
}

void _assertDimensions(int width, int height) {
  if (width <= 0 || height <= 0) _invalid();
  if (width > kImageEditorMaxDimension ||
      height > kImageEditorMaxDimension ||
      width * height > kImageEditorMaxPixels) {
    throw const ImageEditException(ImageEditFailure.dimensionsTooLarge);
  }
}

bool _startsWith(Uint8List bytes, List<int> signature) {
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

Never _invalid() =>
    throw const ImageEditException(ImageEditFailure.invalidImage);
