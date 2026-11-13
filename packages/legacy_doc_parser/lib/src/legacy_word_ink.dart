// SPDX-License-Identifier: MPL-2.0
// ISF packet decoding follows the published format and the .NET Foundation's
// MIT-licensed WPF reference implementation; see doc/ink-decoding.md.

import 'dart:typed_data';

/// A complete bounded semantic decode, or an explicit inert fallback.
/// Unsupported streams never expose a misleading partial stroke collection.
enum LegacyWordInkDecodeStatus { decoded, unsupported, invalid, limitExceeded }

class LegacyWordInkDecodeResult {
  LegacyWordInkDecodeResult._(
    this.status,
    this.reason,
    List<LegacyWordInkStroke> strokes,
  ) : strokes = List.unmodifiable(strokes);
  final LegacyWordInkDecodeStatus status;
  final String? reason;
  final List<LegacyWordInkStroke> strokes;
  int get pointCount =>
      strokes.fold(0, (count, stroke) => count + stroke.points.length);
}

/// Coordinates and pen dimensions use HIMETRIC (1/100 millimeter), before
/// any OfficeArt placement. A decoded collection does not establish how a
/// containing Word shape positions, clips or associates it with a comment.
class LegacyWordInkPoint {
  const LegacyWordInkPoint(this.xHimetric, this.yHimetric, this.normalPressure);
  final int xHimetric, yHimetric;

  /// Null preserves an absent pressure channel. ISF's default factor is 0.5.
  /// Explicit supported pressure packets use the default 0..1023 metric.
  final int? normalPressure;
  double get pressureFactor =>
      normalPressure == null ? 0.5 : normalPressure! / 1023;
}

class LegacyWordInkStroke {
  LegacyWordInkStroke._({
    required List<LegacyWordInkPoint> points,
    required this.colorRgb,
    required this.alpha,
    required this.widthHimetric,
    required this.heightHimetric,
    required this.rectangleTip,
    required this.drawingFlags,
    required this.rasterOperation,
  }) : points = List.unmodifiable(points);
  final List<LegacyWordInkPoint> points;
  final String colorRgb;
  final int alpha;
  final double widthHimetric, heightHimetric;
  final bool rectangleTip;
  final int drawingFlags, rasterOperation;
  bool get fitToCurve => (drawingFlags & 1) != 0;
  bool get ignorePressure => (drawingFlags & 4) != 0;
  bool get isHighlighter => rasterOperation == 9;
}

/// Decodes the complete supported ISF stream. Original bytes are never changed.
/// This does not activate a native ink object or generate a guessed preview.
LegacyWordInkDecodeResult decodeLegacyWordInk(Uint8List bytes) {
  try {
    if (bytes.length > 16 * 1024 * 1024) {
      throw const _InkFailure(
        LegacyWordInkDecodeStatus.limitExceeded,
        'ISF byte limit exceeded',
      );
    }
    return LegacyWordInkDecodeResult._(
      LegacyWordInkDecodeStatus.decoded,
      null,
      _InkDecoder(bytes).decode(),
    );
  } on _InkFailure catch (error) {
    return LegacyWordInkDecodeResult._(error.status, error.message, const []);
  }
}

class _InkFailure implements Exception {
  const _InkFailure(this.status, this.message);
  final LegacyWordInkDecodeStatus status;
  final String message;
}

Never _invalidInk(String message) =>
    throw _InkFailure(LegacyWordInkDecodeStatus.invalid, message);
Never _unsupportedInk(String message) =>
    throw _InkFailure(LegacyWordInkDecodeStatus.unsupported, message);
Never _inkLimit(String message) =>
    throw _InkFailure(LegacyWordInkDecodeStatus.limitExceeded, message);

class _InkReader {
  _InkReader(this.bytes, [this.position = 0, int? end])
    : end = end ?? bytes.length;
  final Uint8List bytes;
  final int end;
  int position;
  bool get done => position == end;
  int get remaining => end - position;
  int byte() {
    if (position >= end) _invalidInk('Truncated ISF value');
    return bytes[position++];
  }

  int unsigned() {
    var value = 0, multiplier = 1;
    for (var index = 0; index < 5; index++) {
      final next = byte();
      final low = next & 127;
      if (low > (0xffffffff - value) ~/ multiplier) {
        _invalidInk('ISF integer overflow');
      }
      value += low * multiplier;
      if (next < 128) return value;
      multiplier *= 128;
    }
    _invalidInk('Unterminated ISF integer');
  }

  int signed() {
    final value = unsigned();
    return value.isOdd ? -(value ~/ 2) : value ~/ 2;
  }

  _InkReader take(int length) {
    if (length < 0 || length > remaining) {
      _invalidInk('Invalid ISF block extent');
    }
    final child = _InkReader(bytes, position, position + length);
    position += length;
    return child;
  }

  _InkReader block() => take(unsigned());
  double real({required bool wide}) {
    final data = take(wide ? 8 : 4);
    final view = ByteData.sublistView(bytes, data.position, data.end);
    final value = wide
        ? view.getFloat64(0, Endian.little)
        : view.getFloat32(0, Endian.little);
    if (!value.isFinite) _invalidInk('Nonfinite ISF transform');
    return value;
  }

  void complete() {
    if (!done) _invalidInk('Unconsumed ISF block bytes');
  }
}

class _InkBits {
  _InkBits(this.reader) : bit = reader.position * 8;
  final _InkReader reader;
  int bit;
  int read(int count) {
    if (count < 0 || count > 32 || count > reader.end * 8 - bit) {
      _invalidInk('Truncated ISF packet bits');
    }
    var value = 0;
    for (var index = 0; index < count; index++, bit++) {
      value = value * 2 + ((reader.bytes[bit ~/ 8] >> (7 - bit % 8)) & 1);
    }
    return value;
  }

  void finish() {
    // Each independently encoded packet channel starts on a byte boundary.
    reader.position = (bit + 7) ~/ 8;
  }
}

const _inkHuffmanWidths = [
  [0, 1, 2, 4, 6, 8, 12, 16, 24, 32],
  [0, 1, 1, 2, 4, 8, 12, 16, 24, 32],
  [0, 1, 1, 1, 2, 4, 8, 14, 22, 32],
  [0, 2, 2, 3, 5, 8, 12, 16, 24, 32],
  [0, 3, 4, 5, 8, 12, 16, 24, 32],
  [0, 4, 6, 8, 12, 16, 24, 32],
  [0, 6, 8, 12, 16, 24, 32],
  [0, 7, 8, 12, 16, 24, 32],
];

int _inkPower(int bits) {
  var value = 1;
  for (var i = 0; i < bits; i++) {
    value *= 2;
  }
  return value;
}

List<int> _inkPackets(_InkReader input, int count) {
  final algorithm = input.byte();
  final result = <int>[];
  var previous = 0, previousPrevious = 0;
  void append(int value, {required bool delta}) {
    if (delta) value += 2 * previous - previousPrevious;
    if (value < -0x80000000 || value > 0x7fffffff) {
      _invalidInk('ISF packet overflow');
    }
    result.add(value);
    previousPrevious = previous;
    previous = value;
  }

  switch (algorithm & 0xc0) {
    case 0:
      final delta = (algorithm & 0x20) != 0;
      final width = (algorithm & 31) == 0 ? 32 : algorithm & 31;
      if (delta) {
        if (count < 2) _invalidInk('Short delta-delta ISF channel');
        append(input.signed(), delta: true);
        append(input.signed(), delta: true);
      }
      final bits = _InkBits(input);
      final sign = _inkPower(width - 1), modulus = _inkPower(width);
      while (result.length < count) {
        final raw = bits.read(width);
        append(raw >= sign ? raw - modulus : raw, delta: delta);
      }
      bits.finish();
    case 0x80:
      if ((algorithm & 0x20) != 0 ||
          (algorithm & 31) >= _inkHuffmanWidths.length) {
        _unsupportedInk('Custom ISF Huffman table');
      }
      final widths = _inkHuffmanWidths[algorithm & 31];
      final minimums = [0];
      var minimum = 1;
      for (final width in widths.skip(1)) {
        minimums.add(minimum);
        minimum += _inkPower(width - 1);
      }
      final bits = _InkBits(input);
      (int, int) code(bool allowExtra) {
        var prefix = 0;
        while (bits.read(1) != 0) {
          if (++prefix > widths.length) {
            _invalidInk('Invalid ISF Huffman prefix');
          }
        }
        if (prefix == 0) return (0, 0);
        if (prefix == widths.length) {
          if (!allowExtra) _unsupportedInk('Nested ISF Huffman overflow code');
          final (extra, extraExtra) = code(false);
          final (value, valueExtra) = code(false);
          if (extra < 0 || extra > 7 || extraExtra != 0 || valueExtra != 0) {
            _invalidInk('Invalid ISF Huffman overflow value');
          }
          return (value, extra);
        }
        final raw = bits.read(widths[prefix]);
        final value = raw ~/ 2 + minimums[prefix];
        if (value > 0x80000000) _invalidInk('ISF Huffman integer overflow');
        return (raw.isOdd ? -value : value, 0);
      }
      while (result.length < count) {
        final (value, extra) = code(true);
        var delta = value;
        if (extra != 0) {
          delta = (extra ~/ 2) * 4294967296 + (value % 4294967296);
          if (extra.isOdd) delta = -delta;
        }
        append(delta, delta: true);
      }
      bits.finish();
    default:
      _unsupportedInk('Unsupported ISF packet compression');
  }
  return result;
}

class _InkPaint {
  _InkPaint({this.width = 25, this.height = 25, this.flags = 0});
  double width, height;
  int flags, color = 0, alpha = 255, tip = 0, raster = 13;
  LegacyWordInkStroke stroke(List<LegacyWordInkPoint> points) =>
      LegacyWordInkStroke._(
        points: points,
        colorRgb: [color & 255, (color >> 8) & 255, (color >> 16) & 255]
            .map((value) => value.toRadixString(16).padLeft(2, '0'))
            .join()
            .toUpperCase(),
        alpha: alpha,
        widthHimetric: width,
        heightHimetric: height,
        rectangleTip: tip == 1,
        drawingFlags: flags,
        rasterOperation: raster,
      );
}

class _InkDecoder {
  _InkDecoder(Uint8List bytes) : input = _InkReader(bytes);
  final _InkReader input;
  final paints = <_InkPaint>[];
  final descriptors = <bool>[];
  final guids = <String>[];
  var paintIndex = 0, descriptorIndex = 0, totalPoints = 0;
  var transformSeen = false;

  List<LegacyWordInkStroke> decode() {
    if (input.unsigned() != 0) _unsupportedInk('Unsupported ISF version');
    final body = input.block();
    input.complete();
    final strokes = <LegacyWordInkStroke>[];
    var operations = 0;
    while (!body.done) {
      if (++operations > 16384) _inkLimit('ISF record limit exceeded');
      final tag = body.unsigned();
      switch (tag) {
        case 1:
          final block = body.block();
          if (block.remaining % 16 != 0) _invalidInk('Invalid ISF GUID table');
          if (guids.isNotEmpty) _unsupportedInk('Repeated ISF GUID table');
          while (!block.done) {
            if (guids.length >= 512) _inkLimit('ISF GUID limit exceeded');
            final guid = block.take(16);
            guids.add(
              guid.bytes
                  .sublist(guid.position, guid.end)
                  .map((value) => value.toRadixString(16).padLeft(2, '0'))
                  .join(),
            );
          }
        case 2:
          if (paints.isNotEmpty) _unsupportedInk('Repeated ISF paint table');
          final block = body.block();
          if (block.done) _invalidInk('Empty ISF paint table');
          while (!block.done) {
            if (paints.length >= 512) _inkLimit('ISF paint limit exceeded');
            paints.add(paint(block.block()));
          }
        case 3:
          if (paints.isNotEmpty) _unsupportedInk('Repeated ISF paint block');
          paints.add(paint(body.block()));
        case 4:
          if (descriptors.isNotEmpty) {
            _unsupportedInk('Repeated ISF packet descriptor');
          }
          final block = body.block();
          if (block.done) _invalidInk('Empty ISF packet descriptor table');
          while (!block.done) {
            if (descriptors.length >= 512) {
              _inkLimit('ISF descriptor limit exceeded');
            }
            descriptors.add(descriptor(block.block()));
          }
        case 5:
          if (descriptors.isNotEmpty) {
            _unsupportedInk('Repeated ISF packet descriptor');
          }
          final block = body.block();
          if (block.done) _invalidInk('Empty ISF packet descriptor block');
          descriptors.add(descriptor(block));
        case 9:
          paintIndex = body.unsigned();
          if (paintIndex >= paints.length) {
            _invalidInk('Invalid ISF paint index');
          }
        case 13:
          descriptorIndex = body.unsigned();
          if (descriptorIndex >= descriptors.length) {
            _invalidInk('Invalid ISF descriptor index');
          }
        case 17:
          if (transformSeen) _unsupportedInk('Repeated ISF transform');
          if (body.real(wide: false) != 1) {
            _unsupportedInk('Nonidentity ISF transform');
          }
          transformSeen = true;
        case 31:
          if (!transformSeen) {
            _invalidInk('ISF extended transform has no initial transform');
          }
          final block = body.block();
          if (block.unsigned() != 17 || block.real(wide: true) != 1) {
            _unsupportedInk('Nonidentity ISF extended transform');
          }
          block.complete();
        case 10:
          if (strokes.length >= 4096) _inkLimit('ISF stroke limit exceeded');
          final block = body.block();
          final count = block.unsigned();
          if (count == 0) _invalidInk('Empty ISF stroke');
          if (count > 100000 - totalPoints) {
            _inkLimit('ISF point limit exceeded');
          }
          totalPoints += count;
          final xs = _inkPackets(block, count), ys = _inkPackets(block, count);
          final pressure =
              descriptors.isNotEmpty && descriptors[descriptorIndex]
              ? _inkPackets(block, count)
              : null;
          block.complete();
          if (pressure != null &&
              pressure.any((value) => value < 0 || value > 1023)) {
            _invalidInk('ISF pressure exceeds the default metric');
          }
          final points = [
            for (var i = 0; i < count; i++)
              LegacyWordInkPoint(xs[i], ys[i], pressure?[i]),
          ];
          final attributes = paints.isEmpty
              ? _InkPaint(width: 53, height: 53, flags: 16)
              : paints[paintIndex];
          strokes.add(attributes.stroke(points));
        default:
          _unsupportedInk('Unsupported ISF record $tag');
      }
    }
    return strokes;
  }

  bool descriptor(_InkReader block) {
    if (block.done) return false;
    if (block.unsigned() != 56 || !block.done) {
      _unsupportedInk('Unsupported ISF packet descriptor');
    }
    return true;
  }

  _InkPaint paint(_InkReader block) {
    final result = _InkPaint();
    var widthSeen = false, heightSeen = false, operations = 0;
    while (!block.done) {
      if (++operations > 512) _inkLimit('ISF paint property limit exceeded');
      final tag = block.unsigned();
      switch (tag) {
        case 68:
          result.color = block.unsigned();
          if (result.color > 0xffffff) _unsupportedInk('Non-RGB ISF color');
        case 69:
        case 70:
          var value = block.unsigned().toDouble();
          if (!block.done && block.bytes[block.position] == 27) {
            block.byte();
            final mantissa = block.take(block.unsigned() + 1);
            if (mantissa.remaining != 3 || mantissa.byte() != 0) {
              _unsupportedInk('Compressed ISF pen-size mantissa');
            }
            final raw = mantissa.byte() + mantissa.byte() * 256;
            value += (raw >= 32768 ? raw - 65536 : raw) / 1000;
          }
          if (value < 0) _invalidInk('Negative ISF pen dimension');
          if (value > 1000000) _inkLimit('ISF pen dimension limit exceeded');
          if (value == 0) value = 53;
          if (tag == 69) {
            result.width = value;
            widthSeen = true;
          } else {
            result.height = value;
            heightSeen = true;
          }
        case 71:
          result.tip = block.unsigned();
          if (result.tip > 1) _unsupportedInk('Unsupported ISF pen tip');
        case 72:
          result.flags = block.unsigned();
          if ((result.flags & ~0x1f) != 0) {
            _unsupportedInk('Unknown ISF drawing flags');
          }
        case 80:
          final transparency = block.unsigned();
          if (transparency > 255) _invalidInk('Invalid ISF transparency');
          result.alpha = 255 - transparency;
        case 87:
          final raw = block.take(4);
          result.raster = raw.byte();
          if (raw.byte() != 0 || raw.byte() != 0 || raw.byte() != 0) {
            _invalidInk('Invalid ISF raster operation');
          }
          if (result.raster != 13 && result.raster != 9) {
            _unsupportedInk('Unsupported ISF raster operation');
          }
        default:
          if (tag < 100 || tag - 100 >= guids.length) {
            _unsupportedInk('Unknown ISF paint property $tag');
          }
          // WPF's explicit StylusTip extension is a typed Int32 property.
          // PenTip supplies the v1/v2 compatibility decision. Other property
          // types and unknown extensions are not silently dropped.
          if (guids[tag - 100] != '31c7263579ee8849b93e70d92f8907ed') {
            _unsupportedInk('Unsupported ISF extended paint property');
          }
          final property = block.take(block.unsigned() + 1);
          if (property.remaining != 7 ||
              property.byte() != 0 ||
              property.byte() != 3 ||
              property.byte() != 0) {
            _unsupportedInk('Unsupported ISF StylusTip encoding');
          }
          final tip = property.byte();
          if (tip > 1 ||
              property.byte() != 0 ||
              property.byte() != 0 ||
              property.byte() != 0) {
            _unsupportedInk('Unsupported ISF StylusTip value');
          }
      }
    }
    if (result.tip == 0 && widthSeen && !heightSeen) {
      result.height = result.width;
    }
    return result;
  }
}
