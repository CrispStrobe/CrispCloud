import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../cos/pdf_cos.dart';
import '../cos/pdf_open_error.dart';

/// DeviceGray, DeviceRGB, or DeviceCMYK JPEG samples normalized to RGB888.
final class PdfDctImage {
  const PdfDctImage(this.pixels, {required this.isGray});

  final Uint8List pixels;
  final bool isGray;
}

/// Bounded PDF JPEG adapter for device color spaces.
abstract final class PdfDct {
  static const int maxPixels = 16 * 1024 * 1024;
  static const int maxDimension = 8192;
  static const int _maxBytes = 32 * 1024 * 1024;

  static Never _unsupported() =>
      throw const PdfFilterUnsupported('DCTDecode');

  /// Finds the actual end marker of an inline JPEG, including the marker.
  static int? inlineLength(Uint8List data) {
    final bounded = data.length > _maxBytes
        ? Uint8List.sublistView(data, 0, _maxBytes)
        : data;
    try {
      return _read(bounded, prefixOnly: true).consumed;
    } on PdfFilterUnsupported {
      return null;
    }
  }

  static PdfDctImage? decode(
    Uint8List data,
    PdfCosDict dict,
    PdfCosDict parms, {
    required PdfCos? Function(PdfCos?) resolve,
  }) {
    final header = _read(data);
    final width = resolve(dict['Width']);
    final height = resolve(dict['Height']);
    final bits = resolve(dict['BitsPerComponent']);
    final mask = resolve(dict['ImageMask']);
    if (width is! PdfCosInt || width.value != header.width ||
        height is! PdfCosInt || height.value != header.height ||
        (bits != null && (bits is! PdfCosInt || bits.value != 8)) ||
        (mask is PdfCosBool && mask.value)) {
      _unsupported();
    }
    final rawTransform = resolve(parms['ColorTransform']);
    if (rawTransform != null && rawTransform is! PdfCosNull &&
        (rawTransform is! PdfCosInt ||
            (rawTransform.value != 0 && rawTransform.value != 1))) {
      _unsupported();
    }
    final cs = resolve(dict['ColorSpace']);
    final expected = switch (pdfCosName(cs)) {
      'DeviceGray' || 'G' => 1,
      'DeviceRGB' || 'RGB' => 3,
      'DeviceCMYK' || 'CMYK' => 4,
      _ => null,
    };
    if (expected != null && expected != header.components) {
      _unsupported();
    }
    final cmyk = header.components == 4;
    if (expected == null && (cmyk || cs != null)) {
      return null;
    }
    final gray = header.components == 1;
    // An Adobe marker overrides DecodeParms. Adobe uses 2 for YCCK,
    // while PDF ColorTransform uses 1 for the equivalent inverse transform.
    if ((!gray && !cmyk && header.adobe == 2) ||
        (cmyk && header.adobe == 1)) {
      _unsupported();
    }
    final transform = header.adobe ??
        (rawTransform is PdfCosInt ? rawTransform.value : (cmyk ? 0 : 1));
    final decode = resolve(dict['Decode']);
    final ranges = <double>[];
    if (decode != null && decode is! PdfCosNull) {
      if (decode is! PdfCosArray ||
          decode.items.length != header.components * 2) {
        _unsupported();
      }
      for (final item in decode.items) {
        final value = pdfCosNumber(resolve(item));
        if (value == null || !value.isFinite) {
          _unsupported();
        }
        ranges.add(value);
      }
    }
    final normalized = BytesBuilder(copy: false)..add(const [0xff, 0xd8]);
    if (!gray) {
      final adobeTransform = cmyk && transform != 0 ? 2 : transform;
      normalized.add([
        0xff, 0xee, 0, 14, 65, 100, 111, 98, 101, 0,
        100, 0, 0, 0, 0, adobeTransform,
      ]);
    }
    normalized.add(header.body!);
    try {
      if (cmyk) {
        return _decodeCmyk(normalized.takeBytes(), header.width, header.height,
            ycck: transform != 0, ranges: ranges);
      }
      final image = img.decodeJpg(normalized.takeBytes(), maxPixels: maxPixels);
      if (image == null || image.width != header.width ||
          image.height != header.height) {
        _unsupported();
      }
      final pixels = image.getBytes(order: img.ChannelOrder.rgb);
      if (pixels.length != header.width * header.height * 3) {
        _unsupported();
      }
      if (ranges.isNotEmpty) {
        for (var i = 0; i < pixels.length; i++) {
          final pair = gray ? 0 : (i % 3) * 2;
          pixels[i] = (_decodeSample(pixels[i], ranges, pair) * 255).round();
        }
      }
      return PdfDctImage(pixels, isGray: gray);
    } on PdfFilterUnsupported {
      rethrow;
    } catch (_) {
      _unsupported();
    }
  }

  static double _decodeSample(int sample, List<double> ranges, int pair) {
    final t = sample / 255;
    return (ranges[pair] * (1 - t) + ranges[pair + 1] * t).clamp(0.0, 1.0);
  }

  static PdfDctImage _decodeCmyk(
    Uint8List jpeg,
    int width,
    int height, {
    required bool ycck,
    required List<double> ranges,
  }) {
    // The RGB image API discards the original component planes. Keep this
    // dependency on the JPEG reader confined here so Decode can use CMYK.
    // ignore: invalid_use_of_internal_member
    final data = img.JpegData()..maxPixels = maxPixels;
    data.read(jpeg);
    final components = data.components;
    if (components.length != 4) {
      _unsupported();
    }
    final columns = [
      for (final plane in components)
        List.generate(width, (x) => x * plane.hSamples ~/ plane.maxHSamples),
    ];
    final ink = List.generate(
      4,
      (channel) => List.generate(
        256,
        (sample) => ranges.isEmpty
            ? sample / 255
            : _decodeSample(sample, ranges, channel * 2),
      ),
    );
    final pixels = Uint8List(width * height * 3);
    var offset = 0;
    for (var y = 0; y < height; y++) {
      final rows = [
        for (final plane in components)
          plane.lines[y * plane.vSamples ~/ plane.maxVSamples]!,
      ];
      for (var x = 0; x < width; x++) {
        var c = rows[0][columns[0][x]];
        var m = rows[1][columns[1][x]];
        var yInk = rows[2][columns[2][x]];
        final k = rows[3][columns[3][x]];
        if (ycck) {
          final luma = c;
          final cb = m - 128;
          final cr = yInk - 128;
          c = 255 - (luma + 1.402 * cr).round().clamp(0, 255);
          m = 255 - (luma - 0.344136 * cb - 0.714136 * cr).round().clamp(0, 255);
          yInk = 255 - (luma + 1.772 * cb).round().clamp(0, 255);
        }
        final white = (1 - ink[3][k]) * 255;
        pixels[offset++] = ((1 - ink[0][c]) * white).round();
        pixels[offset++] = ((1 - ink[1][m]) * white).round();
        pixels[offset++] = ((1 - ink[2][yInk]) * white).round();
      }
    }
    return PdfDctImage(pixels, isGray: false);
  }

  /// Inspect markers before allocating decoder pixels; strip application
  /// metadata so EXIF orientation cannot override the PDF CTM. Entropy
  /// decoding is delegated to image, not implemented by this marker walker.
  static ({
    int width, int height, int components, int? adobe, Uint8List? body,
    int consumed,
  }) _read(Uint8List data, {bool prefixOnly = false}) {
    if (data.length < 4 || data.length > _maxBytes ||
        data[0] != 0xff || data[1] != 0xd8) {
      _unsupported();
    }
    final body = prefixOnly ? null : BytesBuilder(copy: false);
    var width = 0, height = 0, components = 0, scans = 0, markers = 0;
    int? adobe;
    var p = 2;
    var inScan = false;
    while (p < data.length) {
      if (++markers > 4096) {
        _unsupported();
      }
      if (inScan) {
        final start = p;
        var found = false;
        while (p < data.length) {
          if (data[p++] != 0xff) {
            continue;
          }
          final markerStart = p - 1;
          while (p < data.length && data[p] == 0xff) {
            p++;
          }
          if (p == data.length) {
            _unsupported();
          }
          final marker = data[p];
          if (marker == 0 || (marker >= 0xd0 && marker <= 0xd7)) {
            p++;
            continue;
          }
          body?.add(Uint8List.sublistView(data, start, markerStart));
          p = markerStart;
          found = true;
          break;
        }
        if (!found) {
          _unsupported();
        }
        inScan = false;
      }
      final start = p;
      if (data[p++] != 0xff) {
        _unsupported();
      }
      while (p < data.length && data[p] == 0xff) {
        p++;
      }
      if (p == data.length) {
        _unsupported();
      }
      final marker = data[p++];
      if (marker == 0xd9) {
        if (components == 0 || scans == 0) {
          _unsupported();
        }
        body?.add(const [0xff, 0xd9]);
        return (width: width, height: height, components: components,
            adobe: adobe, body: body?.takeBytes(), consumed: p);
      }
      if (marker == 0 || marker == 1 ||
          (marker >= 0xd0 && marker <= 0xd8) || p + 2 > data.length) {
        _unsupported();
      }
      final length = (data[p] << 8) | data[p + 1];
      final end = p + length;
      if (length < 2 || end > data.length) {
        _unsupported();
      }
      final payload = p + 2;
      final sof = marker >= 0xc0 && marker <= 0xcf &&
          marker != 0xc4 && marker != 0xc8 && marker != 0xcc;
      if (sof) {
        if (components != 0 || scans != 0 ||
            (marker != 0xc0 && marker != 0xc1 && marker != 0xc2) ||
            length < 8 || data[payload] != 8) {
          _unsupported();
        }
        height = (data[payload + 1] << 8) | data[payload + 2];
        width = (data[payload + 3] << 8) | data[payload + 4];
        components = data[payload + 5];
        if (width < 1 || height < 1 ||
            width > maxDimension || height > maxDimension ||
            width * height > maxPixels ||
            (components != 1 && components != 3 && components != 4) ||
            length != 8 + 3 * components) {
          _unsupported();
        }
        var blocks = 0;
        final ids = <int>{};
        for (var i = 0; i < components; i++) {
          final index = payload + 6 + i * 3;
          final sample = data[index + 1];
          final h = sample >> 4, v = sample & 15;
          if (!ids.add(data[index]) || h < 1 || h > 4 ||
              v < 1 || v > 4 || data[index + 2] > 3) {
            _unsupported();
          }
          blocks += h * v;
        }
        if (blocks > 10) {
          _unsupported();
        }
      }
      if (marker == 0xee && length >= 14 &&
          data[payload] == 65 && data[payload + 1] == 100 &&
          data[payload + 2] == 111 && data[payload + 3] == 98 &&
          data[payload + 4] == 101) {
        final transform = data[payload + 11];
        if (transform > 2 || (adobe != null && adobe != transform)) {
          _unsupported();
        }
        adobe = transform;
      }
      if (!(marker >= 0xe0 && marker <= 0xef) && marker != 0xfe) {
        body?.add(Uint8List.sublistView(data, start, end));
      }
      if (marker == 0xda) {
        if (components == 0 || ++scans > 128 || length < 6 ||
            data[payload] < 1 || data[payload] > components ||
            length != 6 + 2 * data[payload]) {
          _unsupported();
        }
        inScan = true;
      }
      p = end;
    }
    _unsupported();
  }
}
