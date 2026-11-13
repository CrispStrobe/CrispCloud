// SPDX-License-Identifier: MPL-2.0
// ISF packet decoding follows the published format and the .NET Foundation's
// MIT-licensed WPF reference implementation; see doc/ink-decoding.md.

import 'dart:typed_data';

/// A complete bounded semantic decode, or an explicit inert fallback.
/// Unsupported streams never expose a misleading partial stroke collection.
enum LegacyWordInkDecodeStatus { decoded, unsupported, invalid, limitExceeded }

/// Shared work allowance for inspecting multiple ISF payloads.
///
/// A stroke reserves its declared point count before packet decoding allocates
/// coordinates. Failed or unsupported decodes keep their reservations, so
/// repeated unsuccessful payloads cannot bypass the aggregate work limit.
/// Individual streams retain the same hard limits when no budget is supplied.
class LegacyWordInkDecodeBudget {
  LegacyWordInkDecodeBudget({this.maxPoints = 100000, this.maxStrokes = 4096}) {
    RangeError.checkValueInInterval(maxPoints, 0, 100000, 'maxPoints');
    RangeError.checkValueInInterval(maxStrokes, 0, 4096, 'maxStrokes');
  }

  final int maxPoints, maxStrokes;
  var _pointsUsed = 0, _strokesUsed = 0;
  int get pointsUsed => _pointsUsed;
  int get strokesUsed => _strokesUsed;
  int get remainingPoints => maxPoints - _pointsUsed;
  int get remainingStrokes => maxStrokes - _strokesUsed;

  void _reserve(int points) {
    if (remainingStrokes == 0) {
      _inkLimit('ISF aggregate stroke decode limit exceeded');
    }
    if (points > remainingPoints) {
      _inkLimit('ISF aggregate point decode limit exceeded');
    }
    _pointsUsed += points;
    _strokesUsed++;
  }
}

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

/// A source tablet-to-ink transform. Tag 20 has a zero linear matrix in ISF;
/// an ordinary translation instead uses tag 16 with an identity linear matrix.
class LegacyWordInkTransform {
  const LegacyWordInkTransform._(
    this.recordTag,
    this.doublePrecision,
    this.m11,
    this.m12,
    this.m21,
    this.m22,
    this.dx,
    this.dy,
  );
  static const identity = LegacyWordInkTransform._(
    null,
    false,
    1,
    0,
    0,
    1,
    0,
    0,
  );
  final int? recordTag;
  final bool doublePrecision;
  final double m11, m12, m21, m22, dx, dy;
  double x(int x, int y) => x * m11 + y * m21 + dx;
  double y(int x, int y) => x * m12 + y * m22 + dy;
}

/// The preserved logical pressure range. This bounded decoder supports
/// zero-based unitless ranges at unit resolution; other metrics stay inert.
class LegacyWordInkPressureMetric {
  const LegacyWordInkPressureMetric._(
    this.minimum,
    this.maximum,
    this.unit,
    this.resolution,
  );
  static const standard = LegacyWordInkPressureMetric._(0, 1023, 0, 1);
  final int minimum, maximum, unit;
  final double resolution;
}

/// Coordinates and pen dimensions use HIMETRIC (1/100 millimeter), before
/// any OfficeArt placement. A decoded collection does not establish how a
/// containing Word shape positions, clips or associates it with a comment.
class LegacyWordInkPoint {
  const LegacyWordInkPoint(
    this.packetX,
    this.packetY,
    this.normalPressure, {
    this.transform = LegacyWordInkTransform.identity,
    this.pressureMetric = LegacyWordInkPressureMetric.standard,
  });

  /// Original integer packet coordinates, before the source transform.
  final int packetX, packetY;
  final LegacyWordInkTransform transform;
  final LegacyWordInkPressureMetric pressureMetric;
  double get xHimetric => transform.x(packetX, packetY);
  double get yHimetric => transform.y(packetX, packetY);

  /// Null preserves an absent pressure channel. ISF's default factor is 0.5.
  /// Explicit samples retain the selected source pressure metric.
  final int? normalPressure;
  double get pressureFactor =>
      normalPressure == null ? 0.5 : normalPressure! / pressureMetric.maximum;
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
    required this.transform,
    required this.pressureMetric,
  }) : points = List.unmodifiable(points);
  final List<LegacyWordInkPoint> points;
  final String colorRgb;
  final int alpha;
  final double widthHimetric, heightHimetric;
  final bool rectangleTip;
  final int drawingFlags, rasterOperation;
  final LegacyWordInkTransform transform;
  final LegacyWordInkPressureMetric pressureMetric;
  bool get fitToCurve => (drawingFlags & 1) != 0;
  bool get ignorePressure => (drawingFlags & 4) != 0;
  bool get isHighlighter => rasterOperation == 9;
}

/// Decodes the complete supported ISF stream. Original bytes are never changed.
/// This does not activate a native ink object or generate a guessed preview.
/// An optional [budget] also bounds work across multiple payloads, including
/// allocations made before a later malformed or unsupported record is found.
LegacyWordInkDecodeResult decodeLegacyWordInk(
  Uint8List bytes, {
  LegacyWordInkDecodeBudget? budget,
}) {
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
      _InkDecoder(bytes, budget).decode(),
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
    if (!value.isFinite) _invalidInk('Nonfinite ISF real value');
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
  LegacyWordInkStroke stroke(
    List<LegacyWordInkPoint> points,
    LegacyWordInkTransform transform,
    LegacyWordInkPressureMetric pressureMetric,
  ) => LegacyWordInkStroke._(
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
    transform: transform,
    pressureMetric: pressureMetric,
  );
}

class _InkDecoder {
  _InkDecoder(Uint8List bytes, this.budget) : input = _InkReader(bytes);
  final _InkReader input;
  final LegacyWordInkDecodeBudget? budget;
  final paints = <_InkPaint>[];
  final descriptors = <bool>[];
  final guids = <String>[];
  final transforms = <LegacyWordInkTransform>[];
  final metrics = <LegacyWordInkPressureMetric>[];
  var paintIndex = 0, descriptorIndex = 0, totalPoints = 0;
  var transformIndex = 0, metricIndex = 0;
  var extendedTransformSeen = false;

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
        case 15:
          if (transforms.isNotEmpty || strokes.isNotEmpty) {
            _unsupportedInk('Repeated or late ISF transform table');
          }
          final block = body.block();
          if (block.done) _invalidInk('Empty ISF transform table');
          while (!block.done) {
            if (transforms.length >= 512) {
              _inkLimit('ISF transform limit exceeded');
            }
            transforms.add(transform(block, block.unsigned(), wide: false));
          }
        case 16:
        case 17:
        case 18:
        case 20:
        case 21:
          if (transforms.isNotEmpty || strokes.isNotEmpty) {
            _unsupportedInk('Repeated or late ISF transform');
          }
          transforms.add(transform(body, tag, wide: false));
        case 23:
          transformIndex = body.unsigned();
          if (transformIndex >= transforms.length) {
            _invalidInk('Invalid ISF transform index');
          }
        case 24:
          if (metrics.isNotEmpty || strokes.isNotEmpty) {
            _unsupportedInk('Repeated or late ISF metric table');
          }
          final block = body.block();
          if (block.done) _invalidInk('Empty ISF metric table');
          while (!block.done) {
            if (metrics.length >= 512) _inkLimit('ISF metric limit exceeded');
            metrics.add(metric(block.block()));
          }
        case 25:
          if (metrics.isNotEmpty || strokes.isNotEmpty) {
            _unsupportedInk('Repeated or late ISF metric block');
          }
          metrics.add(metric(body.block()));
        case 26:
          metricIndex = body.unsigned();
          if (metricIndex >= metrics.length) {
            _invalidInk('Invalid ISF metric index');
          }
        case 31:
          if (transforms.isEmpty) {
            _invalidInk('ISF extended transform has no initial transform');
          }
          if (extendedTransformSeen || strokes.isNotEmpty) {
            _unsupportedInk('Repeated or late ISF extended transform');
          }
          final block = body.block();
          for (var i = 0; i < transforms.length; i++) {
            final precise = transform(block, block.unsigned(), wide: true);
            if (!_sameFloatTransform(transforms[i], precise)) {
              _unsupportedInk('Mismatched ISF extended transform');
            }
            transforms[i] = precise;
          }
          block.complete();
          extendedTransformSeen = true;
        case 10:
          if (strokes.length >= 4096) _inkLimit('ISF stroke limit exceeded');
          final block = body.block();
          final count = block.unsigned();
          if (count == 0) _invalidInk('Empty ISF stroke');
          if (count > 100000 - totalPoints) {
            _inkLimit('ISF point limit exceeded');
          }
          budget?._reserve(count);
          totalPoints += count;
          final xs = _inkPackets(block, count), ys = _inkPackets(block, count);
          final pressure =
              descriptors.isNotEmpty && descriptors[descriptorIndex]
              ? _inkPackets(block, count)
              : null;
          block.complete();
          final selectedTransform = transforms.isEmpty
              ? LegacyWordInkTransform.identity
              : transforms[transformIndex];
          final selectedMetric = metrics.isEmpty
              ? LegacyWordInkPressureMetric.standard
              : metrics[metricIndex];
          if (pressure != null &&
              pressure.any(
                (value) => value < 0 || value > selectedMetric.maximum,
              )) {
            _invalidInk('ISF pressure exceeds its source metric');
          }
          final points = [
            for (var i = 0; i < count; i++)
              LegacyWordInkPoint(
                xs[i],
                ys[i],
                pressure?[i],
                transform: selectedTransform,
                pressureMetric: selectedMetric,
              ),
          ];
          for (final point in points) {
            if (!point.xHimetric.isFinite ||
                !point.yHimetric.isFinite ||
                point.xHimetric.abs() > 9007199254740991 ||
                point.yHimetric.abs() > 9007199254740991) {
              _inkLimit('ISF transformed coordinate limit exceeded');
            }
          }
          final attributes = paints.isEmpty
              ? _InkPaint(width: 53, height: 53, flags: 16)
              : paints[paintIndex];
          strokes.add(
            attributes.stroke(points, selectedTransform, selectedMetric),
          );
        default:
          _unsupportedInk('Unsupported ISF record $tag');
      }
    }
    return strokes;
  }

  LegacyWordInkTransform transform(
    _InkReader reader,
    int tag, {
    required bool wide,
  }) {
    final count = switch (tag) {
      16 => 6,
      17 => 1,
      18 || 20 => 2,
      21 => 4,
      _ => _unsupportedInk('Unsupported ISF transform $tag'),
    };
    final values = [for (var i = 0; i < count; i++) reader.real(wide: wide)];
    if (values.any((value) => value.abs() > 1000000)) {
      _inkLimit('ISF transform coefficient limit exceeded');
    }
    if ((tag == 17 || tag == 18) && values.any((value) => value == 0)) {
      _invalidInk('Zero ISF scale');
    }
    final matrix = switch (tag) {
      16 => values,
      17 => [values[0], 0.0, 0.0, values[0], 0.0, 0.0],
      18 => [values[0], 0.0, 0.0, values[1], 0.0, 0.0],
      20 => [0.0, 0.0, 0.0, 0.0, values[0], values[1]],
      _ => [values[0], 0.0, 0.0, values[1], values[2], values[3]],
    };
    return LegacyWordInkTransform._(
      tag,
      wide,
      matrix[0],
      matrix[1],
      matrix[2],
      matrix[3],
      matrix[4],
      matrix[5],
    );
  }

  bool _sameFloatTransform(
    LegacyWordInkTransform initial,
    LegacyWordInkTransform precise,
  ) {
    if (initial.recordTag != precise.recordTag) return false;
    final rounded = ByteData(4);
    final a = [
      initial.m11,
      initial.m12,
      initial.m21,
      initial.m22,
      initial.dx,
      initial.dy,
    ];
    final b = [
      precise.m11,
      precise.m12,
      precise.m21,
      precise.m22,
      precise.dx,
      precise.dy,
    ];
    for (var i = 0; i < a.length; i++) {
      rounded.setFloat32(0, b[i], Endian.little);
      if (rounded.getFloat32(0, Endian.little) != a[i]) return false;
    }
    return true;
  }

  LegacyWordInkPressureMetric metric(_InkReader block) {
    if (block.done) return LegacyWordInkPressureMetric.standard;
    if (block.unsigned() != 56) {
      _unsupportedInk('Unsupported ISF packet metric');
    }
    final entry = block.block();
    var minimum = 0, maximum = 1023, unit = 0;
    var resolution = 1.0;
    // Every present prefix field takes effect. Omitted trailing fields alone
    // inherit defaults (ISF specification, Metric Block, printed page 14).
    if (!entry.done) minimum = entry.signed();
    if (!entry.done) maximum = entry.signed();
    if (!entry.done) unit = entry.unsigned();
    if (!entry.done) resolution = entry.real(wide: false);
    if (!entry.done || !block.done) {
      _unsupportedInk('Extended or repeated ISF pressure metric');
    }
    if (maximum <= minimum || resolution <= 0) {
      _invalidInk('Invalid ISF pressure metric');
    }
    if (minimum != 0 || unit != 0 || resolution != 1) {
      _unsupportedInk('Unqualified ISF pressure metric');
    }
    return LegacyWordInkPressureMetric._(minimum, maximum, unit, resolution);
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
