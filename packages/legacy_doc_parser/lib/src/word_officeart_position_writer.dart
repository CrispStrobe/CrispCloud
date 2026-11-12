// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

/// Word-specific FOPT origins supersede SPA on each explicitly present axis.
/// See doc/officeart-positioning.md for the independent Word binary evidence
/// and the discrepancy with the generic MS-ODRAW table. Offsets are never
/// adjusted for page margins: the receiving layout engine resolves the origin.
extension _WordOfficeArtPositionWriter on _StructuredWordWriter {
  Map<String, int> _officeArtWrapDistances(LegacyWordDrawing drawing) {
    final wrap = drawing.shape?.wrapDistances;
    final values = <String, int>{};
    for (final (side, value) in [
      ('left', wrap?.leftEmu),
      ('top', wrap?.topEmu),
      ('right', wrap?.rightEmu),
      ('bottom', wrap?.bottomEmu),
    ]) {
      if (value == null) continue;
      if (value < 0 || value > 0x7fffffff) _tooComplex();
      values[side] = value;
    }
    return values;
  }

  String _officeArtVmlWrapDistances(LegacyWordDrawing drawing) =>
      _officeArtWrapDistances(drawing).entries
          .map(
            (entry) =>
                'mso-wrap-distance-${entry.key}:${entry.value / 12700}pt;',
          )
          .join();

  ({int horizontal, int vertical, int horizontalMode, int verticalMode})
  _officeArtPosition(LegacyWordDrawing drawing) {
    final position = drawing.shape?.position;
    int value(int? raw, int fallback, int maximum) {
      if (raw == null) return fallback;
      if (raw >= 0 && raw <= maximum) return raw;
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
      return fallback;
    }

    return (
      horizontal: value(
        position?.horizontalRelativeTo,
        drawing.horizontalOrigin,
        3,
      ),
      vertical: value(position?.verticalRelativeTo, drawing.verticalOrigin, 3),
      horizontalMode: value(position?.horizontalMode, 0, 5),
      verticalMode: value(position?.verticalMode, 0, 5),
    );
  }

  String _officeArtVmlPosition(LegacyWordDrawing drawing) {
    final position = _officeArtPosition(drawing);
    const horizontal = ['margin', 'page', 'text', 'char'];
    const vertical = ['margin', 'page', 'text', 'line'];
    const horizontalModes = [
      'absolute',
      'left',
      'center',
      'right',
      'inside',
      'outside',
    ];
    const verticalModes = [
      'absolute',
      'top',
      'center',
      'bottom',
      'inside',
      'outside',
    ];
    return 'mso-position-horizontal:${horizontalModes[position.horizontalMode]};'
        'mso-position-horizontal-relative:${horizontal[position.horizontal]};'
        'mso-position-vertical:${verticalModes[position.verticalMode]};'
        'mso-position-vertical-relative:${vertical[position.vertical]};'
        '${_officeArtVmlWrapDistances(drawing)}';
  }

  String _officeArtVmlWrapOrigins(LegacyWordDrawing drawing) {
    final position = _officeArtPosition(drawing);
    const origins = ['margin', 'page', 'text'];
    // w10:wrap only accepts margin/page/text; the VML style above carries
    // character/line without inventing invalid ST_Horizontal/VerticalAnchor.
    return '${position.horizontal < 3 ? ' anchorx="${origins[position.horizontal]}"' : ''}'
        '${position.vertical < 3 ? ' anchory="${origins[position.vertical]}"' : ''}';
  }

  void _officeArtDrawingPosition(
    LegacyWordDrawing drawing, {
    int? horizontalOffsetEmu,
    int? verticalOffsetEmu,
  }) {
    final position = _officeArtPosition(drawing);
    const horizontal = ['margin', 'page', 'column', 'character'];
    const vertical = ['margin', 'page', 'paragraph', 'line'];
    const horizontalModes = [
      '',
      'left',
      'center',
      'right',
      'inside',
      'outside',
    ];
    const verticalModes = ['', 'top', 'center', 'bottom', 'inside', 'outside'];
    void axis(String name, String origin, int mode, String align, int offset) {
      _xml.add('<wp:position$name relativeFrom="$origin">');
      _xml.add(
        mode == 0
            ? '<wp:posOffset>$offset</wp:posOffset>'
            : '<wp:align>$align</wp:align>',
      );
      _xml.add('</wp:position$name>');
    }

    axis(
      'H',
      horizontal[position.horizontal],
      position.horizontalMode,
      horizontalModes[position.horizontalMode],
      horizontalOffsetEmu ?? drawing.leftTwips * 635,
    );
    axis(
      'V',
      vertical[position.vertical],
      position.verticalMode,
      verticalModes[position.verticalMode],
      verticalOffsetEmu ?? drawing.topTwips * 635,
    );
  }
}
