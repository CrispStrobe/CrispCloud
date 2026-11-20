import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import '../../opc/zip/crc32.dart';
import '../../opc/zip/deflate_codec.dart';
import '../../visual/office_visual.dart';

/// Reads only images already embedded in a native Zotero note response.
///
/// One reader owns the resource budget for the whole note. There are no file,
/// network, SVG, or attachment-key resolution paths here. Accepted raster bytes
/// are retained unchanged; dimensions and pixels are validated before they can
/// reach the editor, DOCX writer, or PDF decoder.
final class WordZoteroNoteImageReader {
  static const maxImages = 32;
  static const maxImageBytes = 4 * 1024 * 1024;
  static const maxTotalImageBytes = 4 * 1024 * 1024;
  static const maxDimension = 8192;
  static const maxPixels = 16 * 1024 * 1024;
  static const maxTotalPixels = 32 * 1024 * 1024;
  static const maxPngScanlineBytes = 32 * 1024 * 1024;
  static const maxTotalDecodedBytes = 64 * 1024 * 1024;
  static const maxMetadataBytes = 1024 * 1024;

  var _count = 0;
  var _bytes = 0;
  var _pixels = 0;
  var _decodedBytes = 0;
  var _metadataBytes = 0;

  OfficeVisual read(Map<String, String> attributes) {
    if (++_count > maxImages) {
      throw _limit('The Zotero note contains more than $maxImages images.');
    }
    for (final text in [attributes['alt'], attributes['title']]) {
      if (text == null) continue;
      for (final rune in text.runes) {
        if (rune != 9 &&
            rune != 10 &&
            rune != 13 &&
            !(rune >= 0x20 && rune <= 0xd7ff) &&
            !(rune >= 0xe000 && rune <= 0xfffd) &&
            !(rune >= 0x10000 && rune <= 0x10ffff)) {
          throw _invalid();
        }
      }
    }
    if ((attributes['style'] ?? '').trim().isNotEmpty ||
        (attributes['class'] ?? '')
            .split(RegExp(r'\s+'))
            .any(
              (value) => value.isNotEmpty && value != 'image' && value != 'ink',
            )) {
      throw UnsupportedError(
        'Custom image styling in Zotero notes is not supported. The document was kept unchanged.',
      );
    }
    final source = attributes['src'];
    final bool png;
    final String payload;
    if (source != null && source.startsWith('data:image/png;base64,')) {
      png = true;
      payload = source.substring('data:image/png;base64,'.length);
    } else if (source != null && source.startsWith('data:image/jpeg;base64,')) {
      png = false;
      payload = source.substring('data:image/jpeg;base64,'.length);
    } else {
      throw UnsupportedError(
        'Zotero note images must be embedded PNG or JPEG data. External files, URLs, missing images, and other image formats are not supported. The document was kept unchanged.',
      );
    }
    if (payload.length > ((maxImageBytes + 2) ~/ 3) * 4) {
      throw _limit('A Zotero note image exceeds the 4 MiB image limit.');
    }
    if (payload.isEmpty || payload.length % 4 != 0) {
      throw _invalid();
    }
    final padding = payload.endsWith('==')
        ? 2
        : payload.endsWith('=')
        ? 1
        : 0;
    if (payload.length ~/ 4 * 3 - padding > maxImageBytes) {
      throw _limit('A Zotero note image exceeds the 4 MiB image limit.');
    }
    // A quantified regular expression can overflow the VM regexp stack on a
    // legitimate multi-megabyte raster. Validate in a bounded linear scan.
    var digit = -1;
    for (var i = 0; i < payload.length - padding; i++) {
      digit = _base64Digit(payload.codeUnitAt(i));
      if (digit < 0) throw _invalid();
    }
    if (padding != 0 && digit & ((1 << (padding * 2)) - 1) != 0) {
      throw _invalid();
    }
    final Uint8List bytes;
    try {
      bytes = base64.decode(payload);
    } on FormatException {
      throw _invalid();
    }
    _bytes += bytes.length;
    if (bytes.length > maxImageBytes || _bytes > maxTotalImageBytes) {
      throw _limit('The Zotero note exceeds the 4 MiB total image limit.');
    }

    final size = png ? _pngSize(bytes) : _jpegSize(bytes);
    // Header inspection alone would admit invented images and malformed pixel
    // streams. Decode only after dimensions, scanline expansion, and the whole
    // note's resource budget have been checked.
    try {
      final decoded = png
          ? image.PngDecoder().decode(bytes)
          : image.JpegDecoder().decode(bytes);
      if (decoded == null ||
          decoded.width != size.width ||
          decoded.height != size.height ||
          decoded.numFrames != 1) {
        throw _invalid();
      }
    } on Object {
      throw _invalid();
    }

    final authoredWidth = _dimension(attributes['width']);
    final authoredHeight = _dimension(attributes['height']);
    final widthPx =
        authoredWidth ??
        (authoredHeight == null
            ? size.width.toDouble()
            : authoredHeight * size.width / size.height);
    final heightPx =
        authoredHeight ??
        (authoredWidth == null
            ? size.height.toDouble()
            : authoredWidth * size.height / size.width);
    // HTML image dimensions are CSS pixels (96 dpi); native extents are points.
    final width = widthPx * 0.75;
    final height = heightPx * 0.75;
    if (!width.isFinite ||
        !height.isFinite ||
        width < 1 ||
        height < 1 ||
        width > 4000 ||
        height > 4000) {
      throw UnsupportedError(
        'Zotero note images must have displayed dimensions between 1 and 4000 points. Resize the image in Zotero and try again. The document was kept unchanged.',
      );
    }
    return OfficeVisual(
      kind: OfficeVisualKind.picture,
      title: attributes['title'] ?? '',
      imageBytes: bytes,
      width: width,
      height: height,
      picture: PictureAdjust(
        altTitle: attributes['title'] ?? '',
        altDescription: attributes['alt'] ?? '',
      ),
    );
  }

  static double? _dimension(String? value) {
    if (value == null) return null;
    // The annotation exporter rounds these values, but the ordinary Zotero
    // note editor stores aspect-ratio-derived dimensions as decimal numbers.
    // Bound the lexical form before parsing; units, signs, and non-finite CSS
    // values are not part of that native image contract.
    final parsed =
        value.length <= 32 &&
            RegExp(r'^(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$').hasMatch(value)
        ? double.tryParse(value)
        : null;
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      throw const FormatException(
        'A Zotero note image has invalid width or height. The document was kept unchanged.',
      );
    }
    return parsed;
  }

  static int _base64Digit(int code) => switch (code) {
    >= 65 && <= 90 => code - 65,
    >= 97 && <= 122 => code - 71,
    >= 48 && <= 57 => code + 4,
    43 => 62,
    47 => 63,
    _ => -1,
  };

  void _reserve(int width, int height, int expandedBytes) {
    if (width < 1 ||
        height < 1 ||
        width > maxDimension ||
        height > maxDimension ||
        width * height > maxPixels) {
      throw _limit('A Zotero note image exceeds the raster dimension limit.');
    }
    _pixels += width * height;
    _decodedBytes += expandedBytes;
    if (_pixels > maxTotalPixels || _decodedBytes > maxTotalDecodedBytes) {
      throw _limit('The Zotero note exceeds the decoded image limit.');
    }
  }

  ({int width, int height}) _pngSize(Uint8List bytes) {
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 45) throw _invalid();
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) throw _invalid();
    }
    var offset = 8;
    var chunks = 0;
    var width = 0;
    var height = 0;
    var depth = 0;
    var color = -1;
    var paletteEntries = 0;
    var hasTransparency = false;
    var hasData = false;
    var dataEnded = false;
    var ended = false;
    var expectedBytes = 0;
    var rows = <({int bytes, int count})>[];
    final compressed = BytesBuilder(copy: false);
    while (offset + 12 <= bytes.length) {
      if (++chunks > 4096) throw _limit('A Zotero PNG has too many chunks.');
      final length = _u32(bytes, offset);
      final end = offset + 12 + length;
      if (end > bytes.length) throw _invalid();
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      if (!RegExp(r'^[A-Za-z]{2}[A-Z][A-Za-z]$').hasMatch(type) ||
          Crc32.compute(Uint8List.sublistView(bytes, offset + 4, end - 4)) !=
              _u32(bytes, end - 4)) {
        throw _invalid();
      }
      final data = Uint8List.sublistView(bytes, offset + 8, end - 4);
      if (chunks == 1 && type != 'IHDR') throw _invalid();
      if (hasData && type != 'IDAT') dataEnded = true;
      switch (type) {
        case 'IHDR':
          if (chunks != 1 || length != 13) throw _invalid();
          width = _u32(data, 0);
          height = _u32(data, 4);
          depth = data[8];
          color = data[9];
          final validDepths = switch (color) {
            0 => const <int>[1, 2, 4, 8, 16],
            2 || 4 || 6 => const <int>[8, 16],
            3 => const <int>[1, 2, 4, 8],
            _ => const <int>[],
          };
          if (!validDepths.contains(depth) ||
              data[10] != 0 ||
              data[11] != 0 ||
              data[12] > 1) {
            throw _invalid();
          }
          final channels = switch (color) {
            2 => 3,
            4 => 2,
            6 => 4,
            _ => 1,
          };
          rows = _pngRows(width, height, channels * depth, data[12] == 1);
          expectedBytes = rows.fold(
            0,
            (sum, row) => sum + row.bytes * row.count,
          );
          if (expectedBytes > maxPngScanlineBytes) {
            throw _limit('A Zotero PNG exceeds the 32 MiB scanline limit.');
          }
          _reserve(width, height, expectedBytes);
        case 'PLTE':
          if (hasData ||
              paletteEntries != 0 ||
              color == 0 ||
              color == 4 ||
              length == 0 ||
              length % 3 != 0 ||
              length > 768) {
            throw _invalid();
          }
          paletteEntries = length ~/ 3;
          if (color == 3 && paletteEntries > 1 << depth) throw _invalid();
        case 'tRNS':
          if (hasData || hasTransparency) throw _invalid();
          hasTransparency = true;
          if (!(color == 0 && length == 2) &&
              !(color == 2 && length == 6) &&
              !(color == 3 && length > 0 && length <= paletteEntries)) {
            throw _invalid();
          }
        case 'IDAT':
          if (dataEnded || (color == 3 && paletteEntries == 0)) {
            throw _invalid();
          }
          hasData = true;
          compressed.add(data);
        case 'IEND':
          if (!hasData || length != 0 || end != bytes.length) throw _invalid();
          ended = true;
        case 'acTL':
        case 'fcTL':
        case 'fdAT':
          throw UnsupportedError(
            'Animated PNG images in Zotero notes are not supported. The document was kept unchanged.',
          );
        default:
          // An unknown critical chunk changes how pixels are interpreted.
          if (type.codeUnitAt(0) >= 65 && type.codeUnitAt(0) <= 90) {
            throw _invalid();
          }
          _pngMetadata(type, data);
      }
      offset = end;
      if (ended) break;
    }
    if (!ended || offset != bytes.length) throw _invalid();
    final raster = _inflate(compressed.takeBytes(), expectedBytes);
    if (raster.length != expectedBytes) throw _invalid();
    offset = 0;
    for (final row in rows) {
      for (var i = 0; i < row.count; i++) {
        if (raster[offset] > 4) throw _invalid();
        offset += row.bytes;
      }
    }
    return (width: width, height: height);
  }

  static List<({int bytes, int count})> _pngRows(
    int width,
    int height,
    int bitsPerPixel,
    bool interlaced,
  ) {
    if (!interlaced) {
      return [(bytes: 1 + ((width * bitsPerPixel + 7) ~/ 8), count: height)];
    }
    const passes = <(int, int, int, int)>[
      (0, 0, 8, 8),
      (4, 0, 8, 8),
      (0, 4, 4, 8),
      (2, 0, 4, 4),
      (0, 2, 2, 4),
      (1, 0, 2, 2),
      (0, 1, 1, 2),
    ];
    return [
      for (final (x, y, stepX, stepY) in passes)
        if (width > x && height > y)
          (
            bytes:
                1 +
                ((((width - x + stepX - 1) ~/ stepX) * bitsPerPixel + 7) ~/ 8),
            count: (height - y + stepY - 1) ~/ stepY,
          ),
    ];
  }

  void _pngMetadata(String type, Uint8List data) {
    int? compressedAt;
    if (type == 'zTXt' || type == 'iCCP') {
      final zero = data.indexOf(0);
      if (zero < 1 ||
          zero > 79 ||
          zero + 2 >= data.length ||
          data[zero + 1] != 0) {
        throw _invalid();
      }
      compressedAt = zero + 2;
    } else if (type == 'iTXt') {
      final zero = data.indexOf(0);
      if (zero < 1 ||
          zero > 79 ||
          zero + 3 >= data.length ||
          data[zero + 1] > 1 ||
          data[zero + 2] != 0) {
        throw _invalid();
      }
      final languageEnd = data.indexOf(0, zero + 3);
      if (languageEnd < 0) throw _invalid();
      final translatedEnd = data.indexOf(0, languageEnd + 1);
      if (translatedEnd < 0) throw _invalid();
      if (data[zero + 1] == 1) compressedAt = translatedEnd + 1;
    }
    if (compressedAt != null) {
      final expanded = _inflate(
        Uint8List.sublistView(data, compressedAt),
        maxMetadataBytes - _metadataBytes,
      );
      _metadataBytes += expanded.length;
    }
  }

  static Uint8List _inflate(Uint8List data, int limit) {
    if (data.length < 6 ||
        data[0] & 15 != 8 ||
        data[0] >> 4 > 7 ||
        ((data[0] << 8) + data[1]) % 31 != 0 ||
        data[1] & 32 != 0) {
      throw _invalid();
    }
    final Uint8List result;
    try {
      result = RawDeflate.inflate(
        Uint8List.sublistView(data, 2, data.length - 4),
        maxOutputBytes: limit,
      );
    } on ZipDeflateException {
      throw _invalid();
    }
    var a = 1;
    var b = 0;
    for (final value in result) {
      a = (a + value) % 65521;
      b = (b + a) % 65521;
    }
    if (((b << 16) | a) != _u32(data, data.length - 4)) throw _invalid();
    return result;
  }

  ({int width, int height}) _jpegSize(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 255 || bytes[1] != 216) {
      throw _invalid();
    }
    var offset = 2;
    var markers = 0;
    var scans = 0;
    var width = 0;
    var height = 0;
    var ended = false;
    while (offset < bytes.length) {
      if (++markers > 4096 || bytes[offset++] != 255) throw _invalid();
      while (offset < bytes.length && bytes[offset] == 255) {
        offset++;
      }
      if (offset == bytes.length) throw _invalid();
      final marker = bytes[offset++];
      if (marker == 217) {
        ended = true;
        break;
      }
      if (marker == 0 ||
          marker == 216 ||
          marker == 1 ||
          (marker >= 208 && marker <= 215) ||
          offset + 2 > bytes.length) {
        throw _invalid();
      }
      final length = _u16(bytes, offset);
      if (length < 2 || offset + length > bytes.length) throw _invalid();
      final data = Uint8List.sublistView(bytes, offset + 2, offset + length);
      if (marker >= 192 &&
          marker <= 207 &&
          marker != 196 &&
          marker != 200 &&
          marker != 204) {
        if ((marker != 192 && marker != 193 && marker != 194) ||
            width != 0 ||
            data.length < 6 ||
            data[0] != 8) {
          throw _invalid();
        }
        // Quds' current PDF JPEG writer embeds DeviceRGB data. Other component
        // layouts need a separate color-space implementation before acceptance.
        if (data[5] != 3) {
          throw UnsupportedError(
            'Zotero JPEG images must use three-component RGB or YCbCr color. Use a PNG for grayscale or CMYK images. The document was kept unchanged.',
          );
        }
        if (data.length != 6 + 3 * data[5]) throw _invalid();
        final components = <int>{};
        for (var i = 6; i < data.length; i += 3) {
          final horizontal = data[i + 1] >> 4;
          final vertical = data[i + 1] & 15;
          if (!components.add(data[i]) ||
              horizontal < 1 ||
              horizontal > 4 ||
              vertical < 1 ||
              vertical > 4 ||
              data[i + 2] > 3) {
            throw _invalid();
          }
        }
        height = _u16(data, 1);
        width = _u16(data, 3);
        _reserve(width, height, width * height * 4);
      } else if (marker == 225) {
        _jpegOrientation(data);
      }
      offset += length;
      if (marker == 218) {
        if (width == 0 || ++scans > 100 || data.length < 6) throw _invalid();
        // Scan over entropy bytes, respecting stuffed FF and restart markers.
        // This discovers every later SOF/SOS before any decoder allocates data.
        while (offset < bytes.length) {
          if (bytes[offset] != 255) {
            offset++;
            continue;
          }
          final start = offset++;
          while (offset < bytes.length && bytes[offset] == 255) {
            offset++;
          }
          if (offset == bytes.length) throw _invalid();
          final next = bytes[offset];
          if (next == 0 || (next >= 208 && next <= 215)) {
            offset++;
          } else {
            offset = start;
            break;
          }
        }
      }
    }
    if (!ended || offset != bytes.length || width == 0 || scans == 0) {
      throw _invalid();
    }
    return (width: width, height: height);
  }

  static void _jpegOrientation(Uint8List data) {
    const signature = <int>[69, 120, 105, 102, 0, 0];
    if (data.length < signature.length) return;
    for (var i = 0; i < signature.length; i++) {
      if (data[i] != signature[i]) return;
    }
    if (data.length < 14) throw _invalid();
    final tiff = ByteData.sublistView(data, 6);
    final Endian endian;
    if (tiff.getUint16(0) == 0x4949) {
      endian = Endian.little;
    } else if (tiff.getUint16(0) == 0x4d4d) {
      endian = Endian.big;
    } else {
      throw _invalid();
    }
    if (tiff.getUint16(2, endian) != 42) throw _invalid();
    final start = tiff.getUint32(4, endian);
    if (start == 0) return;
    if (start < 8 || start + 2 > tiff.lengthInBytes) throw _invalid();
    final count = tiff.getUint16(start, endian);
    if (count > 4096 || start + 2 + 12 * count + 4 > tiff.lengthInBytes) {
      throw _invalid();
    }
    var seen = false;
    for (var i = 0; i < count; i++) {
      final entry = start + 2 + 12 * i;
      if (tiff.getUint16(entry, endian) != 0x112) continue;
      if (seen ||
          tiff.getUint16(entry + 2, endian) != 3 ||
          tiff.getUint32(entry + 4, endian) != 1) {
        throw _invalid();
      }
      seen = true;
      if (tiff.getUint16(entry + 8, endian) != 1) {
        throw UnsupportedError(
          'Rotated or flipped EXIF JPEG images in Zotero notes are not supported. Export an upright PNG or JPEG and try again. The document was kept unchanged.',
        );
      }
    }
  }

  static int _u16(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes).getUint16(offset);
  static int _u32(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes).getUint32(offset);

  static FormatException _invalid() => const FormatException(
    'A Zotero note image is malformed or does not match its PNG/JPEG format. The document was kept unchanged.',
  );
  static FormatException _limit(String message) =>
      FormatException('$message The document was kept unchanged.');
}
