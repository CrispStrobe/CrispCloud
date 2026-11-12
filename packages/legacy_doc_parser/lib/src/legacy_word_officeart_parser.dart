// SPDX-License-Identifier: MPL-2.0
part of 'legacy_word_structured_parser.dart';

// MS-ODRAW 2.3.1: Boolean FOPT values have independent use bits. A child
// property changes only explicitly used bits; copying the whole word loses
// inherited, unrelated flags. Complex property bytes remain bounded views.
class _OfficeArtProperties {
  final values = <int, int>{};
  final complex = <int, Uint8List>{};

  void addAll(_OfficeArtProperties other) {
    for (final entry in other.values.entries) {
      final old = values[entry.key];
      var value = entry.value;
      if (old != null &&
          const {0x00bf, 0x017f, 0x01bf, 0x01ff, 0x023f}.contains(entry.key)) {
        final used = value ~/ 65536;
        final inherited = old ~/ 65536;
        value =
            ((used | inherited) & 0xffff) * 65536 +
            ((old & 0xffff & ~used) | (value & used));
      }
      values[entry.key] = value;
      complex.remove(entry.key);
    }
    for (final entry in other.complex.entries) {
      complex[entry.key] = entry.value;
      values.remove(entry.key);
    }
  }
}

class _OfficeArtShapeReader {
  _OfficeArtShapeReader(this.properties, this.type, this.flags);
  final _OfficeArtProperties properties;
  final int type, flags;
  final unsupported = <int>{};
  Map<int, int> get p => properties.values;
  int pointCount = 0;

  LegacyWordOfficeArtShape read() {
    final fill = p.keys.any((id) => id >= 0x0180 && id <= 0x01bf)
        ? LegacyWordOfficeArtFill(
            enabled: _used(0x01bf, 4),
            type: _enum(0x0180, 9),
            color: _color(0x0181),
            opacityFixed16: _opacity(0x0182),
          )
        : null;
    final line = p.keys.any((id) => id >= 0x01c0 && id <= 0x01ff)
        ? LegacyWordOfficeArtLine(
            enabled: _used(0x01ff, 3),
            type: _enum(0x01c4, 4),
            color: _color(0x01c0),
            opacityFixed16: _opacity(0x01c1),
            widthEmu: _nonnegative(0x01cb),
            dash: _enum(0x01ce, 10),
            join: _enum(0x01d6, 2),
            cap: _enum(0x01d7, 2),
          )
        : null;
    final shadow = p.keys.any((id) => id >= 0x0200 && id <= 0x023f)
        ? LegacyWordOfficeArtShadow(
            enabled: _used(0x023f, 1),
            type: _enum(0x0200, 5),
            color: _color(0x0201),
            opacityFixed16: _opacity(0x0204),
            offsetXEmu: p[0x0205]?.toSigned(32),
            offsetYEmu: p[0x0206]?.toSigned(32),
            obscured: _used(0x023f, 0),
          )
        : null;
    final text =
        p.keys.any((id) => (id >= 0x0081 && id <= 0x0089) || id == 0x00bf)
        ? LegacyWordOfficeArtText(
            insetLeftEmu: p[0x0081]?.toSigned(32),
            insetTopEmu: p[0x0082]?.toSigned(32),
            insetRightEmu: p[0x0083]?.toSigned(32),
            insetBottomEmu: p[0x0084]?.toSigned(32),
            wrapMode: _enum(0x0085, 4),
            anchor: _enum(0x0087, 9),
            flow: _enum(0x0088, 5),
            fontDirection: _enum(0x0089, 3),
            fitShapeToText: _used(0x00bf, 1),
            autoTextMargin: _used(0x00bf, 3),
          )
        : null;
    final geometry = _geometry();
    if (fill?.type != null && fill!.type != 0) unsupported.add(0x0180);
    if (line?.type != null && line!.type != 0) unsupported.add(0x01c4);
    if (shadow?.type != null && shadow!.type != 0) unsupported.add(0x0200);
    const mapped = {
      0x0140,
      0x0141,
      0x0142,
      0x0143,
      0x0144,
      0x0145,
      0x0146,
      0x0180,
      0x0181,
      0x0182,
      0x01bf,
      0x01c0,
      0x01c1,
      0x01c4,
      0x01cb,
      0x01ce,
      0x01d6,
      0x01d7,
      0x01ff,
      0x0200,
      0x0201,
      0x0204,
      0x0205,
      0x0206,
      0x023f,
    };
    for (final id in {...p.keys, ...properties.complex.keys}) {
      if (id >= 0x0140 && id <= 0x02ff && !mapped.contains(id)) {
        unsupported.add(id);
      }
    }
    // Fill rectangles, recoloring, and inset/background-line styles alter
    // appearance beyond the direct solid-color subset.
    if (_used(0x01bf, 1) == true || _used(0x01bf, 6) == true) {
      unsupported.add(0x01bf);
    }
    if (_used(0x01ff, 6) == true || _used(0x01ff, 9) == true) {
      unsupported.add(0x01ff);
    }
    return LegacyWordOfficeArtShape(
      type: type,
      rotationFixed16: (p[0x0004] ?? 0).toSigned(32),
      flipHorizontal: (flags & 0x40) != 0,
      flipVertical: (flags & 0x80) != 0,
      geometry: geometry,
      fill: fill,
      line: line,
      shadow: shadow,
      text: text,
      unsupportedProperties: unsupported.toList()..sort(),
    );
  }

  bool? _used(int id, int bit) {
    final value = p[id];
    if (value == null || (value & (1 << (bit + 16))) == 0) return null;
    return (value & (1 << bit)) != 0;
  }

  int? _enum(int id, int maximum) {
    final value = p[id];
    if (value != null && value > maximum) {
      unsupported.add(id);
      return null;
    }
    return value;
  }

  int? _opacity(int id) {
    final value = p[id];
    if (value != null && value > 65536) {
      unsupported.add(id);
      return null;
    }
    return value;
  }

  int? _nonnegative(int id) {
    final value = p[id];
    if (value != null && value > 0x7fffffff) {
      unsupported.add(id);
      return null;
    }
    return value;
  }

  String? _color(int id) {
    final value = p[id];
    if (value == null) return null;
    // Palette indices, system colors and scheme colors need document/application
    // context. Never reinterpret their low bytes as a literal RGB color.
    if (value > 0xffffff) {
      unsupported.add(id);
      return null;
    }
    return [value & 255, (value >> 8) & 255, (value >> 16) & 255]
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  LegacyWordOfficeArtGeometry? _geometry() {
    final bounds = LegacyWordVectorBounds(
      (p[0x0140] ?? 0).toSigned(32),
      (p[0x0141] ?? 0).toSigned(32),
      (p[0x0142] ?? 21600).toSigned(32),
      (p[0x0143] ?? 21600).toSigned(32),
    );
    if (bounds.width <= 0 || bounds.height <= 0) {
      unsupported.addAll([0x0140, 0x0141, 0x0142, 0x0143]);
      return null;
    }
    final vertices = properties.complex[0x0145];
    final segments = properties.complex[0x0146];
    if (vertices == null) {
      if (segments != null || (p[0x0145] ?? 0) != 0 || (p[0x0146] ?? 0) != 0) {
        unsupported.addAll([0x0145, 0x0146]);
        return null;
      }
      // Custom adjustment values require the matching shape's guide program;
      // emitting the unadjusted preset would silently change its geometry.
      if (p.keys.any((id) => id >= 0x0147 && id <= 0x014e)) return null;
      final preset = switch (type) {
        1 || 202 => 'rect',
        2 => 'roundRect',
        3 => 'ellipse',
        20 => 'line',
        _ => null,
      };
      return preset == null
          ? null
          : LegacyWordOfficeArtGeometry(bounds: bounds, preset: preset);
    }
    final array = _array(vertices, 0x0145, 8, 16384);
    if (array == null) return null;
    final points = <LegacyWordOfficeArtPoint>[];
    pointCount = array.$2;
    for (var i = 0; i < array.$2; i++) {
      final x = array.$1.u32(i * 8), y = array.$1.u32(i * 8 + 4);
      if ((x >= 0x80000000 && x <= 0x8000007f) ||
          (y >= 0x80000000 && y <= 0x8000007f)) {
        unsupported.add(0x0145); // Unresolved pGuides reference.
        return null;
      }
      points.add(LegacyWordOfficeArtPoint(x.toSigned(32), y.toSigned(32)));
    }
    if (points.isEmpty) return null;
    final path = <LegacyWordOfficeArtPathCommand>[];
    final segmentArray = segments == null || segments.isEmpty
        ? null
        : _array(segments, 0x0146, 2, 16384);
    if (segments != null && segments.isNotEmpty && segmentArray == null) {
      return null;
    }
    // MS-ODRAW 2.3.6.5: a nonempty pSegmentInfo takes precedence over
    // shapePath, including a source's contradictory simple-path value.
    final mode = segmentArray != null && segmentArray.$2 > 0
        ? 4
        : p[0x0144] ?? 1;
    if (mode > 4) {
      unsupported.add(0x0144);
      return null;
    }
    if (mode != 4) {
      path.add(
        LegacyWordOfficeArtPathCommand(LegacyWordOfficeArtPathKind.move, [
          points.first,
        ]),
      );
      if (mode <= 1) {
        for (final point in points.skip(1)) {
          path.add(
            LegacyWordOfficeArtPathCommand(LegacyWordOfficeArtPathKind.line, [
              point,
            ]),
          );
        }
      } else {
        if ((points.length - 1) % 3 != 0) {
          throw const FormatException('Invalid OfficeArt cubic vertex count.');
        }
        for (var i = 1; i < points.length; i += 3) {
          path.add(
            LegacyWordOfficeArtPathCommand(
              LegacyWordOfficeArtPathKind.cubic,
              points.sublist(i, i + 3),
            ),
          );
        }
      }
      if (mode == 1 || mode == 3) {
        path.add(
          LegacyWordOfficeArtPathCommand(LegacyWordOfficeArtPathKind.close),
        );
      }
    } else {
      if (segmentArray == null || segmentArray.$2 == 0) {
        throw const FormatException('OfficeArt complex path has no segments.');
      }
      final array = segmentArray;
      var cursor = 0, begun = false, ended = false;
      for (var i = 0; i < array.$2; i++) {
        final value = array.$1.u16(i * 2);
        final kind = value >> 13, count = value & 0x1fff;
        if (kind >= 5) {
          unsupported.add(
            0x0146,
          ); // Escape/client-escape semantics are distinct.
          return null;
        }
        if (ended) {
          unsupported.add(
            0x0146,
          ); // Multiple painted paths need distinct fills.
          return null;
        }
        if (kind == 2) {
          if (count != 0 || cursor >= points.length) {
            throw const FormatException('Invalid OfficeArt move segment.');
          }
          path.add(
            LegacyWordOfficeArtPathCommand(LegacyWordOfficeArtPathKind.move, [
              points[cursor++],
            ]),
          );
          begun = true;
        } else if (kind <= 1) {
          final needed = count * (kind == 1 ? 3 : 1);
          if (!begun || needed > points.length - cursor) {
            throw const FormatException('OfficeArt path exceeds its vertices.');
          }
          for (var j = 0; j < count; j++) {
            final length = kind == 1 ? 3 : 1;
            path.add(
              LegacyWordOfficeArtPathCommand(
                kind == 1
                    ? LegacyWordOfficeArtPathKind.cubic
                    : LegacyWordOfficeArtPathKind.line,
                points.sublist(cursor, cursor + length),
              ),
            );
            cursor += length;
          }
        } else if (kind == 3) {
          if (!begun || count != 1) {
            throw const FormatException('Invalid OfficeArt close segment.');
          }
          path.add(
            LegacyWordOfficeArtPathCommand(LegacyWordOfficeArtPathKind.close),
          );
        } else {
          if (count != 0) {
            throw const FormatException('Invalid OfficeArt end segment.');
          }
          ended = true;
        }
      }
      if (!ended || cursor != points.length) {
        throw const FormatException('Incomplete OfficeArt path references.');
      }
    }
    return LegacyWordOfficeArtGeometry(bounds: bounds, path: path);
  }

  (_Bytes, int)? _array(Uint8List bytes, int id, int size, int limit) {
    final input = _Bytes(bytes);
    final count = input.u16(0), allocated = input.u16(2);
    final storedSize = input.u16(4);
    if (allocated < count || count > limit) {
      throw const FormatException('OfficeArt array exceeds its element limit.');
    }
    final actualSize = storedSize == 0xfff0 ? 4 : storedSize;
    if (actualSize == 0 || input.length != 6 + count * actualSize) {
      throw const FormatException('Invalid OfficeArt array extent.');
    }
    if (storedSize != size) {
      unsupported.add(id); // Truncated POINT encoding is retained, not guessed.
      return null;
    }
    return (_Bytes(input.slice(6, input.length - 6)), count);
  }
}
