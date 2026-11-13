// SPDX-License-Identifier: MPL-2.0
part of 'legacy_word_structured_parser.dart';

// MS-ODRAW 2.3.1: Boolean FOPT values have independent use bits. A child
// property changes only explicitly used bits; copying the whole word loses
// inherited, unrelated flags. Complex property bytes remain bounded views.
class _OfficeArtProperties {
  final values = <int, int>{};
  final complex = <int, Uint8List>{};
  final blipReferences = <int>{};

  void addAll(_OfficeArtProperties other) {
    for (final entry in other.values.entries) {
      final old = values[entry.key];
      var value = entry.value;
      if (old != null &&
          const {
            0x00bf,
            0x017f,
            0x01bf,
            0x01ff,
            0x023f,
            0x03bf,
            0x073f,
          }.contains(entry.key)) {
        final used = value ~/ 65536;
        final inherited = old ~/ 65536;
        value =
            ((used | inherited) & 0xffff) * 65536 +
            ((old & 0xffff & ~used) | (value & used));
      }
      values[entry.key] = value;
      complex.remove(entry.key);
      if (other.blipReferences.contains(entry.key)) {
        blipReferences.add(entry.key);
      } else {
        blipReferences.remove(entry.key);
      }
    }
    for (final entry in other.complex.entries) {
      complex[entry.key] = entry.value;
      values.remove(entry.key);
      blipReferences.remove(entry.key);
    }
  }
}

class _OfficeArtShapeReader {
  _OfficeArtShapeReader(
    this.properties,
    this.type,
    this.flags, {
    this.fillImage,
  });
  final _OfficeArtProperties properties;
  final int type, flags;
  final LegacyWordImageAsset? fillImage;
  final unsupported = <int>{};
  Map<int, int> get p => properties.values;
  int pointCount = 0;
  late final Uint8List? _inkData = _readInkData();
  int get inkByteLength => _inkData?.length ?? 0;

  Uint8List? _readInkData() {
    if (properties.complex.containsKey(0x073f)) {
      throw const FormatException(
        'OfficeArt ink Boolean properties are complex.',
      );
    }
    if ((p[0x0700] ?? 0) != 0) {
      throw const FormatException('Noncomplex OfficeArt ink must be absent.');
    }
    final bytes = properties.complex[0x0700];
    if (bytes == null) return null;
    // MS-ODRAW IMsoInkData: GUID, uint32 cbBlob, then exactly cbBlob ISF bytes.
    // pInkData is an envelope, not a bare ISF stream or an arbitrary freeform.
    const guid = [
      0x34,
      0x1a,
      0x7c,
      0x93,
      0x1d,
      0x15,
      0x10,
      0x46,
      0x9c,
      0xa6,
      0xa8,
      0xcc,
      0x9b,
      0xdb,
      0x5d,
      0x83,
    ];
    if (bytes.length < 20 ||
        bytes.length > LegacyWordOfficeArtInk.maxDataLength + 20) {
      throw const FormatException('Invalid OfficeArt ink envelope extent.');
    }
    for (var i = 0; i < guid.length; i++) {
      if (bytes[i] != guid[i]) {
        throw const FormatException('Invalid OfficeArt ink envelope identity.');
      }
    }
    final input = _Bytes(bytes), length = input.u32(16);
    if (length != bytes.length - 20) {
      throw const FormatException('Invalid OfficeArt ink envelope byte count.');
    }
    return input.slice(20, length);
  }

  LegacyWordOfficeArtShape read() {
    final inkData = _inkData;
    final ink =
        inkData != null || p.containsKey(0x073f) || p.containsKey(0x0700)
        ? LegacyWordOfficeArtInk(
            data: inkData,
            annotation: _used(0x073f, 3),
            hitTestInk: _used(0x073f, 2),
            renderShape: _used(0x073f, 1),
            renderInk: _used(0x073f, 0),
          )
        : null;
    final fill = p.keys.any((id) => id >= 0x0180 && id <= 0x01bf)
        ? LegacyWordOfficeArtFill(
            enabled: _used(0x01bf, 4),
            type: _enum(0x0180, 9),
            color: _color(0x0181),
            opacityFixed16: _opacity(0x0182),
            // MS-ODRAW 2.3.7.4: the background is inactive for solid fills.
            backColor: (p[0x0180] ?? 0) == 0 ? null : _color(0x0183),
            backOpacityFixed16: _opacity(0x0184),
            angleFixed16: _signed(0x018b, -360 * 65536, 360 * 65536),
            focusPercent: _signed(0x018c, -100, 100),
            rotateWithShape: _used(0x01bf, 5),
            imageId: fillImage?.id,
            imageSourceName: _fillImageName(),
            imageNameFlags: p[0x0188],
            recolorAsPicture: _used(0x01bf, 6),
          )
        : null;
    final line = p.keys.any((id) => id >= 0x01c0 && id <= 0x01ff)
        ? LegacyWordOfficeArtLine(
            enabled: _used(0x01ff, 3),
            type: _enum(0x01c4, 4),
            color: _color(0x01c0),
            opacityFixed16: _opacity(0x01c1),
            widthEmu: _nonnegative(0x01cb, maximum: 0x0132f540),
            compoundStyle: _enum(0x01cd, 4),
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
    const positionProperties = {0x038f, 0x0390, 0x0391, 0x0392};
    final position =
        positionProperties.any(
          (id) => p.containsKey(id) || properties.complex.containsKey(id),
        )
        ? LegacyWordOfficeArtPosition(
            horizontalMode: p[0x038f],
            horizontalRelativeTo: p[0x0390],
            verticalMode: p[0x0391],
            verticalRelativeTo: p[0x0392],
          )
        : null;
    for (final id in positionProperties) {
      final maximum = id == 0x038f || id == 0x0391 ? 5 : 3;
      if (properties.complex.containsKey(id) || (p[id] ?? 0) > maximum) {
        unsupported.add(id);
      }
    }
    const wrapProperties = {0x0384, 0x0385, 0x0386, 0x0387};
    final wrapDistances =
        wrapProperties.any(
          (id) => p.containsKey(id) || properties.complex.containsKey(id),
        )
        ? LegacyWordOfficeArtWrapDistances(
            leftEmu: _nonnegative(0x0384),
            topEmu: _nonnegative(0x0385),
            rightEmu: _nonnegative(0x0386),
            bottomEmu: _nonnegative(0x0387),
          )
        : null;
    for (final id in wrapProperties) {
      if (properties.complex.containsKey(id)) unsupported.add(id);
    }
    final geometry = _geometry();
    final imageFill = const {1, 2, 3}.contains(fill?.type);
    final resolvedImage =
        fillImage?.isRenderable == true &&
        (fill?.type != 1 || fillImage?.nativeBitmapBytes != null);
    if (!const {null, 0, 7}.contains(fill?.type) &&
        !(imageFill && resolvedImage)) {
      unsupported.add(0x0180);
    }
    if (imageFill && !resolvedImage) unsupported.add(0x0186);
    if (properties.complex.containsKey(0x0188) || (p[0x0188] ?? 0) != 0) {
      // Linked/file/URL fill sources require their own mapping. A stored
      // comment with a validated embedded BLIP does not create a live link.
      unsupported.add(0x0188);
    }
    for (final id in [0x0180, 0x0181, 0x0182, 0x0184, 0x018b, 0x018c, 0x01bf]) {
      if (properties.complex.containsKey(id)) unsupported.add(id);
    }
    if (line?.type != null && line!.type != 0) unsupported.add(0x01c4);
    if (properties.complex.containsKey(0x01cb)) unsupported.add(0x01cb);
    if (properties.complex.containsKey(0x01cd) ||
        (line?.compoundStyle ?? 0) != 0) {
      unsupported.add(0x01cd);
    }
    if (properties.complex.containsKey(0x01ff)) unsupported.add(0x01ff);
    if (shadow?.type != null && shadow!.type != 0) unsupported.add(0x0200);
    // MS-ODRAW 2.3.7.2 marks the background color unused for a solid fill.
    // Line background color is inactive for a solid line unless the separate
    // opaque-background bit enables an extra stroke (2.3.8.38). Complex or
    // unresolved operands must not receive this exception.
    if (properties.complex.containsKey(0x0183) ||
        (p.containsKey(0x0183) && properties.complex.containsKey(0x0180))) {
      unsupported.add(0x0183);
    }
    if (properties.complex.containsKey(0x01c2) ||
        (p.containsKey(0x01c2) &&
            ((p[0x01c4] ?? 0) != 0 ||
                properties.complex.containsKey(0x01c4) ||
                properties.complex.containsKey(0x01ff) ||
                _used(0x01ff, 9) == true))) {
      unsupported.add(0x01c2);
    }
    // Every other explicitly used group Boolean remains unresolved. In
    // particular, a child layout flag must not erase inherited hidden,
    // printing, overlap, script, wrapping or behind-document semantics.
    if (properties.complex.containsKey(0x03bf) ||
        (((p[0x03bf] ?? 0) ~/ 65536) & 0x7fff) != 0) {
      unsupported.add(0x03bf);
    }
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
      0x0183,
      0x0184,
      0x0187,
      0x0188,
      0x018b,
      0x018c,
      0x01bf,
      0x01c0,
      0x01c1,
      0x01c2,
      0x01c4,
      0x01cb,
      0x01cd,
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
      // Coordinate/flip properties outside the resolved FSP flags and scalar
      // rotation can change a transform. Retain them as unsupported instead
      // of emitting a transform that silently overrides those source fields.
      if ((id <= 0x003f && id != 0x0004) ||
          (id == 0x0004 && properties.complex.containsKey(id))) {
        unsupported.add(id);
      }
      // A zero-length BLIP cannot supply an image. Word writes these empty
      // inherited operands for plain fills and lines; they have no active
      // pattern/texture meaning in the resolved solid/gradient subset.
      final inactiveEmptyBlip =
          properties.complex[id]?.isEmpty == true &&
          ((id == 0x0186 && const {0, 7}.contains(p[0x0180] ?? 0)) ||
              (id == 0x01c5 &&
                  (p[0x01c4] ?? 0) == 0 &&
                  !properties.complex.containsKey(0x01c4)));
      if (id >= 0x0140 &&
          id <= 0x02ff &&
          !mapped.contains(id) &&
          !inactiveEmptyBlip &&
          !(id == 0x0186 && imageFill && resolvedImage)) {
        unsupported.add(id);
      }
      // WordArt and unmodeled shape/group properties can
      // change appearance or placement. Plain name/description metadata does
      // not. Do not turn such a shape into an apparently complete plain path.
      if ((id >= 0x00c0 && id <= 0x00ff) ||
          (id >= 0x0300 &&
              id <= 0x07ff &&
              id != 0x0380 &&
              id != 0x0381 &&
              id != 0x03bf &&
              !wrapProperties.contains(id) &&
              !positionProperties.contains(id))) {
        unsupported.add(id);
      }
    }
    // Fill rectangles, recoloring, and inset/background-line styles alter
    // appearance beyond the direct solid-color subset.
    if (_used(0x01bf, 1) == true ||
        (_used(0x01bf, 2) == false && (fill?.type ?? 0) != 0) ||
        (_used(0x01bf, 6) == true &&
            (properties.complex.containsKey(0x010d) ||
                properties.complex.containsKey(0x0185) ||
                (p[0x010d] ?? 0x20000000) != 0x20000000 ||
                (p[0x0185] ?? 0x20000000) != 0x20000000))) {
      unsupported.add(0x01bf);
    }
    // fNoLineDrawDash requests a dashed indication even when the ordinary
    // line is disabled (MS-ODRAW 2.3.8.38). Merely writing stroked="f" would
    // lose that source appearance. Preserve the flag as unsupported evidence
    // until this distinct fallback stroke has a validated native mapping.
    if ((_used(0x01ff, 0) == true && line?.enabled == false) ||
        _used(0x01ff, 6) == true ||
        _used(0x01ff, 9) == true) {
      unsupported.add(0x01ff);
    }
    return LegacyWordOfficeArtShape(
      type: type,
      sourceFlags: flags,
      rotationFixed16: (p[0x0004] ?? 0).toSigned(32),
      flipHorizontal: (flags & 0x40) != 0,
      flipVertical: (flags & 0x80) != 0,
      geometry: geometry,
      fill: fill,
      line: line,
      shadow: shadow,
      text: text,
      position: position,
      wrapDistances: wrapDistances,
      groupShapeBooleanProperties: p[0x03bf],
      ink: ink,
      discussionAnchor: p[0x0307] == 1,
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

  int? _nonnegative(int id, {int maximum = 0x7fffffff}) {
    final value = p[id];
    if (value != null && value > maximum) {
      unsupported.add(id);
      return null;
    }
    return value;
  }

  int? _signed(int id, int minimum, int maximum) {
    final value = p[id]?.toSigned(32);
    if (value != null && (value < minimum || value > maximum)) {
      unsupported.add(id);
      return null;
    }
    return value;
  }

  String? _fillImageName() {
    final bytes = properties.complex[0x0187];
    if (bytes == null) {
      if ((p[0x0187] ?? 0) != 0) unsupported.add(0x0187);
      return null;
    }
    if (bytes.isEmpty) return null;
    if (bytes.length.isOdd || bytes.length > 32768) {
      unsupported.add(0x0187);
      return null;
    }
    final input = _Bytes(bytes), count = bytes.length ~/ 2;
    if (input.u16(bytes.length - 2) != 0) {
      unsupported.add(0x0187);
      return null;
    }
    final units = <int>[];
    for (var index = 0; index < count - 1; index++) {
      final unit = input.u16(index * 2);
      if (unit == 0 || (unit >= 0xdc00 && unit <= 0xdfff)) {
        unsupported.add(0x0187);
        return null;
      }
      units.add(unit);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++index >= count - 1) {
          unsupported.add(0x0187);
          return null;
        }
        final low = input.u16(index * 2);
        if (low < 0xdc00 || low > 0xdfff) {
          unsupported.add(0x0187);
          return null;
        }
        units.add(low);
      }
    }
    return String.fromCharCodes(units);
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
      if (array.$3 == 4) {
        // pVertices' 0xFFF0 form stores two signed 16-bit coordinates. Both
        // native DOC playback and an independently implemented OfficeArt
        // producer confirm this POINT-specific interpretation of IMsoArray.
        points.add(
          LegacyWordOfficeArtPoint(
            array.$1.i16(i * 4),
            array.$1.i16(i * 4 + 2),
          ),
        );
        continue;
      }
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
    final editingHints = <LegacyWordOfficeArtPathEditingHint>[];
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
        // MS-ODRAW 2.4.31: SymmetricCurve describes editing tangents rather
        // than a new drawing segment. Accept only the observed zero-count
        // form after a current point, keeping its association as evidence.
        // Other escapes, client escapes and paint modifiers remain inert.
        if (value == 0xb300 && begun && !ended) {
          editingHints.add(
            LegacyWordOfficeArtPathEditingHint(cursor - 1, 0x13),
          );
          continue;
        }
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
    return LegacyWordOfficeArtGeometry(
      bounds: bounds,
      path: path,
      editingHints: editingHints,
    );
  }

  (_Bytes, int, int)? _array(Uint8List bytes, int id, int size, int limit) {
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
    final packedPoints = id == 0x0145 && storedSize == 0xfff0;
    if ((storedSize != size && !packedPoints) || (packedPoints && type == 19)) {
      // Arc presets use a different unsigned packed-coordinate convention in
      // native readers. Keep that unverified case inert instead of applying
      // the signed custom-path interpretation to it.
      unsupported.add(id);
      return null;
    }
    return (_Bytes(input.slice(6, input.length - 6)), count, actualSize);
  }
}
