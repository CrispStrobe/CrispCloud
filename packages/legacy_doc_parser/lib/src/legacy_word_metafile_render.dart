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
      pen = other.pen,
      brush = other.brush,
      penHandle = other.penHandle,
      brushHandle = other.brushHandle,
      world = other.world;
  double windowWidth, windowHeight, viewportWidth, viewportHeight;
  double windowX = 0, windowY = 0, viewportX = 0, viewportY = 0;
  double x = 0, y = 0;
  int mapMode = 1;
  String fillRule = 'evenodd';
  _MetaPen pen = const _MetaPen('000000', 1);
  _MetaBrush brush = const _MetaBrush('FFFFFF');
  int? penHandle, brushHandle;
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

  static const _emfSupported = {
    1,
    2,
    3,
    4,
    5,
    6,
    9,
    10,
    11,
    12,
    14,
    17,
    18,
    19,
    20,
    24,
    25,
    27,
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
    54,
    85,
    86,
    87,
    88,
    89,
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
    0x02fc,
    0x0324,
    0x0325,
    0x0418,
    0x041b,
    0x061c,
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

  void _emit(String element, String geometry, {bool filled = false}) {
    final pen = state.pen, brush = state.brush;
    _write(
      '<$element $geometry transform="matrix(${_matrix().map(_n).join(' ')})" '
      'fill="${filled && !brush.none ? '#${brush.color}' : 'none'}" '
      'fill-rule="${state.fillRule}" stroke="${pen.none ? 'none' : '#${pen.color}'}" '
      'stroke-width="${_n(pen.width == 0 ? 1 : pen.width)}" '
      'stroke-linecap="round" stroke-linejoin="round"'
      '${pen.width == 0 ? ' vector-effect="non-scaling-stroke"' : ''}/>',
    );
  }

  void _move(double x, double y, {bool draw = false}) {
    if (draw) {
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
      path.write('M${_n(state.x)} ${_n(state.y)}');
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
    _emit('path', 'd="$path"', filled: closed);
    if (to && index > 0) {
      state.x = points[index - 1].$1;
      state.y = points[index - 1].$2;
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
  }

  void _delete(int id) {
    if (state.penHandle == id ||
        state.brushHandle == id ||
        _stack.any(
          (saved) => saved.penHandle == id || saved.brushHandle == id,
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
      case 17:
        _mapMode(data.i32(8));
      case 18:
        if (!const {1, 2}.contains(data.u32(8))) _unsupported();
      case 19:
        _fillRule(data.u32(8));
      case 20:
        if (data.u32(8) != 13) _unsupported();
      case 24:
      case 25:
        data.require(8, 4); // No text or patterned/dashed pens emitted.
      case 27:
      case 54:
        _move(
          data.i32(8).toDouble(),
          data.i32(12).toDouble(),
          draw: type == 54,
        );
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
      default:
        _unsupported();
    }
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
        if (!const {1, 2}.contains(data.u16(6))) _unsupported();
      case 0x0103:
        _mapMode(data.i16(6));
      case 0x0104:
        if (data.u16(6) != 13) _unsupported();
      case 0x0106:
        _fillRule(data.u16(6));
      case 0x0201:
      case 0x0209:
        data.require(6, 4);
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
      case 0x012d:
        final value = data.u16(6);
        _select(value & 0x7fff, stock: (value & 0x8000) != 0);
      case 0x01f0:
        _delete(data.u16(6));
      case 0x0324:
      case 0x0325:
        _poly(_readPoints(data, 8, data.u16(6), 2), closed: type == 0x0324);
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
      default:
        _unsupported();
    }
  }
}
