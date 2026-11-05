import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Gallery decoding budgets apply before allocating a full pixel buffer.
const kGalleryMaxPixels = 40 * 1000 * 1000;
const kGalleryInputLimitBytes = 64 * 1024 * 1024;

class GalleryDecodeRequest {
  const GalleryDecodeRequest(this.bytes, {this.fileName = '', this.maxSize});
  final Uint8List bytes;
  final String fileName;
  final int? maxSize;
}

class GalleryDecodedRaster {
  const GalleryDecodedRaster({
    required this.bytes,
    required this.width,
    required this.height,
    required this.frameCount,
  });
  final Uint8List bytes;
  final int width;
  final int height;
  final int frameCount;
}

/// Pure Dart fallback for TIFF, PSD, TGA, PNM, ICO and other formats unsupported
/// by the platform codec. Called with compute on native platforms, never with
/// dart:ui resources (those belong to the root isolate).
GalleryDecodedRaster? decodeGalleryRaster(GalleryDecodeRequest request) {
  if (request.bytes.length > kGalleryInputLimitBytes) return null;
  final previousLimit = img.Decoder.defaultMaxPixels;
  img.Decoder.defaultMaxPixels = kGalleryMaxPixels;
  try {
    final decoder = img.findDecoderForNamedImage(request.fileName) ??
        img.findDecoderForData(request.bytes);
    if (decoder == null) return null;
    final info = decoder.startDecode(request.bytes);
    if (info == null ||
        info.width < 1 ||
        info.height < 1 ||
        info.width * info.height > kGalleryMaxPixels) {
      return null;
    }
    // Never decode every page/frame of a TIFF or animation just for a tile.
    final decoded = decoder.decodeFrame(0);
    if (decoded == null) return null;
    var image = img.bakeOrientation(decoded);
    final originalWidth = image.width;
    final originalHeight = image.height;
    final maxSize = request.maxSize;
    if (maxSize != null && math.max(image.width, image.height) > maxSize) {
      final scale = maxSize / math.max(image.width, image.height);
      image = img.copyResize(
        image,
        width: math.max(1, (image.width * scale).round()),
        height: math.max(1, (image.height * scale).round()),
        interpolation: img.Interpolation.average,
      );
    }
    // Strip source metadata from a generated cache image. It is inspected
    // separately from the original, and must not turn thumbnails into copies
    // of a private EXIF block or embedded full-resolution preview.
    image.exif.clear();
    return GalleryDecodedRaster(
      bytes: img.encodePng(image, singleFrame: true),
      width: originalWidth,
      height: originalHeight,
      frameCount: info.numFrames,
    );
  } catch (_) {
    return null;
  } finally {
    img.Decoder.defaultMaxPixels = previousLimit;
  }
}

/// Reads a bounded metadata block without decoding pixels. A corrupt EXIF
/// directory is optional metadata, so it must not prevent image browsing.
Map<String, String> readGalleryExif(Uint8List bytes) {
  try {
    final block = _exifBlock(bytes);
    if (block == null || block.length > 1024 * 1024) return const {};
    final exif = img.ExifData.fromInputBuffer(img.InputBuffer(block));
    final result = <String, String>{};
    const tags = <int, String>{
      0x010e: 'Description',
      0x010f: 'Camera make',
      0x0110: 'Camera model',
      0x0112: 'EXIF orientation',
      0x0131: 'Software',
      0x0132: 'EXIF modified',
      0x013b: 'Artist',
      0x8298: 'Copyright',
      0x829a: 'Exposure time',
      0x829d: 'Aperture',
      0x8827: 'ISO',
      0x9003: 'Date taken',
      0x9004: 'Digitized',
      0x9204: 'Exposure bias',
      0x9207: 'Metering mode',
      0x9209: 'Flash',
      0x920a: 'Focal length',
      0xa001: 'Color space',
      0xa405: '35mm focal length',
      0xa434: 'Lens',
    };
    for (final entry in tags.entries) {
      final value = exif.exifIfd[entry.key] ?? exif.imageIfd[entry.key] ??
          exif.getTag(entry.key);
      if (value == null) continue;
      final text = value.toString().replaceAll(RegExp(r'[\x00-\x1f]'), '').trim();
      if (text.isNotEmpty) {
        result[entry.value] = text.length > 512 ? text.substring(0, 512) : text;
      }
    }
    final gps = exif.gpsIfd;
    final latitude = gps[2];
    final longitude = gps[4];
    if (latitude != null && longitude != null &&
        latitude.length >= 3 && longitude.length >= 3) {
      double coordinate(img.IfdValue value) =>
          value.toDouble(0) + value.toDouble(1) / 60 + value.toDouble(2) / 3600;
      var lat = coordinate(latitude);
      var lon = coordinate(longitude);
      if (gps[1]?.toString().startsWith('S') ?? false) lat = -lat;
      if (gps[3]?.toString().startsWith('W') ?? false) lon = -lon;
      if (lat.isFinite && lon.isFinite && lat.abs() <= 90 && lon.abs() <= 180) {
        result['GPS'] = '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';
      }
    }
    return result;
  } catch (_) {
    return const {};
  }
}

Uint8List? _exifBlock(Uint8List bytes) {
  if (bytes.length < 8) return null;
  final data = ByteData.sublistView(bytes);
  Uint8List? block(int start, int end) {
    if (start < 0 || end > bytes.length || end - start < 8 ||
        end - start > 1024 * 1024) return null;
    if (start + 6 <= end &&
        ascii.decode(bytes.sublist(start, start + 6), allowInvalid: true) ==
            'Exif\u0000\u0000') {
      start += 6;
    }
    return Uint8List.sublistView(bytes, start, end);
  }

  // TIFF starts with its EXIF/TIFF header. Large TIFF pixel data is not copied
  // or parsed here; the first MiB is enough for ordinary camera directories.
  if ((bytes[0] == 0x49 && bytes[1] == 0x49) ||
      (bytes[0] == 0x4d && bytes[1] == 0x4d)) {
    return block(0, math.min(bytes.length, 1024 * 1024));
  }
  if (bytes[0] == 0xff && bytes[1] == 0xd8) {
    var offset = 2;
    while (offset + 4 <= bytes.length) {
      if (bytes[offset] != 0xff) break;
      final marker = bytes[offset + 1];
      if (marker == 0xda || marker == 0xd9) break;
      if (marker == 0xff) { offset++; continue; }
      if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd8)) {
        offset += 2;
        continue;
      }
      final length = data.getUint16(offset + 2, Endian.big);
      if (length < 2 || offset + 2 + length > bytes.length) break;
      if (marker == 0xe1 && length >= 8 &&
          ascii.decode(bytes.sublist(offset + 4, offset + 10), allowInvalid: true) ==
              'Exif\u0000\u0000') {
        return block(offset + 4, offset + 2 + length);
      }
      offset += 2 + length;
    }
  }
  // PNG eXIf and WebP EXIF chunks carry the same TIFF directory structure.
  final isPng = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e;
  final isWebp = bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
  if (isPng || isWebp) {
    var offset = isPng ? 8 : 12;
    while (offset + 8 <= bytes.length) {
      final length = data.getUint32(isPng ? offset : offset + 4,
          isPng ? Endian.big : Endian.little);
      final typeOffset = isPng ? offset + 4 : offset;
      final type = ascii.decode(bytes.sublist(typeOffset, typeOffset + 4),
          allowInvalid: true);
      final end = offset + 8 + length;
      if (end > bytes.length) break;
      if (type == (isPng ? 'eXIf' : 'EXIF')) return block(offset + 8, end);
      offset = end + (isPng ? 4 : (length.isOdd ? 1 : 0));
    }
  }
  return null;
}
