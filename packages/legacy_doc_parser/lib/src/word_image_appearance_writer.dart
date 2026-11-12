// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

class _ImageTransform {
  const _ImageTransform({
    this.rotation = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
  });

  final int rotation;
  final bool flipHorizontal, flipVertical;
  bool get swapsAxes => rotation % 10800000 == 5400000;
  String get attributes =>
      '${rotation == 0 ? '' : ' rot="$rotation"'}'
      '${flipHorizontal ? ' flipH="1"' : ''}'
      '${flipVertical ? ' flipV="1"' : ''}';
}

extension _WordImageAppearance on _StructuredWordWriter {
  bool _canWriteImageAppearance(LegacyWordOfficeArtShape shape) =>
      shape.type == 75 &&
      (shape.sourceFlags & 0x3f) == 0 &&
      shape.ink == null &&
      !shape.discussionAnchor &&
      !shape.unsupportedProperties.any((id) => id >= 0x0240 && id <= 0x02ff);

  _ImageTransform _imageTransform(
    LegacyWordOfficeArtShape? shape, {
    bool floatingAbsolute = false,
  }) {
    if (shape == null) return const _ImageTransform();
    if (shape.unsupportedProperties.isNotEmpty) {
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
    }
    if (!_canWriteImageAppearance(shape) ||
        shape.unsupportedProperties.any((id) => id <= 0x003f || id == 0x033f)) {
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
      return const _ImageTransform();
    }
    final sourceRotation = shape.rotationFixed16;
    if (sourceRotation < -0x80000000 || sourceRotation > 0x7fffffff) {
      _tooComplex();
    }
    var rotation = 0;
    if (sourceRotation != 0) {
      // FSPA quarter-turn rectangles interchange the unrotated axes. Their
      // center can be retained without solving an arbitrary rotated box.
      if (floatingAbsolute && sourceRotation % (90 * 65536) == 0) {
        rotation = (sourceRotation ~/ (90 * 65536) % 4) * 5400000;
      } else {
        limitations.add(LegacyWordConversionLimitation.partialFormatting);
        _evidenceRecords.add({
          'kind': 'unrenderedImageRotation',
          'rotationFixed16': sourceRotation,
          'reason':
              'Only absolute floating picture-frame quarter turns have a verified extent mapping; source OfficeArt remains evidence.',
        });
      }
    }
    return _ImageTransform(
      rotation: rotation,
      flipHorizontal: shape.flipHorizontal,
      flipVertical: shape.flipVertical,
    );
  }

  void _imageAppearance(LegacyWordOfficeArtShape? shape) {
    if (shape == null || !_canWriteImageAppearance(shape)) return;
    final line = shape.line;
    if (line?.enabled == false) {
      _xml.add('<a:ln><a:noFill/></a:ln>');
    } else if (line != null &&
        (line.enabled == true ||
            line.color != null ||
            line.opacityFixed16 != null ||
            line.widthEmu != null ||
            line.dash != null ||
            line.join != null ||
            line.cap != null)) {
      // A solid line has no patterned background. A nondefault opaque
      // background flag is separately diagnosed as unsupported 0x01ff.
      if ((line.type ?? 0) != 0 ||
          shape.unsupportedProperties.any(
            (id) => id >= 0x01c0 && id <= 0x01ff && id != 0x01c2,
          )) {
        limitations.add(LegacyWordConversionLimitation.partialFormatting);
      } else {
        final width = line.widthEmu ?? 9525;
        if (width < 0 || width > 0x0132f540) _tooComplex();
        final cap = _imageEnum(const ['rnd', 'sq', 'flat'], line.cap ?? 2);
        final dash = _imageEnum(const [
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
        ], line.dash ?? 0);
        final join = _imageEnum(const [
          'bevel',
          'miter',
          'round',
        ], line.join ?? 2);
        _xml.add('<a:ln w="$width" cap="$cap"><a:solidFill>');
        _imageColor(line.color ?? '000000', line.opacityFixed16);
        _xml.add('</a:solidFill><a:prstDash val="$dash"/><a:$join');
        if (join == 'miter') _xml.add(' lim="800000"');
        _xml.add('/></a:ln>');
      }
    }
    final shadow = shape.shadow;
    if (shadow?.enabled != true) return;
    if ((shadow!.type ?? 0) != 0 ||
        shadow.obscured == true ||
        shape.unsupportedProperties.any((id) => id >= 0x0200 && id <= 0x023f)) {
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
      return;
    }
    final x = shadow.offsetXEmu ?? 25400, y = shadow.offsetYEmu ?? 25400;
    if (x < -0x80000000 ||
        x > 0x7fffffff ||
        y < -0x80000000 ||
        y > 0x7fffffff) {
      _tooComplex();
    }
    final distance = math.sqrt(x.toDouble() * x + y.toDouble() * y).round();
    final direction =
        (math.atan2(y.toDouble(), x.toDouble()) * 10800000 / math.pi).round() %
        21600000;
    _xml.add(
      '<a:effectLst><a:outerShdw blurRad="0" dist="$distance" '
      'dir="$direction" algn="ctr" rotWithShape="0">',
    );
    _imageColor(shadow.color ?? '808080', shadow.opacityFixed16);
    _xml.add('</a:outerShdw></a:effectLst>');
  }

  void _imageColor(String color, int? opacity) {
    _xml.add('<a:srgbClr val="${_StructuredWordWriter._color(color)}">');
    if (opacity != null) {
      if (opacity < 0 || opacity > 65536) _tooComplex();
      _xml.add('<a:alpha val="${(opacity * 100000 / 65536).round()}"/>');
    }
    _xml.add('</a:srgbClr>');
  }

  String _imageEnum(List<String> values, int index) {
    if (index < 0 || index >= values.length) _tooComplex();
    return values[index];
  }
}
