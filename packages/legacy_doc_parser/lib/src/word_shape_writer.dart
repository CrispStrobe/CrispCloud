// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

/// Editable VML for fully resolved geometry and direct solid appearance.
/// Unknown effects are not turned into a simplified active drawing. Their
/// original OfficeArt remains in the existing evidence path.
extension _WordShapes on _StructuredWordWriter {
  bool _canWriteShape(LegacyWordOfficeArtShape? shape) {
    if (shape == null ||
        shape.unsupportedProperties.isNotEmpty ||
        shape.ink != null ||
        shape.discussionAnchor ||
        (((shape.groupShapeBooleanProperties ?? 0) ~/ 65536) & 0x7fff) != 0 ||
        (shape.sourceFlags & 0x37) != 0) {
      return false;
    }
    final geometry = shape.geometry;
    if (geometry == null ||
        !const {null, 'rect', 'ellipse', 'line'}.contains(geometry.preset) ||
        (geometry.preset == null && geometry.path.isEmpty) ||
        (shape.fill?.type ?? 0) != 0 ||
        (shape.line?.type ?? 0) != 0 ||
        (shape.line?.compoundStyle ?? 0) != 0 ||
        (shape.shadow?.type ?? 0) != 0) {
      return false;
    }
    return true;
  }

  void _shapeDrawing(LegacyWordDrawing drawing) {
    final shape = drawing.shape!, geometry = shape.geometry!;
    if (geometry.editingHints.isNotEmpty) {
      final vertices = geometry.path.fold<int>(
        0,
        (count, command) => count + command.points.length,
      );
      if (geometry.preset != null ||
          geometry.editingHints.length > 16384 ||
          geometry.editingHints.any(
            (hint) =>
                hint.escape != 0x13 ||
                hint.vertexIndex < 0 ||
                hint.vertexIndex >= vertices,
          )) {
        throw const FormatException('Invalid OfficeArt path editing hint.');
      }
      _count('shapePathEditingHints', geometry.editingHints.length);
      if ((counts['shapePathCommands'] ?? 0) +
              counts['shapePathEditingHints']! >
          100000) {
        _tooComplex();
      }
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
      _evidenceRecords.add({
        'kind': 'pathEditingHints',
        'shapeId': drawing.shapeId,
        'hints': [
          for (final hint in geometry.editingHints)
            {'vertexIndex': hint.vertexIndex, 'escape': hint.escape},
        ],
        'reason':
            'Source editing-tangent hints retained as evidence; rendered segments are explicit, but native tangent-editor behavior is not mapped.',
      });
    }
    final bounds = geometry.bounds;
    if (bounds.width <= 0 ||
        bounds.height <= 0 ||
        [
          bounds.left,
          bounds.top,
          bounds.right,
          bounds.bottom,
          bounds.width,
          bounds.height,
        ].any((n) => n.abs() > 0x7fffffff) ||
        shape.rotationFixed16.abs() > 360 * 65536) {
      _tooComplex();
    }
    final zeroExtentLine =
        geometry.preset == 'line' &&
        (drawing.leftTwips == drawing.rightTwips ||
            drawing.topTwips == drawing.bottomTwips);
    final element = zeroExtentLine
        ? 'line'
        : geometry.preset == 'ellipse'
        ? 'oval'
        : 'shape';
    final prefix = drawing.headerStory ? 'Header' : '';
    _mediaStart(drawing.presentation);
    _xml.add(
      '<w:pict><v:$element id="_legacy${prefix}Shape${drawing.shapeId}" ',
    );
    if (zeroExtentLine) {
      // VML line endpoints are in the parent's coordinate space. A shape
      // rectangle with a zero dimension instead requires an invalid scale.
      // Keep source flips in the style; reversing from/to creates negative
      // line extents in native consumers.
      _xml.add(
        'from="${drawing.leftTwips / 20}pt,${drawing.topTwips / 20}pt" '
        'to="${drawing.rightTwips / 20}pt,${drawing.bottomTwips / 20}pt" '
        'style="position:absolute;',
      );
    } else {
      _xml.add(
        'coordorigin="${bounds.left},${bounds.top}" '
        'coordsize="${bounds.width},${bounds.height}" '
        'style="position:absolute;margin-left:${drawing.leftTwips / 20}pt;'
        'margin-top:${drawing.topTwips / 20}pt;'
        'width:${(drawing.rightTwips - drawing.leftTwips) / 20}pt;'
        'height:${(drawing.bottomTwips - drawing.topTwips) / 20}pt;',
      );
    }
    _xml.add(
      '${_officeArtVmlPosition(drawing)}'
      'z-index:${drawing.behindText ? -1 : drawing.shapeId}',
    );
    if (shape.rotationFixed16 != 0) {
      _xml.add(';rotation:${shape.rotationFixed16 / 65536}');
    }
    if (shape.flipHorizontal || shape.flipVertical) {
      _xml.add(
        ';flip:${[if (shape.flipHorizontal) 'x', if (shape.flipVertical) 'y'].join(' ')}',
      );
    }
    _xml.add('"');
    if (element == 'shape') {
      _xml.add(' path="');
      if (geometry.preset == 'rect') {
        _xml.add(
          'm${bounds.left},${bounds.top}'
          'l${bounds.right},${bounds.top},${bounds.right},${bounds.bottom},${bounds.left},${bounds.bottom}xe',
        );
      } else if (geometry.preset == 'line') {
        _xml.add(
          'm${bounds.left},${bounds.top}l${bounds.right},${bounds.bottom}e',
        );
      } else {
        _shapePath(geometry.path);
      }
      _xml.add('"');
    }
    _shapePaintAttributes(shape, lineGeometry: geometry.preset == 'line');
    if (shape.layoutInCell case final layout?) {
      _xml.add(' o:allowincell="${layout ? 't' : 'f'}"');
    }
    _xml.add('>');
    _shapePaintElements(shape);
    final wrap = switch (drawing.wrapMode) {
      1 => 'topAndBottom',
      3 => 'none',
      _ => 'square',
    };
    if (drawing.wrapMode == 4 || drawing.wrapMode == 5) {
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
    }
    final side = ['both', 'left', 'right', 'largest'][drawing.wrapSide];
    _xml.add(
      '<w10:wrap xmlns:w10="urn:schemas-microsoft-com:office:word" '
      'type="$wrap" side="$side"${_officeArtVmlWrapOrigins(drawing)}/>'
      '</v:$element></w:pict>',
    );
    _mediaEnd(drawing.presentation);
    _count('editableShapes');
    _evidenceRecords.add(
      _drawingMetadata(drawing)
        ..['kind'] = 'editableShape'
        ..['geometry'] = geometry.preset ?? 'customPath'
        ..['reason'] =
            'Resolved source geometry and supported paint emitted as editable VML; host layout and raster equivalence are not certified.',
    );
  }

  void _shapePath(List<LegacyWordOfficeArtPathCommand> path) {
    if (path.length > 16384) _tooComplex();
    _count('shapePathCommands', path.length);
    if (counts['shapePathCommands']! + (counts['shapePathEditingHints'] ?? 0) >
        100000) {
      _tooComplex();
    }
    var begun = false;
    for (final command in path) {
      final expected = switch (command.kind) {
        LegacyWordOfficeArtPathKind.move ||
        LegacyWordOfficeArtPathKind.line => 1,
        LegacyWordOfficeArtPathKind.cubic => 3,
        LegacyWordOfficeArtPathKind.close => 0,
      };
      if (command.points.length != expected ||
          (!begun && command.kind != LegacyWordOfficeArtPathKind.move)) {
        throw const FormatException('Invalid resolved OfficeArt path.');
      }
      if (command.points.any(
        (p) => p.x.abs() > 0x7fffffff || p.y.abs() > 0x7fffffff,
      )) {
        _tooComplex();
      }
      final code = switch (command.kind) {
        LegacyWordOfficeArtPathKind.move => 'm',
        LegacyWordOfficeArtPathKind.line => 'l',
        LegacyWordOfficeArtPathKind.cubic => 'c',
        LegacyWordOfficeArtPathKind.close => 'x',
      };
      if (command.kind == LegacyWordOfficeArtPathKind.move) begun = true;
      _xml.add('$code${command.points.map((p) => '${p.x},${p.y}').join(',')}');
    }
    _xml.add('e');
  }

  void _shapePaintAttributes(
    LegacyWordOfficeArtShape shape, {
    bool lineGeometry = false,
  }) {
    final fill = shape.fill, line = shape.line;
    _xml.add(
      ' filled="${!lineGeometry && fill?.enabled != false ? 't' : 'f'}"'
      ' fillcolor="#${_StructuredWordWriter._color(fill?.color ?? 'FFFFFF')}"'
      ' stroked="${line?.enabled != false ? 't' : 'f'}"'
      ' strokecolor="#${_StructuredWordWriter._color(line?.color ?? '000000')}"',
    );
    // Source lineWidth defaults to 0x2535 EMU (0.75 pt), whereas VML's
    // strokeweight default is 1 pt. Emit source defaults explicitly.
    final width = line?.widthEmu ?? 9525;
    if (width < 0 || width > 0x0132f540) _tooComplex();
    _xml.add(' strokeweight="${width / 12700}pt"');
  }

  String _shapeOpacity(int value) {
    if (value < 0 || value > 65536) _tooComplex();
    return '${value / 65536}';
  }

  void _shapePaintElements(
    LegacyWordOfficeArtShape shape, {
    bool includeFill = true,
    bool includeStroke = true,
    bool includeShadow = true,
  }) {
    final fill = shape.fill, line = shape.line, shadow = shape.shadow;
    if (includeFill && fill?.opacityFixed16 != null) {
      _xml.add('<v:fill opacity="${_shapeOpacity(fill!.opacityFixed16!)}"/>');
    }
    if (includeStroke) {
      _xml.add('<v:stroke');
      if (line?.opacityFixed16 != null) {
        _xml.add(' opacity="${_shapeOpacity(line!.opacityFixed16!)}"');
      }
      const dashes = [
        'solid',
        'shortdash',
        'shortdot',
        'shortdashdot',
        'shortdashdotdot',
        'dot',
        'dash',
        'longdash',
        'dashdot',
        'longdashdot',
        'longdashdotdot',
      ];
      for (final (name, value, choices) in [
        ('dashstyle', line?.dash ?? 0, dashes),
        ('joinstyle', line?.join ?? 2, ['bevel', 'miter', 'round']),
        ('endcap', line?.cap ?? 2, ['round', 'square', 'flat']),
      ]) {
        if (value < 0 || value >= choices.length) _tooComplex();
        _xml.add(' $name="${choices[value]}"');
      }
      _xml.add('/>');
    }
    if (includeShadow && shadow != null) {
      // Shadow properties do not enable a shadow unless its used flag does.
      _xml.add(
        '<v:shadow on="${shadow.enabled == true ? 't' : 'f'}" type="single"',
      );
      _xml.add(
        ' color="#${_StructuredWordWriter._color(shadow.color ?? '808080')}"',
      );
      if (shadow.opacityFixed16 != null) {
        _xml.add(' opacity="${_shapeOpacity(shadow.opacityFixed16!)}"');
      }
      if (shadow.obscured != null) {
        _xml.add(' obscured="${shadow.obscured! ? 't' : 'f'}"');
      }
      if (shadow.offsetXEmu != null || shadow.offsetYEmu != null) {
        final x = shadow.offsetXEmu ?? 25400, y = shadow.offsetYEmu ?? 25400;
        if (x.abs() > 0x7fffffff || y.abs() > 0x7fffffff) _tooComplex();
        _xml.add(' offset="${x / 12700}pt,${y / 12700}pt"');
      }
      _xml.add('/>');
    }
  }
}
