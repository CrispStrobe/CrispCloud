// SPDX-License-Identifier: MPL-2.0
part of 'legacy_word_metafile.dart';

class _MetafilePreview {
  const _MetafilePreview(this.svg, this.unsupported);
  final String? svg;
  final List<int> unsupported;
}

class _UnsupportedMetafilePreview implements Exception {
  const _UnsupportedMetafilePreview(this.record);
  final int record;
}

class _MetaPen {
  const _MetaPen(this.color, this.width, {this.none = false});
  final String color;
  final double width;
  final bool none;
}

class _MetaBrush {
  const _MetaBrush(this.color, {this.none = false});
  final String color;
  final bool none;
}

class _MetaFont {
  const _MetaFont(
    this.family,
    this.height,
    this.weight,
    this.charSet, {
    this.topAscent,
  });
  final String family;
  final int height, weight, charSet;
  final int? topAscent;
}

typedef _MetaRect = ({double left, double top, double right, double bottom});

class _MetaState {
  _MetaState(double width, double height)
    : windowWidth = width,
      windowHeight = height,
      viewportWidth = width,
      viewportHeight = height;
  _MetaState.copy(_MetaState other)
    : windowWidth = other.windowWidth,
      windowHeight = other.windowHeight,
      viewportWidth = other.viewportWidth,
      viewportHeight = other.viewportHeight,
      windowX = other.windowX,
      windowY = other.windowY,
      viewportX = other.viewportX,
      viewportY = other.viewportY,
      x = other.x,
      y = other.y,
      mapMode = other.mapMode,
      fillRule = other.fillRule,
      arcClockwise = other.arcClockwise,
      pen = other.pen,
      brush = other.brush,
      font = other.font,
      textAlign = other.textAlign,
      textColor = other.textColor,
      backgroundMode = other.backgroundMode,
      penHandle = other.penHandle,
      brushHandle = other.brushHandle,
      fontHandle = other.fontHandle,
      clipId = other.clipId,
      clipRects = other.clipRects,
      world = other.world;
  double windowWidth, windowHeight, viewportWidth, viewportHeight;
  double windowX = 0, windowY = 0, viewportX = 0, viewportY = 0;
  double x = 0, y = 0;
  int mapMode = 1;
  String fillRule = 'evenodd';
  bool arcClockwise = false;
  _MetaPen pen = const _MetaPen('000000', 1);
  _MetaBrush brush = const _MetaBrush('FFFFFF');
  _MetaFont? font;
  int textAlign = 0, backgroundMode = 2, textColor = 0;
  int? penHandle, brushHandle, fontHandle, clipId;
  List<_MetaRect>? clipRects;
  List<double> world = const [1, 0, 0, 1, 0, 0];
}

/// Restricted replay into generated SVG. Unknown drawing/state records make
/// the whole preview unavailable; they are not silently dropped from an image.
/// Original native data remains a separate preservation capability.
class _MetafileRenderer {
  _MetafileRenderer(this.input, this.scan, this.format, this.bounds, this.limit)
    : state = _MetaState(bounds.width.toDouble(), bounds.height.toDouble());
  final _MetaBytes input;
  final _MetafileScan scan;
  final LegacyWordImageFormat format;
  final LegacyWordVectorBounds bounds;
  final int limit;
  final _body = StringBuffer();
  final _objects = <int, Object>{};
  late final _freeHandles = SplayTreeSet<int>.of(
    Iterable<int>.generate(scan.objects),
  );
  final _stack = <_MetaState>[];
  _MetaState state;
  var _characters = 0, _points = 0, _recordType = 0;
  StringBuffer? _path;
  String? _pathMatrix;
  var _pathOpen = false, _figureOpen = false;
  var _painted = false, _hasAlternateImage = false;
  var _clipCount = 0;
  var _plusHeader = false, _plusEnd = false;

  static const _emfSupported = {
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    17,
    18,
    19,
    20,
    21,
    22,
    24,
    25,
    27,
    29,
    30,
    33,
    34,
    35,
    36,
    37,
    38,
    39,
    40,
    42,
    43,
    44,
    45,
    46,
    47,
    54,
    55,
    57,
    59,
    60,
    61,
    62,
    64,
    67,
    68,
    70,
    75,
    81,
    82,
    84,
    85,
    86,
    87,
    88,
    89,
    90,
    91,
  };
  static const _wmfSupported = {
    0,
    0x001e,
    0x0102,
    0x0103,
    0x0104,
    0x0106,
    0x0127,
    0x012d,
    0x012e,
    0x01f0,
    0x0201,
    0x0209,
    0x020b,
    0x020c,
    0x020d,
    0x020e,
    0x020f,
    0x0211,
    0x0213,
    0x0214,
    0x02fa,
    0x02fb,
    0x02fc,
    0x0324,
    0x0325,
    0x0418,
    0x041b,
    0x0538,
    0x061c,
    0x0817,
    0x081a,
    0x0830,
    0x0a32,
  };

  _MetafilePreview render() {
    final supported = format == LegacyWordImageFormat.emf
        ? _emfSupported
        : _wmfSupported;
    final unsupported = <int>{
      for (final record in scan.records)
        if (!supported.contains(record.type)) record.type,
    };
    if (unsupported.isNotEmpty) {
      return _MetafilePreview(null, unsupported.toList()..sort());
    }
    try {
      _write(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="${bounds.left} ${bounds.top} ${bounds.width} ${bounds.height}" overflow="hidden">',
      );
      for (final record in scan.records) {
        _recordType = record.type;
        final bytes = _MetaBytes(
          Uint8List.sublistView(
            input.bytes,
            record.offset,
            record.offset + record.size,
          ),
        );
        if (format == LegacyWordImageFormat.emf) {
          _emf(record.type, bytes);
        } else {
          _wmf(record.type, bytes);
        }
      }
      if (_pathOpen) throw const _UnsupportedMetafilePreview(59);
      if ((_hasAlternateImage || _plusHeader) && !_painted ||
          _plusHeader && !_plusEnd) {
        throw const _UnsupportedMetafilePreview(70);
      }
      _write('</svg>');
      return _MetafilePreview(_body.toString(), const []);
    } on _UnsupportedMetafilePreview catch (error) {
      return _MetafilePreview(null, [error.record]);
    }
  }

  Never _unsupported() => throw _UnsupportedMetafilePreview(_recordType);
  void _write(String value) {
    if (value.length > limit - _characters) {
      throw const FormatException('Metafile preview exceeds its output limit.');
    }
    _characters += value.length;
    _body.write(value);
  }

  String _n(num value) {
    if (!value.isFinite || value.abs() > 1e12) {
      throw const FormatException('Metafile coordinate exceeds its limit.');
    }
    if (value == 0) return '0';
    return value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _color(int value) {
    if (value > 0xffffff) {
      _unsupported(); // Palette/system colors require context.
    }
    return [value & 255, (value >> 8) & 255, (value >> 16) & 255]
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  List<double> _matrix() {
    final sx = state.mapMode == 1
        ? 1.0
        : state.viewportWidth / state.windowWidth;
    final sy = state.mapMode == 1
        ? 1.0
        : state.viewportHeight / state.windowHeight;
    final w = state.world;
    return [
      sx * w[0],
      sy * w[1],
      sx * w[2],
      sy * w[3],
      sx * (w[4] - state.windowX) + state.viewportX,
      sy * (w[5] - state.windowY) + state.viewportY,
    ];
  }

  void _emit(
    String element,
    String geometry, {
    bool filled = false,
    bool stroked = true,
  }) {
    if (state.clipRects?.isEmpty ?? false) return;
    final pen = state.pen, brush = state.brush;
    final clipId = state.clipId;
    if (clipId != null) _write('<g clip-path="url(#emfClip$clipId)">');
    _write(
      '<$element $geometry transform="matrix(${_matrix().map(_n).join(' ')})" '
      'fill="${filled && !brush.none ? '#${brush.color}' : 'none'}" '
      'fill-rule="${state.fillRule}" stroke="${!stroked || pen.none ? 'none' : '#${pen.color}'}" '
      'stroke-width="${_n(pen.width == 0 ? 1 : pen.width)}" '
      'stroke-linecap="round" stroke-linejoin="round"'
      '${pen.width == 0 ? ' vector-effect="non-scaling-stroke"' : ''}/>',
    );
    if (clipId != null) _write('</g>');
    _painted |= (filled && !brush.none) || (stroked && !pen.none);
  }

  String _matrixString() => _matrix().map(_n).join(' ');

  void _appendPath(String commands) {
    final path = _path!;
    if (commands.length > limit - _characters - path.length) {
      throw const FormatException('Metafile path exceeds its output limit.');
    }
    path.write(commands);
  }

  String _takePath() {
    final path = _path;
    if (path == null || _pathOpen || _pathMatrix != _matrixString()) {
      _unsupported();
    }
    _path = null;
    _pathMatrix = null;
    return path.toString();
  }

  void _replaceClip() {
    final path = _takePath();
    final id = ++_clipCount;
    _write(
      '<defs><clipPath id="emfClip$id"><path d="$path" '
      'clip-rule="${state.fillRule}" transform="matrix(${_matrixString()})"/>'
      '</clipPath></defs>',
    );
    state.clipId = id;
    state.clipRects = null;
  }

  _MetaRect? _intersectRect(_MetaRect a, _MetaRect b) {
    final left = math.max(a.left, b.left), top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right),
        bottom = math.min(a.bottom, b.bottom);
    return right > left && bottom > top
        ? (left: left, top: top, right: right, bottom: bottom)
        : null;
  }

  void _clipRect(_MetaBytes data, {required bool exclude}) {
    final matrix = _matrix();
    final previous = state.clipRects;
    if (data.length < 24 ||
        matrix[1] != 0 ||
        matrix[2] != 0 ||
        (state.clipId != null && previous == null)) {
      _unsupported();
    }
    // The rectangle becomes part of the clip in device space. Later mapping
    // changes only transform drawing commands, not the saved clip.
    final x1 = matrix[0] * data.i32(8) + matrix[4];
    final x2 = matrix[0] * data.i32(16) + matrix[4];
    final y1 = matrix[3] * data.i32(12) + matrix[5];
    final y2 = matrix[3] * data.i32(20) + matrix[5];
    final box = (
      left: math.min(x1, x2),
      top: math.min(y1, y2),
      right: math.max(x1, x2),
      bottom: math.max(y1, y2),
    );
    final current =
        previous ??
        [
          (
            left: bounds.left.toDouble(),
            top: bounds.top.toDouble(),
            right: bounds.right.toDouble(),
            bottom: bounds.bottom.toDouble(),
          ),
        ];
    final next = <_MetaRect>[];
    for (final region in current) {
      final overlap = _intersectRect(region, box);
      if (!exclude) {
        if (overlap != null) next.add(overlap);
      } else if (overlap == null) {
        next.add(region);
      } else {
        // Keep a disjoint rectangle for each strip around the removed area.
        next.addAll([
          if (region.top < overlap.top)
            (
              left: region.left,
              top: region.top,
              right: region.right,
              bottom: overlap.top,
            ),
          if (overlap.bottom < region.bottom)
            (
              left: region.left,
              top: overlap.bottom,
              right: region.right,
              bottom: region.bottom,
            ),
          if (region.left < overlap.left)
            (
              left: region.left,
              top: overlap.top,
              right: overlap.left,
              bottom: overlap.bottom,
            ),
          if (overlap.right < region.right)
            (
              left: overlap.right,
              top: overlap.top,
              right: region.right,
              bottom: overlap.bottom,
            ),
        ]);
      }
      if (next.length > 128) _unsupported();
    }
    state.clipRects = next;
    if (next.isEmpty) {
      state.clipId = null;
      return;
    }
    final id = ++_clipCount;
    _write('<defs><clipPath id="emfClip$id">');
    for (final region in next) {
      _write(
        '<rect x="${_n(region.left)}" y="${_n(region.top)}" '
        'width="${_n(region.right - region.left)}" '
        'height="${_n(region.bottom - region.top)}"/>',
      );
    }
    _write('</clipPath></defs>');
    state.clipId = id;
  }

  void _stretchDibits(_MetaBytes record) {
    // SRCCOPY of a bottom-up, uncompressed RGB bitmap. Preserve the smaller
    // source width used by producers that include an unused padding column.
    record.require(0, 80);
    final info = record.u32(48);
    final infoLength = record.u32(52);
    final bits = record.u32(56);
    final bitsLength = record.u32(60);
    if (info < 80 ||
        infoLength != 40 ||
        bits < info + infoLength ||
        record.u32(64) != 0 ||
        record.u32(68) != 0x00cc0020) {
      _unsupported();
    }
    record.require(info, infoLength);
    record.require(bits, bitsLength);
    final bitmapWidth = record.i32(info + 4);
    final height = record.i32(info + 8);
    final depth = record.u16(info + 14);
    final x = record.i32(32);
    final requestedWidth = record.i32(40);
    final signedDestWidth = record.i32(72);
    final signedDestHeight = record.i32(76);
    if (record.u32(info) != 40 ||
        record.u16(info + 12) != 1 ||
        record.u32(info + 16) != 0 ||
        (depth != 24 && depth != 32) ||
        x < 0 ||
        record.i32(36) != 0 ||
        requestedWidth <= 0 ||
        height <= 0 ||
        record.i32(44) != height ||
        x >= bitmapWidth ||
        x + requestedWidth > bitmapWidth + 3 ||
        bitmapWidth * height > 4 * 1024 * 1024 ||
        signedDestWidth <= 0 ||
        signedDestHeight <= 0) {
      _unsupported();
    }
    // Some exporters put a four-pixel-aligned extent in the record while
    // the DIB header gives the exact visible width.
    final width = math.min(requestedWidth, bitmapWidth - x);
    final bytesPerPixel = depth ~/ 8;
    final stride = (bitmapWidth * bytesPerPixel + 3) & ~3;
    if (stride * height != bitsLength) _unsupported();
    if (state.clipRects?.isEmpty ?? false) return;
    final scan = Uint8List((width * 3 + 1) * height);
    for (var row = 0; row < height; row++) {
      var input = bits + (height - 1 - row) * stride + x * bytesPerPixel;
      var output = row * (width * 3 + 1) + 1;
      for (var column = 0; column < width; column++) {
        scan[output++] = record.bytes[input + 2];
        scan[output++] = record.bytes[input + 1];
        scan[output++] = record.bytes[input];
        input += bytesPerPixel;
      }
    }
    final png = BytesBuilder(copy: false)
      ..add(const [137, 80, 78, 71, 13, 10, 26, 10]);
    void chunk(String kind, List<int> payload) {
      final type = kind.codeUnits;
      png
        ..add((ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List())
        ..add(type)
        ..add(payload)
        ..add(
          (ByteData(4)..setUint32(0, getCrc32(payload, getCrc32(type)))).buffer
              .asUint8List(),
        );
    }

    final header = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, 8)
      ..setUint8(9, 2);
    chunk('IHDR', header.buffer.asUint8List());
    chunk('IDAT', const ZLibEncoder().encode(scan, level: 3));
    chunk('IEND', const []);
    final clip = state.clipId;
    if (clip != null) _write('<g clip-path="url(#emfClip$clip)">');
    if ((png.length + 2) ~/ 3 * 4 > limit - _characters) _unsupported();
    _write(
      '<image x="${record.i32(24)}" y="${record.i32(28)}" '
      'width="$signedDestWidth" height="$signedDestHeight" '
      'preserveAspectRatio="none" transform="matrix(${_matrixString()})" '
      'href="data:image/png;base64,${base64Encode(png.takeBytes())}"/>',
    );
    if (clip != null) _write('</g>');
    _painted = true;
  }

  void _alternateImageComment(_MetaBytes data) {
    // MS-EMF 2.3.3.4.3. Render only the classical fallback drawing, leaving
    // the alternative format bytes (such as PostScript or PDF) opaque.
    final size = data.u32(8);
    if (size < 28 ||
        size > data.length - 12 ||
        data.u32(12) != 0x43494447 ||
        data.u32(16) != 0x40000004) {
      _unsupported();
    }
    final count = data.u32(36);
    if (count == 0 || count > (size - 28) ~/ 16) _unsupported();
    final formatsEnd = 28 + count * 16;
    for (var index = 0; index < count; index++) {
      final entry = 40 + index * 16;
      final length = data.u32(entry + 8);
      final offset = data.u32(entry + 12);
      if (offset % 4 != 0 ||
          offset < formatsEnd ||
          offset > size ||
          length > size - offset) {
        _unsupported();
      }
    }
    _hasAlternateImage = true;
  }

  void _emfComment(_MetaBytes data) {
    final size = data.u32(8);
    if (size < 4 || size > data.length - 12) _unsupported();
    final identifier = data.u32(12);
    if (identifier == 0x43494447) {
      _alternateImageComment(data);
    } else if (identifier == 0x2b464d45) {
      // This dual stream may contain EMF+ state changes, while all its
      // drawing comes from the classical sibling records. A stream with an
      // EMF+ drawing or unrecognized operation needs its own renderer.
      final end = 12 + size;
      if (size < 16) _unsupported();
      for (var pos = 16; pos < end;) {
        if (end - pos < 12 || _plusEnd) _unsupported();
        final type = data.u16(pos);
        final flags = data.u16(pos + 2);
        final length = data.u32(pos + 4);
        final expected = switch (type) {
          0x4001 => 16, // Header
          0x4002 || 0x4004 || 0x401e || 0x4021 || 0x4022 || 0x4024 => 0,
          0x402a => 24, // SetWorldTransform
          0x4030 => 4, // SetPageTransform
          _ => -1,
        };
        if (expected < 0 ||
            length != 12 + expected ||
            length > end - pos ||
            data.u32(pos + 8) != expected) {
          _unsupported();
        }
        if (type == 0x4001) {
          if (_plusHeader || flags != 1) _unsupported();
          _plusHeader = true;
        } else {
          if (!_plusHeader) _unsupported();
          if (type == 0x4002) _plusEnd = true;
        }
        pos += length;
      }
    } else if (identifier != 0x5247534d || !_plusHeader || _plusEnd) {
      _unsupported();
    }
    // MSGR is opaque private data. The validated dual stream above and the
    // drawing records supply the classical preview without reading it.
  }

  void _move(double x, double y, {bool draw = false}) {
    if (_pathOpen) {
      if (draw && !_figureOpen) {
        _appendPath('M${_n(state.x)} ${_n(state.y)}');
      }
      _appendPath('${draw ? 'L' : 'M'}${_n(x)} ${_n(y)}');
      _figureOpen = true;
    } else if (draw) {
      _emit('path', 'd="M${_n(state.x)} ${_n(state.y)}L${_n(x)} ${_n(y)}"');
    }
    state.x = x;
    state.y = y;
  }

  void _box(
    double left,
    double top,
    double right,
    double bottom, {
    bool ellipse = false,
    double? cornerWidth,
    double? cornerHeight,
  }) {
    if (right < left || bottom < top) return; // Empty GDI rectangle.
    if (ellipse) {
      _emit(
        'ellipse',
        'cx="${_n((left + right) / 2)}" cy="${_n((top + bottom) / 2)}" rx="${_n((right - left) / 2)}" ry="${_n((bottom - top) / 2)}"',
        filled: true,
      );
    } else {
      _emit(
        'rect',
        'x="${_n(left)}" y="${_n(top)}" width="${_n(right - left)}" height="${_n(bottom - top)}"'
            '${cornerWidth == null ? '' : ' rx="${_n(cornerWidth.abs() / 2)}" ry="${_n(cornerHeight!.abs() / 2)}"'}',
        filled: true,
      );
    }
  }

  void _poly(
    List<(double, double)> points, {
    bool closed = false,
    bool bezier = false,
    bool to = false,
  }) {
    if (points.isEmpty) return;
    final path = StringBuffer();
    var index = 0;
    if (to) {
      if (!_pathOpen || !_figureOpen) {
        path.write('M${_n(state.x)} ${_n(state.y)}');
      }
    } else {
      path.write('M${_n(points.first.$1)} ${_n(points.first.$2)}');
      index = 1;
    }
    if (bezier) {
      // MS-EMF explicitly ignores any incomplete trailing control-point group.
      while (index + 2 < points.length) {
        path.write('C');
        for (var end = index + 3; index < end; index++) {
          path.write('${_n(points[index].$1)} ${_n(points[index].$2)} ');
        }
      }
    } else {
      for (; index < points.length; index++) {
        path.write('L${_n(points[index].$1)} ${_n(points[index].$2)}');
      }
    }
    if (closed) path.write('Z');
    if (_pathOpen) {
      _appendPath(path.toString());
      _figureOpen = !closed;
    } else {
      _emit('path', 'd="$path"', filled: closed);
    }
    if (to && index > 0) {
      state.x = points[index - 1].$1;
      state.y = points[index - 1].$2;
    }
  }

  void _arc(
    double left,
    double top,
    double right,
    double bottom,
    double radialStartX,
    double radialStartY,
    double radialEndX,
    double radialEndY, {
    bool chord = false,
    bool pie = false,
    bool to = false,
  }) {
    // GDI's inputs describe radial lines, not points on the ellipse. Project
    // them onto the logical ellipse before applying the current DC transform.
    // Degenerate or reversed boxes are not asserted as a visible shape.
    if (right <= left || bottom <= top) _unsupported();
    final cx = (left + right) / 2, cy = (top + bottom) / 2;
    final rx = (right - left) / 2, ry = (bottom - top) / 2;
    final dx1 = (radialStartX - cx) / rx;
    final dy1 = (radialStartY - cy) / ry;
    final dx2 = (radialEndX - cx) / rx;
    final dy2 = (radialEndY - cy) / ry;
    // A radial whose endpoint is the center has no defined direction. Do not
    // guess a start point and offer a complete but misleading preview.
    if ((dx1 == 0 && dy1 == 0) || (dx2 == 0 && dy2 == 0)) {
      _unsupported();
    }
    final length1 = math.sqrt(dx1 * dx1 + dy1 * dy1);
    final length2 = math.sqrt(dx2 * dx2 + dy2 * dy2);
    final x1 = cx + rx * dx1 / length1;
    final y1 = cy + ry * dy1 / length1;
    final x2 = cx + rx * dx2 / length2;
    final y2 = cy + ry * dy2 / length2;
    final start = math.atan2(dy1, dx1), end = math.atan2(dy2, dx2);
    final sweep = state.arcClockwise ? 1 : 0;
    final angle =
        (state.arcClockwise ? end - start : start - end) % (2 * math.pi);
    final full = angle == 0;
    // Equal-angle, unequal radial inputs and coincident pie radials have
    // producer-dependent zero/full-sweep and radial-outline behavior. Keep
    // their original native image but do not guess a complete SVG.
    if (full &&
        (pie || radialStartX != radialEndX || radialStartY != radialEndY)) {
      _unsupported();
    }
    final path = StringBuffer();
    if (to) path.write('M${_n(state.x)} ${_n(state.y)}L');
    if (!to) path.write('M');
    path.write('${_n(x1)} ${_n(y1)}');
    void segment(double x, double y, int large) =>
        path.write('A${_n(rx)} ${_n(ry)} 0 $large $sweep ${_n(x)} ${_n(y)}');
    if (full) {
      // An SVG arc with identical endpoints draws nothing. Two half-ellipse
      // segments retain the full-ellipse GDI case without flattening curves.
      segment(2 * cx - x1, 2 * cy - y1, 0);
      segment(x1, y1, 0);
    } else {
      segment(x2, y2, angle > math.pi ? 1 : 0);
    }
    if (pie && !full) path.write('L${_n(cx)} ${_n(cy)}');
    if (pie || chord) path.write('Z');
    _emit('path', 'd="$path"', filled: pie || chord);
    if (to) {
      state.x = x2;
      state.y = y2;
    }
  }

  List<(double, double)> _readPoints(
    _MetaBytes data,
    int start,
    int count,
    int width,
  ) {
    if (count > 100000 - _points ||
        count > (data.length - start) ~/ (width * 2)) {
      throw const FormatException(
        'Metafile points exceed their extent or limit.',
      );
    }
    data.require(start, count * width * 2);
    _points += count;
    return [
      for (var i = 0; i < count; i++)
        (
          (width == 2 ? data.i16(start + i * 4) : data.i32(start + i * 8))
              .toDouble(),
          (width == 2
                  ? data.i16(start + i * 4 + 2)
                  : data.i32(start + i * 8 + 4))
              .toDouble(),
        ),
    ];
  }

  void _multiPoly(
    _MetaBytes data, {
    required int countOffset,
    required int countsOffset,
    required int countWidth,
    required int pointWidth,
    required bool closed,
    int? declaredPoints,
  }) {
    final count = countWidth == 2
        ? data.u16(countOffset)
        : data.u32(countOffset);
    if (count > 16384 || count > (data.length - countsOffset) ~/ countWidth) {
      throw const FormatException(
        'Metafile polygon counts exceed their extent or limit.',
      );
    }
    data.require(countsOffset, count * countWidth);
    final counts = <int>[];
    var total = 0;
    for (var i = 0; i < count; i++) {
      final size = countWidth == 2
          ? data.u16(countsOffset + i * countWidth)
          : data.u32(countsOffset + i * countWidth);
      // GDI PolyPolygon and PolyPolyline both require at least two points
      // in each figure; these operations neither use nor change the current
      // drawing position.
      if (size < 2 || size > 100000 - _points - total) {
        throw const FormatException('Invalid or oversized metafile polygon.');
      }
      counts.add(size);
      total += size;
    }
    if (declaredPoints != null && total != declaredPoints) {
      throw const FormatException('Inconsistent metafile polygon point count.');
    }
    final start = countsOffset + count * countWidth;
    data.require(start, total * pointWidth * 2);
    // The 32-bit EMF records specify device-dependent point limits. Avoid
    // asserting a complete SVG when their total exceeds the largest limit.
    if (countWidth == 4 && pointWidth == 4 && total > 16384) _unsupported();
    final points = _readPoints(data, start, total, pointWidth);
    final path = StringBuffer();
    var cursor = 0;
    for (final size in counts) {
      for (var i = 0; i < size; i++, cursor++) {
        final point = points[cursor];
        path.write('${i == 0 ? 'M' : 'L'}${_n(point.$1)} ${_n(point.$2)}');
      }
      if (closed) path.write('Z');
    }
    if (counts.isNotEmpty) {
      // One compound path is essential: alternate/winding fill applies to
      // all figures together, including holes and overlapping polygons.
      if (_pathOpen) {
        _appendPath(path.toString());
        _figureOpen = !closed;
      } else {
        _emit('path', 'd="$path"', filled: closed);
      }
    }
  }

  void _mapMode(int value) {
    if (value != 1 && value != 8) _unsupported();
    state.mapMode = value;
  }

  void _extent(double x, double y, {required bool viewport}) {
    // GDI ignores extent changes in fixed-scale MM_TEXT.
    if (state.mapMode == 1) return;
    if (x == 0 || y == 0) {
      throw const FormatException('Zero metafile mapping extent.');
    }
    if (viewport) {
      state.viewportWidth = x;
      state.viewportHeight = y;
    } else {
      state.windowWidth = x;
      state.windowHeight = y;
    }
  }

  void _origin(
    double x,
    double y, {
    required bool viewport,
    bool relative = false,
  }) {
    if (viewport) {
      state.viewportX = x + (relative ? state.viewportX : 0);
      state.viewportY = y + (relative ? state.viewportY : 0);
    } else {
      state.windowX = x + (relative ? state.windowX : 0);
      state.windowY = y + (relative ? state.windowY : 0);
    }
  }

  void _save() {
    if (_stack.length >= 64) {
      throw const FormatException('Metafile state stack exceeds its limit.');
    }
    _stack.add(_MetaState.copy(state));
  }

  void _restore(int value) {
    final index = value < 0 ? _stack.length + value : value - 1;
    if (value == 0 || index < 0 || index >= _stack.length) {
      throw const FormatException('Invalid metafile restored state.');
    }
    state = _stack[index];
    _stack.removeRange(index, _stack.length);
  }

  void _object(int id, Object value) {
    final first = format == LegacyWordImageFormat.emf ? 1 : 0;
    if (id < first || id >= scan.objects || _objects.containsKey(id)) {
      throw const FormatException('Invalid or reused metafile object handle.');
    }
    _objects[id] = value;
    if (format == LegacyWordImageFormat.wmf) _freeHandles.remove(id);
  }

  int _freeObject() {
    if (_freeHandles.isEmpty) {
      throw const FormatException('Metafile object table is full.');
    }
    return _freeHandles.first;
  }

  void _select(int id, {bool stock = false}) {
    if (stock && id == 13) {
      // SYSTEM_FONT is used to deselect an explicit logical font. Its
      // device-dependent contents are unavailable to the SVG renderer.
      state.font = null;
      state.fontHandle = null;
      return;
    }
    final Object? object;
    if (stock) {
      object = switch (id) {
        0 => const _MetaBrush('FFFFFF'),
        4 => const _MetaBrush('000000'),
        5 => const _MetaBrush('000000', none: true),
        6 => const _MetaPen('FFFFFF', 1),
        7 => const _MetaPen('000000', 1),
        8 => const _MetaPen('000000', 1, none: true),
        _ => null,
      };
      if (object == null) _unsupported();
    } else {
      object = _objects[id];
      if (object == null) {
        throw const FormatException('Missing metafile object handle.');
      }
    }
    if (object is _MetaPen) {
      state.pen = object;
      state.penHandle = stock ? null : id;
    }
    if (object is _MetaBrush) {
      state.brush = object;
      state.brushHandle = stock ? null : id;
    }
    if (object is _MetaFont) {
      state.font = object;
      state.fontHandle = id;
    }
  }

  void _delete(int id) {
    if (state.penHandle == id ||
        state.brushHandle == id ||
        state.fontHandle == id ||
        _stack.any(
          (saved) =>
              saved.penHandle == id ||
              saved.brushHandle == id ||
              saved.fontHandle == id,
        )) {
      throw const FormatException('Cannot delete a selected metafile object.');
    }
    if (_objects.remove(id) == null) {
      throw const FormatException('Missing deleted metafile object.');
    }
    if (format == LegacyWordImageFormat.wmf) _freeHandles.add(id);
  }

  _MetaPen _pen(int style, int width, int color) {
    if (style != 0 && style != 5) _unsupported();
    if (width < 0 || width > 1000000) {
      throw const FormatException('Metafile pen exceeds its width limit.');
    }
    return _MetaPen(_color(color), width.toDouble(), none: style == 5);
  }

  _MetaBrush _brush(int style, int color) {
    if (style != 0 && style != 1) _unsupported();
    return _MetaBrush(_color(color), none: style == 1);
  }

  void _fillRule(int value) {
    if (value != 1 && value != 2) {
      throw const FormatException('Invalid metafile fill mode.');
    }
    state.fillRule = value == 1 ? 'evenodd' : 'nonzero';
  }

  List<double> _world(_MetaBytes data, int start) =>
      [for (var i = 0; i < 6; i++) data.f32(start + i * 4)].map((value) {
        if (!value.isFinite || value.abs() > 1e6) {
          throw const FormatException('Invalid metafile affine transform.');
        }
        return value;
      }).toList();
  List<double> _multiply(List<double> a, List<double> b) => [
    a[0] * b[0] + a[2] * b[1],
    a[1] * b[0] + a[3] * b[1],
    a[0] * b[2] + a[2] * b[3],
    a[1] * b[2] + a[3] * b[3],
    a[0] * b[4] + a[2] * b[5] + a[4],
    a[1] * b[4] + a[3] * b[5] + a[5],
  ];

  void _emf(int type, _MetaBytes data) {
    if (_pathOpen &&
        !const {
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          14,
          27,
          54,
          60,
          61,
          68,
          85,
          86,
          87,
          88,
          89,
          90,
          91,
        }.contains(type)) {
      _unsupported();
    }
    switch (type) {
      case 1:
      case 14:
        return;
      case 9:
      case 11:
        _extent(
          data.i32(8).toDouble(),
          data.i32(12).toDouble(),
          viewport: type == 11,
        );
      case 10:
      case 12:
        _origin(
          data.i32(8).toDouble(),
          data.i32(12).toDouble(),
          viewport: type == 12,
        );
      case 13:
        data.require(8, 8); // Only solid and null brushes are supported.
      case 17:
        _mapMode(data.i32(8));
      case 18:
        final mode = data.u32(8);
        if (!const {1, 2}.contains(mode)) _unsupported();
        state.backgroundMode = mode;
      case 19:
        _fillRule(data.u32(8));
      case 20:
        if (data.u32(8) != 13) _unsupported();
      case 21:
        data.require(8, 4);
      case 22:
        state.textAlign = data.u32(8);
      case 24:
        state.textColor = data.u32(8);
      case 25:
        data.require(8, 4); // No text background fills or dashed pens.
      case 27:
      case 54:
        _move(
          data.i32(8).toDouble(),
          data.i32(12).toDouble(),
          draw: type == 54,
        );
      case 29:
      case 30:
        _clipRect(data, exclude: type == 29);
      case 33:
        _save();
      case 34:
        _restore(data.i32(8));
      case 35:
        state.world = _world(data, 8);
      case 36:
        final mode = data.u32(32);
        if (mode == 1) {
          state.world = const [1, 0, 0, 1, 0, 0];
        } else if (mode == 2) {
          state.world = _multiply(_world(data, 8), state.world);
        } else if (mode == 3) {
          state.world = _multiply(state.world, _world(data, 8));
        } else if (mode == 4) {
          state.world = _world(data, 8);
        } else {
          _unsupported();
        }
      case 37:
        final value = data.u32(8);
        _select(value & 0x7fffffff, stock: (value & 0x80000000) != 0);
      case 38:
        _object(data.u32(8), _pen(data.u32(12), data.i32(16), data.u32(24)));
      case 39:
        data.require(8, 16);
        _object(data.u32(8), _brush(data.u32(12), data.u32(16)));
      case 40:
        _delete(data.u32(8));
      case 42:
      case 43:
      case 44:
        _box(
          data.i32(8).toDouble(),
          data.i32(12).toDouble(),
          data.i32(16).toDouble(),
          data.i32(20).toDouble(),
          ellipse: type == 42,
          cornerWidth: type == 44 ? data.i32(24).toDouble() : null,
          cornerHeight: type == 44 ? data.i32(28).toDouble() : null,
        );
      case 45:
      case 46:
      case 47:
      case 55:
        _arc(
          data.i32(8).toDouble(),
          data.i32(12).toDouble(),
          data.i32(16).toDouble(),
          data.i32(20).toDouble(),
          data.i32(24).toDouble(),
          data.i32(28).toDouble(),
          data.i32(32).toDouble(),
          data.i32(36).toDouble(),
          chord: type == 46,
          pie: type == 47,
          to: type == 55,
        );
      case 57:
        final direction = data.u32(8);
        if (direction != 1 && direction != 2) {
          throw const FormatException('Invalid metafile arc direction.');
        }
        state.arcClockwise = direction == 2;
      case 59:
        _pathOpen = true;
        _figureOpen = false;
        _pathMatrix = _matrixString();
        _path = StringBuffer();
      case 60:
        if (!_pathOpen) _unsupported();
        _pathOpen = false;
      case 61:
        if (!_pathOpen || !_figureOpen) _unsupported();
        _appendPath('Z');
        _figureOpen = false;
      case 62:
      case 64:
        data.require(8, 16);
        final path = _takePath();
        if (path.isNotEmpty) {
          _emit('path', 'd="$path"', filled: type != 64, stroked: type != 62);
        }
      case 67:
        if (data.u32(8) != 5) _unsupported();
        _replaceClip();
      case 68:
        _path = null;
        _pathOpen = false;
        _pathMatrix = null;
      case 70:
        _emfComment(data);
      case 75:
        if (data.u32(8) != 0 || data.u32(12) != 5) _unsupported();
        state.clipId = null;
        state.clipRects = null;
      case 81:
        _stretchDibits(data);
      case 82:
        _emfFont(data);
      case 84:
        _emfText(data);
      case 2:
      case 3:
      case 4:
      case 5:
      case 6:
      case 85:
      case 86:
      case 87:
      case 88:
      case 89:
        final base = type >= 85 ? type - 83 : type;
        _poly(
          _readPoints(data, 28, data.u32(24), type >= 85 ? 2 : 4),
          closed: base == 3,
          bezier: base == 2 || base == 5,
          to: base == 5 || base == 6,
        );
      case 7:
      case 8:
      case 90:
      case 91:
        _multiPoly(
          data,
          countOffset: 24,
          countsOffset: 32,
          countWidth: 4,
          pointWidth: type >= 90 ? 2 : 4,
          closed: type == 8 || type == 91,
          declaredPoints: data.u32(28),
        );
      default:
        _unsupported();
    }
  }

  void _emfFont(_MetaBytes data) {
    const nameStart = 40, nameEnd = 104;
    data.require(0, nameEnd);
    final fontName = <int>[];
    for (var offset = nameStart; offset < nameEnd; offset += 2) {
      final code = data.u16(offset);
      if (code == 0) break;
      fontName.add(code);
    }
    final name = String.fromCharCodes(fontName);
    final height = -data.i32(12);
    final weight = data.i32(28);
    final charSet = data.u8(35);
    final supported =
        fontName.length < 32 &&
        RegExp(r'^[A-Za-z0-9 ._-]+$').hasMatch(name) &&
        height > 0 &&
        height <= 1000000 &&
        weight >= 0 &&
        weight <= 900 &&
        weight % 100 == 0 &&
        data.i32(16) == 0 &&
        data.i32(20) == 0 &&
        data.i32(24) == 0 &&
        data.u8(32) == 0 &&
        data.u8(33) == 0 &&
        data.u8(34) == 0 &&
        (charSet == 0 || charSet == 1);
    // Match the Windows ascent for the chart fonts known to this renderer.
    // SVG text uses a baseline and the vector renderer cannot query a GDI DC.
    final topAscent = switch (name.toLowerCase()) {
      'arial' => (height * 1854 / 2048).round(),
      'calibri' => (height * 1950 / 2048).round(),
      _ => null,
    };
    _object(
      data.u32(8),
      _MetaFont(
        name,
        supported ? height : 0,
        weight,
        charSet,
        topAscent: topAscent,
      ),
    );
  }

  void _emfText(_MetaBytes data) {
    if (data.length < 76) _unsupported();
    final font = state.font;
    final count = data.u32(44);
    final stringStart = data.u32(48), advanceStart = data.u32(72);
    // Transparent, unrotated TA_LEFT text positioned by authored advances.
    final ascent = switch (state.textAlign) {
      0 => font?.topAscent,
      24 => 0,
      _ => null,
    };
    if (font == null ||
        font.height == 0 ||
        ascent == null ||
        state.backgroundMode != 1 ||
        data.u32(52) != 0 ||
        !const {1, 2}.contains(data.u32(24)) ||
        count > 4096) {
      _unsupported();
    }
    if (count == 0) return;
    if (stringStart < 76 ||
        stringStart.isOdd ||
        advanceStart < 76 ||
        advanceStart % 4 != 0 ||
        (stringStart < advanceStart + 4 * count &&
            advanceStart < stringStart + 2 * count)) {
      _unsupported();
    }
    data.require(stringStart, count * 2);
    data.require(advanceStart, count * 4);
    if (state.clipRects?.isEmpty ?? false) return;
    final clip = state.clipId;
    if (clip != null) _write('<g clip-path="url(#emfClip$clip)">');
    final color = _color(
      state.textColor >> 24 == 2 ? state.textColor & 0xffffff : state.textColor,
    );
    _write(
      '<g transform="matrix(${_matrixString()})" '
      'font-family="${font.family}" font-size="${font.height}" '
      'font-weight="${font.weight == 0 ? 400 : font.weight}" fill="#$color">',
    );
    var x = data.i32(36);
    final y = data.i32(40) + ascent;
    for (var index = 0; index < count; index++) {
      final code = data.u16(stringStart + index * 2);
      // These are independently positionable Latin characters. Other
      // scripts and surrogate pairs require shaping across code units.
      if (!(code >= 32 && code <= 126 || code >= 160 && code <= 0x024f)) {
        _unsupported();
      }
      if (code != 32 && code != 160) {
        final glyph = const HtmlEscape().convert(String.fromCharCode(code));
        _write('<text x="$x" y="$y">$glyph</text>');
        _painted = true;
      }
      x += data.i32(advanceStart + index * 4);
    }
    _write('</g>');
    if (clip != null) _write('</g>');
  }

  void _wmfFont(_MetaBytes data) {
    data.require(6, 18);
    final nameStart = 24;
    final nameLimit = math.min(data.length, nameStart + 32);
    var end = nameStart;
    while (end < nameLimit && data.bytes[end] != 0) {
      end++;
    }
    final name = String.fromCharCodes(data.bytes, nameStart, end);
    final height = -data.i16(6);
    final weight = data.i16(14);
    final charSet = data.u8(19);
    final supported =
        end < nameLimit &&
        RegExp(r'^[A-Za-z0-9 ._-]+$').hasMatch(name) &&
        height > 0 &&
        weight >= 0 &&
        weight <= 900 &&
        weight % 100 == 0 &&
        data.i16(8) == 0 &&
        data.i16(10) == 0 &&
        data.i16(12) == 0 &&
        data.u8(16) == 0 &&
        data.u8(17) == 0 &&
        data.u8(18) == 0 &&
        (charSet == 0 || charSet == 238);
    _object(
      _freeObject(),
      _MetaFont(name, supported ? height : 0, weight, charSet),
    );
  }

  void _wmfText(_MetaBytes data) {
    final font = state.font;
    final count = data.i16(10), flags = data.u16(12);
    // TA_LEFT | TA_BASELINE | TA_NOUPDATECP, with an explicit clip rectangle.
    if (font == null ||
        font.height == 0 ||
        state.textAlign != 24 ||
        state.backgroundMode != 1 ||
        flags != 4 ||
        count < 0 ||
        count > 4096) {
      _unsupported();
    }
    const textStart = 22;
    final advanceStart = textStart + ((count + 1) & ~1);
    if (data.length != advanceStart + count * 2) _unsupported();
    final left = data.i16(14), top = data.i16(16);
    final width = data.i16(18) - left, height = data.i16(20) - top;
    if (width <= 0 || height <= 0 || count == 0) return;
    final id = ++_clipCount;
    // PALETTERGB carries RGB channels directly when played into true color.
    final color = _color(
      state.textColor >> 24 == 2 ? state.textColor & 0xffffff : state.textColor,
    );
    _write(
      '<g transform="matrix(${_matrixString()})">'
      '<defs><clipPath id="wmfTextClip$id">'
      '<rect x="$left" y="$top" width="$width" height="$height"/>'
      '</clipPath></defs><g clip-path="url(#wmfTextClip$id)" '
      'font-family="${font.family}" font-size="${font.height}" '
      'font-weight="${font.weight == 0 ? 400 : font.weight}" fill="#$color">',
    );
    var x = data.i16(8);
    final y = data.i16(6);
    for (var index = 0; index < count; index++) {
      final byte = data.u8(textStart + index);
      // The printable Latin-1 letters in CP1252 can be represented directly.
      // Reject ambiguous C1 and Central European bytes until their tables
      // are available, rather than substituting different letters.
      if (byte < 32 ||
          (byte >= 127 && byte < 160) ||
          (font.charSet == 238 && byte >= 127)) {
        _unsupported();
      }
      if (byte != 32) {
        final glyph = const HtmlEscape().convert(String.fromCharCode(byte));
        _write('<text x="$x" y="$y">$glyph</text>');
      }
      x += data.i16(advanceStart + index * 2);
    }
    _write('</g></g>');
    _painted = true;
  }

  void _wmf(int type, _MetaBytes data) {
    switch (type) {
      case 0:
        return;
      case 0x001e:
        _save();
      case 0x0127:
        _restore(data.i16(6));
      case 0x0102:
        final mode = data.u16(6);
        if (!const {1, 2}.contains(mode)) _unsupported();
        state.backgroundMode = mode;
      case 0x0103:
        _mapMode(data.i16(6));
      case 0x0104:
        if (data.u16(6) != 13) _unsupported();
      case 0x0106:
        _fillRule(data.u16(6));
      case 0x0201:
        data.require(6, 4);
      case 0x0209:
        state.textColor = data.u32(6);
      case 0x020b:
      case 0x020d:
      case 0x020f:
      case 0x0211:
        _origin(
          data.i16(8).toDouble(),
          data.i16(6).toDouble(),
          viewport: type == 0x020d || type == 0x0211,
          relative: type == 0x020f || type == 0x0211,
        );
      case 0x020c:
      case 0x020e:
        _extent(
          data.i16(8).toDouble(),
          data.i16(6).toDouble(),
          viewport: type == 0x020e,
        );
      case 0x0213:
      case 0x0214:
        _move(
          data.i16(8).toDouble(),
          data.i16(6).toDouble(),
          draw: type == 0x0213,
        );
      case 0x02fa:
        _object(_freeObject(), _pen(data.u16(6), data.i16(8), data.u32(12)));
      case 0x02fc:
        data.require(6, 8);
        _object(_freeObject(), _brush(data.u16(6), data.u32(8)));
      case 0x02fb:
        _wmfFont(data);
      case 0x012d:
        // Unlike EMF, MS-WMF specifies only an object-table index here.
        // Reinterpreting its high bit as a stock-object flag invents a brush
        // or pen that the source never defined.
        _select(data.u16(6));
      case 0x012e:
        state.textAlign = data.u16(6);
      case 0x01f0:
        _delete(data.u16(6));
      case 0x0324:
      case 0x0325:
        _poly(_readPoints(data, 8, data.u16(6), 2), closed: type == 0x0324);
      case 0x0538:
        _multiPoly(
          data,
          countOffset: 6,
          countsOffset: 8,
          countWidth: 2,
          pointWidth: 2,
          closed: true,
        );
      case 0x0418:
      case 0x041b:
      case 0x061c:
        final start = type == 0x061c ? 10 : 6;
        _box(
          data.i16(start + 6).toDouble(),
          data.i16(start + 4).toDouble(),
          data.i16(start + 2).toDouble(),
          data.i16(start).toDouble(),
          ellipse: type == 0x0418,
          cornerWidth: type == 0x061c ? data.i16(8).toDouble() : null,
          cornerHeight: type == 0x061c ? data.i16(6).toDouble() : null,
        );
      case 0x0817:
      case 0x081a:
      case 0x0830:
        _arc(
          data.i16(20).toDouble(),
          data.i16(18).toDouble(),
          data.i16(16).toDouble(),
          data.i16(14).toDouble(),
          data.i16(12).toDouble(),
          data.i16(10).toDouble(),
          data.i16(8).toDouble(),
          data.i16(6).toDouble(),
          chord: type == 0x0830,
          pie: type == 0x081a,
        );
      case 0x0a32:
        _wmfText(data);
      default:
        _unsupported();
    }
  }
}
