// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

// VML uses lowercase dash keywords. DrawingML below has a different spelling;
// the native regression rendered camel-case "shortDot" as a solid line.
const _vmlDashStyles = [
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
const _drawingDashStyles = [
  'solid',
  'sysDash',
  'sysDot',
  'sysDashDot',
  'sysDashDotDot',
  'dot',
  'dash',
  'lgDash',
  'dashDot',
  'lgDashDot',
  'lgDashDotDot',
];

extension _WordOfficeArt on _StructuredWordWriter {
  /// Style declarations end with a semicolon and contain generated numbers only.
  String _officeArtVmlStyle(LegacyWordOfficeArtShape? shape) {
    if (shape == null) return '';
    final rotation = _officeArtRotation(shape);
    return '${rotation == 0 ? '' : 'rotation:${_officeArtNumber(rotation / 60000)};'}'
        '${!shape.flipHorizontal && !shape.flipVertical ? '' : 'flip:${shape.flipHorizontal ? 'x' : ''}${shape.flipVertical ? 'y' : ''};'}';
  }

  /// Leading-space attributes, with absence distinct from an explicit false.
  String _officeArtVmlAttributes(LegacyWordOfficeArtShape? shape) {
    if (shape == null) return '';
    _officeArtDiagnostics(shape);
    final fill = shape.fill, line = shape.line;
    final output = StringBuffer();
    if (fill?.enabled != null) {
      output.write(' filled="${fill!.enabled! ? 't' : 'f'}"');
    }
    if (fill?.color != null && (fill!.type == null || fill.type == 0)) {
      output.write(' fillcolor="#${_officeArtColor(fill.color!)}"');
    }
    if (line?.enabled != null) {
      output.write(' stroked="${line!.enabled! ? 't' : 'f'}"');
    }
    if (line?.color != null && (line!.type == null || line.type == 0)) {
      output.write(' strokecolor="#${_officeArtColor(line.color!)}"');
    }
    if (line?.widthEmu != null) {
      _officeArtUnsigned(line!.widthEmu!);
      output.write(
        ' strokeweight="${_officeArtNumber(line.widthEmu! / 12700)}pt"',
      );
    }
    return output.toString();
  }

  /// Fixed VML children shared by ordinary shapes and linked text boxes.
  void _officeArtVmlChildren(LegacyWordOfficeArtShape? shape) {
    if (shape == null) return;
    _officeArtDiagnostics(shape);
    final fill = shape.fill, line = shape.line, shadow = shape.shadow;
    if (fill?.opacityFixed16 != null &&
        fill!.enabled != false &&
        (fill.type == null || fill.type == 0)) {
      _xml.add(
        '<v:fill type="solid" opacity="${_officeArtOpacity(fill.opacityFixed16!)}"/>',
      );
    }
    if (line != null &&
        line.enabled != false &&
        (line.type == null || line.type == 0)) {
      final attributes = StringBuffer();
      if (line.opacityFixed16 != null) {
        attributes.write(
          ' opacity="${_officeArtOpacity(line.opacityFixed16!)}"',
        );
      }
      if (line.dash != null) {
        attributes.write(
          ' dashstyle="${_officeArtEnum(_vmlDashStyles, line.dash!)}"',
        );
      }
      if (line.join != null) {
        attributes.write(
          ' joinstyle="${_officeArtEnum(const ['bevel', 'miter', 'round'], line.join!)}"',
        );
      }
      if (line.cap != null) {
        attributes.write(
          ' endcap="${_officeArtEnum(const ['round', 'square', 'flat'], line.cap!)}"',
        );
      }
      if (attributes.isNotEmpty) _xml.add('<v:stroke$attributes/>');
    }
    if (_officeArtSimpleShadow(shape)) {
      final opacity = _officeArtOpacity(shadow!.opacityFixed16 ?? 65536);
      final color = _officeArtColor(shadow.color ?? '808080');
      final x = shadow.offsetXEmu ?? 25400, y = shadow.offsetYEmu ?? 25400;
      _officeArtSigned(x);
      _officeArtSigned(y);
      _xml.add(
        '<v:shadow on="t" type="single" color="#$color" opacity="$opacity" '
        'offset="${_officeArtNumber(x / 12700)}pt,${_officeArtNumber(y / 12700)}pt"'
        '${shadow.obscured == null ? '' : ' obscured="${shadow.obscured! ? 't' : 'f'}"'}/>',
      );
    }
  }

  void _officeArtDiagnostics(LegacyWordOfficeArtShape shape) {
    if (shape.unsupportedProperties.isNotEmpty) {
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
    }
  }

  /// Word's native DOC producer/consumer mapping is zero-based (margin, page,
  /// text, character/line). Keep the source FSPA and explicit values separate.
  /// LibreOffice ProcessEscherAlign gives explicit 0x390/0x392 precedence.
  String _officeArtVmlPosition(LegacyWordDrawing drawing) {
    final position = drawing.shape?.position;
    final horizontal = _officeArtEnum(const [
      'margin',
      'page',
      'text',
      'char',
    ], position?.horizontalRelativeTo ?? drawing.horizontalOrigin);
    final vertical = _officeArtEnum(const [
      'margin',
      'page',
      'text',
      'line',
    ], position?.verticalRelativeTo ?? drawing.verticalOrigin);
    final h = position?.horizontalMode ?? 0, v = position?.verticalMode ?? 0;
    return 'mso-position-horizontal-relative:$horizontal;'
        'mso-position-vertical-relative:$vertical;'
        '${h == 0 ? '' : 'mso-position-horizontal:${_officeArtEnum(const ['absolute', 'left', 'center', 'right', 'inside', 'outside'], h)};'}'
        '${v == 0 ? '' : 'mso-position-vertical:${_officeArtEnum(const ['absolute', 'top', 'center', 'bottom', 'inside', 'outside'], v)};'}';
  }

  void _officeArtDrawingPosition(LegacyWordDrawing drawing) {
    final position = drawing.shape?.position;
    final horizontal = _officeArtEnum(const [
      'margin',
      'page',
      'column',
      'character',
    ], position?.horizontalRelativeTo ?? drawing.horizontalOrigin);
    final vertical = _officeArtEnum(const [
      'margin',
      'page',
      'paragraph',
      'line',
    ], position?.verticalRelativeTo ?? drawing.verticalOrigin);
    final h = position?.horizontalMode ?? 0, v = position?.verticalMode ?? 0;
    _xml.add('<wp:positionH relativeFrom="$horizontal">');
    _xml.add(
      h == 0
          ? '<wp:posOffset>${drawing.leftTwips * 635}</wp:posOffset>'
          : '<wp:align>${_officeArtEnum(const ['', 'left', 'center', 'right', 'inside', 'outside'], h)}</wp:align>',
    );
    _xml.add('</wp:positionH><wp:positionV relativeFrom="$vertical">');
    _xml.add(
      v == 0
          ? '<wp:posOffset>${drawing.topTwips * 635}</wp:posOffset>'
          : '<wp:align>${_officeArtEnum(const ['', 'top', 'center', 'bottom', 'inside', 'outside'], v)}</wp:align>',
    );
    _xml.add('</wp:positionV>');
  }

  bool _officeArtSimpleShadow(LegacyWordOfficeArtShape shape) {
    final shadow = shape.shadow;
    if (shadow?.enabled != true) return false;
    if ((shadow!.type != null && shadow.type != 0) ||
        shape.unsupportedProperties.any((id) => id >= 0x0200 && id <= 0x023f)) {
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
      return false;
    }
    return true;
  }

  bool _officeArtDrawable(LegacyWordOfficeArtShape? shape) {
    if (shape?.geometry == null) return false;
    final geometry = shape!.geometry!;
    if (geometry.bounds.width <= 0 ||
        geometry.bounds.height <= 0 ||
        geometry.path.length > 100000) {
      _tooComplex();
    }
    for (final value in [
      geometry.bounds.left,
      geometry.bounds.top,
      geometry.bounds.right,
      geometry.bounds.bottom,
    ]) {
      _officeArtSigned(value);
    }
    if (geometry.preset != null &&
        !const {
          'rect',
          'roundRect',
          'ellipse',
          'line',
        }.contains(geometry.preset)) {
      throw const FormatException('Unsupported OfficeArt output geometry.');
    }
    return geometry.preset != null || geometry.path.isNotEmpty;
  }

  void _officeArtDrawing(LegacyWordDrawing drawing) {
    final shape = drawing.shape!;
    final geometry = shape.geometry!;
    final id = ++_drawingId;
    final preset = geometry.preset;
    final tag = switch (preset) {
      'rect' => 'rect',
      'roundRect' => 'roundrect',
      'ellipse' => 'oval',
      _ => 'shape',
    };
    final width = (drawing.rightTwips - drawing.leftTwips) / 20;
    final height = (drawing.bottomTwips - drawing.topTwips) / 20;
    _mediaStart(drawing.presentation);
    _xml.add(
      '<w:pict><v:$tag id="_legacyOfficeArt$id" '
      'style="position:absolute;margin-left:${_officeArtNumber(drawing.leftTwips / 20)}pt;'
      'margin-top:${_officeArtNumber(drawing.topTwips / 20)}pt;'
      'width:${_officeArtNumber(width)}pt;height:${_officeArtNumber(height)}pt;'
      '${_officeArtVmlPosition(drawing)}'
      'z-index:${drawing.behindText ? -id : id};${_officeArtVmlStyle(shape)}"'
      '${_officeArtVmlAttributes(shape)}',
    );
    if (tag == 'shape') {
      final bounds = geometry.bounds;
      final path = preset == 'line'
          ? 'm${bounds.left},${bounds.top}l${bounds.right},${bounds.bottom}e'
          : _officeArtVmlPath(geometry);
      _xml.add(
        ' coordorigin="${bounds.left},${bounds.top}" '
        'coordsize="${bounds.width},${bounds.height}" path="$path"',
      );
    }
    _xml.add('>');
    _officeArtVmlChildren(shape);
    _officeArtVmlWrap(drawing);
    _xml.add('</v:$tag></w:pict>');
    _mediaEnd(drawing.presentation);
    _count('drawingReferences');
    _count('editableShapes');
    _evidenceRecords.add(
      _drawingMetadata(drawing)
        ..['nativeGeometry'] = preset ?? 'customPath'
        ..['unsupportedProperties'] = shape.unsupportedProperties,
    );
  }

  void _officeArtVmlWrap(LegacyWordDrawing drawing) {
    const ns = 'xmlns:w10="urn:schemas-microsoft-com:office:word"';
    final type = switch (drawing.wrapMode) {
      1 => 'topAndBottom',
      3 => 'none',
      _ => 'square',
    };
    if (drawing.wrapMode == 4 || drawing.wrapMode == 5) {
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
    }
    final side = ['both', 'left', 'right', 'largest'][drawing.wrapSide];
    _xml.add(
      '<w10:wrap $ns type="$type"${type == 'square' ? ' side="$side"' : ''}/>',
    );
    if (drawing.anchorLocked) _xml.add('<w10:anchorlock $ns/>');
  }

  String _officeArtVmlPath(LegacyWordOfficeArtGeometry geometry) {
    final path = StringBuffer();
    var begun = false;
    for (final command in geometry.path) {
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
      if (command.kind == LegacyWordOfficeArtPathKind.move) begun = true;
      path.write(switch (command.kind) {
        LegacyWordOfficeArtPathKind.move => 'm',
        LegacyWordOfficeArtPathKind.line => 'l',
        LegacyWordOfficeArtPathKind.cubic => 'c',
        LegacyWordOfficeArtPathKind.close => 'x',
      });
      var first = true;
      for (final point in command.points) {
        _officeArtSigned(point.x);
        _officeArtSigned(point.y);
        if (!first) path.write(',');
        path.write('${point.x},${point.y}');
        first = false;
      }
    }
    if (!geometry.fill) path.write('nf');
    if (!geometry.stroke) path.write('ns');
    path.write('e');
    return path.toString();
  }

  String _officeArtImageTransform(LegacyWordOfficeArtShape? shape) {
    if (shape == null) return '';
    _officeArtDiagnostics(shape);
    final rotation = _officeArtRotation(shape);
    return '${rotation == 0 ? '' : ' rot="$rotation"'}'
        '${shape.flipHorizontal ? ' flipH="1"' : ''}'
        '${shape.flipVertical ? ' flipV="1"' : ''}';
  }

  void _officeArtImageAppearance(LegacyWordOfficeArtShape? shape) {
    if (shape == null) return;
    final line = shape.line;
    if (line?.enabled == false) {
      _xml.add('<a:ln><a:noFill/></a:ln>');
    } else if (line != null &&
        (line.type == null || line.type == 0) &&
        (line.enabled == true ||
            line.color != null ||
            line.opacityFixed16 != null ||
            line.widthEmu != null ||
            line.dash != null ||
            line.join != null ||
            line.cap != null)) {
      if (line.widthEmu != null) _officeArtUnsigned(line.widthEmu!);
      final width = line.widthEmu == null ? '' : ' w="${line.widthEmu}"';
      final cap = line.cap == null
          ? ''
          : ' cap="${_officeArtEnum(const ['rnd', 'sq', 'flat'], line.cap!)}"';
      _xml.add('<a:ln$width$cap><a:solidFill>');
      _officeArtDrawingColor(line.color ?? '000000', line.opacityFixed16);
      _xml.add('</a:solidFill>');
      if (line.dash != null) {
        _xml.add(
          '<a:prstDash val="${_officeArtEnum(_drawingDashStyles, line.dash!)}"/>',
        );
      }
      if (line.join != null) {
        _xml.add(
          '<a:${_officeArtEnum(const ['bevel', 'miter', 'round'], line.join!)}'
          '${line.join == 1 ? ' lim="800000"' : ''}/>',
        );
      }
      _xml.add('</a:ln>');
    }
    if (_officeArtSimpleShadow(shape)) {
      final shadow = shape.shadow!;
      final x = shadow.offsetXEmu ?? 25400, y = shadow.offsetYEmu ?? 25400;
      _officeArtSigned(x);
      _officeArtSigned(y);
      final distance = sqrt(x.toDouble() * x + y.toDouble() * y).round();
      final direction =
          ((atan2(y.toDouble(), x.toDouble()) * 10800000 / pi).round()) %
          21600000;
      _xml.add(
        '<a:effectLst><a:outerShdw blurRad="0" dist="$distance" '
        'dir="$direction" algn="ctr" rotWithShape="0">',
      );
      _officeArtDrawingColor(shadow.color ?? '808080', shadow.opacityFixed16);
      _xml.add('</a:outerShdw></a:effectLst>');
      // DrawingML outer shadow cannot reproduce unfilled-shape obscuring exactly.
      if (shadow.obscured == true) {
        limitations.add(LegacyWordConversionLimitation.partialFormatting);
      }
    }
  }

  void _officeArtDrawingColor(String color, int? opacity) {
    _xml.add('<a:srgbClr val="${_officeArtColor(color)}">');
    if (opacity != null) {
      _officeArtOpacity(opacity);
      _xml.add('<a:alpha val="${(opacity * 100000 / 65536).round()}"/>');
    }
    _xml.add('</a:srgbClr>');
  }
}

String _officeArtNumber(num value) {
  if (!value.isFinite || value.abs() > 1e12) _tooComplex();
  if (value == 0) return '0';
  return value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
}

String _officeArtColor(String value) {
  if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(value)) {
    throw const FormatException('Invalid resolved OfficeArt color.');
  }
  return value.toUpperCase();
}

String _officeArtOpacity(int value) {
  if (value < 0 || value > 65536) _tooComplex();
  return _officeArtNumber(value / 65536);
}

String _officeArtEnum(List<String> values, int value) {
  if (value < 0 || value >= values.length) {
    throw const FormatException('Invalid resolved OfficeArt style.');
  }
  return values[value];
}

void _officeArtSigned(int value) {
  if (value < -2147483648 || value > 2147483647) _tooComplex();
}

void _officeArtUnsigned(int value) {
  if (value < 0 || value > 2147483647) _tooComplex();
}

int _officeArtRotation(LegacyWordOfficeArtShape shape) {
  _officeArtSigned(shape.rotationFixed16);
  return (shape.rotationFixed16 * 60000 / 65536).round() % 21600000;
}
