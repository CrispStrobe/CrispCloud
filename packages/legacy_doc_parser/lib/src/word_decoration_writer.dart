// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

extension _WordDecorations on _StructuredWordWriter {
  String _underlineValue(LegacyWordCharacterStyle style) {
    if (!style.underline) return 'none';
    final value = style.underlineStyle ?? 'single';
    if (!const {
      'none',
      'single',
      'words',
      'double',
      'dotted',
      'thick',
      'dash',
      'dotDash',
      'dotDotDash',
      'wave',
      'dottedHeavy',
      'dashedHeavy',
      'dashDotHeavy',
      'dashDotDotHeavy',
      'wavyHeavy',
      'dashLong',
      'wavyDouble',
      'dashLongHeavy',
    }.contains(value)) {
      throw const FormatException('Invalid Word underline style.');
    }
    return value;
  }

  void _paragraphDecorations(
    LegacyWordParagraphStyle style,
    _BoundedWordXml xml,
    int? cp,
  ) {
    final bar = style.borders[LegacyWordBorderSide.bar];
    if (bar != null) {
      // MS-DOC paragraph bar borders have no effect. Activating w:bar would
      // change the source appearance, so retain the stored record as metadata.
      _evidenceRecords.add({
        'kind': 'inactiveParagraphBarBorder',
        'story': _storyId,
        'cp': cp,
        'rawType': bar.rawType,
        'style': bar.style,
        'widthEighthPoints': bar.widthEighthPoints,
        'colorHex': bar.colorHex,
        'spacingPoints': bar.spacingPoints,
        'shadow': bar.shadow,
        'frame': bar.frame,
        'reason': 'paragraph bar border has no effect in the source format',
      });
    }
    final active = LegacyWordBorderSide.values.where(
      (side) =>
          side != LegacyWordBorderSide.bar && style.borders.containsKey(side),
    );
    if (active.isNotEmpty) {
      xml.add('<w:pBdr>');
      for (final side in active) {
        final border = style.borders[side]!;
        if (!_wordBorderStyles.contains(border.style) ||
            border.widthEighthPoints < 0 ||
            border.widthEighthPoints > 255 ||
            border.spacingPoints < 0 ||
            border.spacingPoints > 31) {
          throw const FormatException('Invalid Word paragraph border.');
        }
        final shadow =
            border.shadow &&
            side != LegacyWordBorderSide.top &&
            side != LegacyWordBorderSide.left;
        final frame =
            border.frame &&
            (side == LegacyWordBorderSide.right ||
                side == LegacyWordBorderSide.bottom);
        xml.add(
          '<w:${side.name} w:val="${border.style}" '
          'w:sz="${border.widthEighthPoints}" w:space="${border.spacingPoints}" '
          'w:color="${border.colorHex == null ? 'auto' : _StructuredWordWriter._color(border.colorHex!)}" '
          'w:shadow="${shadow ? 1 : 0}" w:frame="${frame ? 1 : 0}"/>',
        );
      }
      xml.add('</w:pBdr>');
    }
    if (style.shading != null) _shading(style.shading!, xml, 'paragraph', cp);
    if (style.tabs.isNotEmpty) {
      if (style.tabs.length > 64) _tooComplex();
      final tabs = [...style.tabs]
        ..sort((a, b) => a.positionTwips.compareTo(b.positionTwips));
      final positions = <int>{};
      xml.add('<w:tabs>');
      for (final tab in tabs) {
        if (tab.positionTwips < -31680 ||
            tab.positionTwips > 31680 ||
            !positions.add(tab.positionTwips)) {
          throw const FormatException('Invalid or duplicate Word tab stop.');
        }
        final alignment = tab.alignment == LegacyWordTabAlignment.list
            ? 'num'
            : tab.alignment.name;
        xml.add(
          '<w:tab w:val="$alignment" w:leader="${tab.leader.name}" '
          'w:pos="${tab.positionTwips}"/>',
        );
      }
      xml.add('</w:tabs>');
    }
  }

  void _shading(
    LegacyWordShading shading,
    _BoundedWordXml xml,
    String scope,
    int? cp,
  ) {
    final pattern = shading.pattern;
    if (pattern == null) {
      _evidenceRecords.add({
        'kind': 'shading',
        'scope': scope,
        'story': _storyId,
        'cp': cp,
        'rawPattern': shading.rawPattern,
        'foregroundHex': shading.foregroundHex,
        'backgroundHex': shading.backgroundHex,
        'reason': 'source shading has no exact WordprocessingML pattern',
      });
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
      return;
    }
    if (!_wordShadingPatterns.contains(pattern)) {
      throw const FormatException('Invalid Word shading pattern.');
    }
    xml.add(
      '<w:shd w:val="$pattern" '
      'w:color="${shading.foregroundHex == null ? 'auto' : _StructuredWordWriter._color(shading.foregroundHex!)}" '
      'w:fill="${shading.backgroundHex == null ? 'auto' : _StructuredWordWriter._color(shading.backgroundHex!)}"/>',
    );
  }
}

const _wordBorderStyles = {
  'nil',
  'none',
  'single',
  'thick',
  'double',
  'dotted',
  'dashed',
  'dotDash',
  'dotDotDash',
  'triple',
  'thinThickSmallGap',
  'thickThinSmallGap',
  'thinThickThinSmallGap',
  'thinThickMediumGap',
  'thickThinMediumGap',
  'thinThickThinMediumGap',
  'thinThickLargeGap',
  'thickThinLargeGap',
  'thinThickThinLargeGap',
  'wave',
  'doubleWave',
  'dashSmallGap',
  'dashDotStroked',
  'threeDEmboss',
  'threeDEngrave',
  'outset',
  'inset',
};

const _wordShadingPatterns = {
  'nil',
  'clear',
  'solid',
  'horzStripe',
  'vertStripe',
  'reverseDiagStripe',
  'diagStripe',
  'horzCross',
  'diagCross',
  'thinHorzStripe',
  'thinVertStripe',
  'thinReverseDiagStripe',
  'thinDiagStripe',
  'thinHorzCross',
  'thinDiagCross',
  'pct5',
  'pct10',
  'pct12',
  'pct15',
  'pct20',
  'pct25',
  'pct30',
  'pct35',
  'pct37',
  'pct40',
  'pct45',
  'pct50',
  'pct55',
  'pct60',
  'pct62',
  'pct65',
  'pct70',
  'pct75',
  'pct80',
  'pct85',
  'pct87',
  'pct90',
  'pct95',
};
