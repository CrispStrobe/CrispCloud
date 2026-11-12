// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

extension _WordTableTextWriter on _StructuredWordWriter {
  void _tableTextEvidence(
    int id,
    LegacyWordTableTextFormat format,
    LegacyWordTableCondition? condition,
  ) {
    if (format.characterProperties.contains(
      LegacyWordTableCharacterProperty.highlight,
    )) {
      // CT_RPrBase/StyleRunProperties excludes highlight. MS-DOC UpxChpx
      // likewise excludes properties preserved across CIstd. Keep an
      // encountered value on resolved runs without writing invalid style XML.
      _evidenceRecords.add({
        'kind': 'tableStyleDirectOnlyProperty',
        'tableStyleId': id,
        'condition': condition?.name,
        'property': 'highlight',
        'colorHex': format.character.highlightHex,
        'reason':
            'Highlight is not allowed in native style run properties; '
            'the encountered source value is applied to resolved runs.',
      });
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
    }
    for (final entry in format.relativeCharacterToggles.entries) {
      if (entry.value != 0x80 && entry.value != 0x81) {
        throw const FormatException('Invalid relative table text toggle.');
      }
      _evidenceRecords.add({
        'kind': 'tableTextRelativeToggle',
        'tableStyleId': id,
        'condition': condition?.name,
        'property': entry.key.name,
        'sourceOperand': entry.value,
        'reason':
            'Resolved before run segmentation; overlapping conditional '
            'source toggles have no single context-free native rule.',
      });
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
    }
  }

  void _tableTextProperties(
    LegacyWordTableTextFormat format,
    _BoundedWordXml xml,
  ) {
    if (format.paragraphProperties.isNotEmpty) {
      final style = format.paragraph, layout = style.layout;
      final mask = format.paragraphProperties;
      bool has(String key) => mask.any((property) => property.name == key);
      void flag(String key, String tag, bool? value) {
        if (has(key) && value != null) {
          xml.add('<w:$tag w:val="${value ? 1 : 0}"/>');
        }
      }

      xml.add('<w:pPr>');
      flag('keepNext', 'keepNext', style.keepNext);
      flag('keepTogether', 'keepLines', style.keepTogether);
      flag('pageBreakBefore', 'pageBreakBefore', style.pageBreakBefore);
      flag('widowControl', 'widowControl', layout.widowControl);
      flag(
        'suppressLineNumbers',
        'suppressLineNumbers',
        layout.suppressLineNumbers,
      );
      _paragraphDecorations(
        LegacyWordParagraphStyle(
          borders: has('borders') ? style.borders : const {},
          shading: has('shading') ? style.shading : null,
          tabs: has('tabs') ? style.tabs : const [],
        ),
        xml,
        null,
      );
      flag(
        'suppressAutoHyphens',
        'suppressAutoHyphens',
        layout.suppressAutoHyphens,
      );
      flag('kinsoku', 'kinsoku', layout.kinsoku);
      flag('wordWrap', 'wordWrap', layout.wordWrap);
      flag('overflowPunctuation', 'overflowPunct', layout.overflowPunctuation);
      flag(
        'autoSpaceEastAsianLatin',
        'autoSpaceDE',
        layout.autoSpaceEastAsianLatin,
      );
      flag(
        'autoSpaceEastAsianNumbers',
        'autoSpaceDN',
        layout.autoSpaceEastAsianNumbers,
      );
      flag('rightToLeft', 'bidi', layout.rightToLeft);
      if (has('before') ||
          has('after') ||
          has('lineSpacing') ||
          has('spaceBeforeAuto') ||
          has('spaceAfterAuto')) {
        xml.add('<w:spacing');
        if (has('before')) xml.add(' w:before="${style.spaceBeforeTwips}"');
        if (has('after')) xml.add(' w:after="${style.spaceAfterTwips}"');
        if (has('spaceBeforeAuto')) {
          xml.add(' w:beforeAutospacing="${layout.spaceBeforeAuto ? 1 : 0}"');
        }
        if (has('spaceAfterAuto')) {
          xml.add(' w:afterAutospacing="${layout.spaceAfterAuto ? 1 : 0}"');
        }
        if (has('lineSpacing') && style.lineSpacingValue != null) {
          final line = style.lineSpacingValue!;
          final rule = style.lineSpacingMultiple
              ? 'auto'
              : line < 0
              ? 'exact'
              : 'atLeast';
          xml.add(' w:line="${line.abs()}" w:lineRule="$rule"');
        }
        xml.add('/>');
      }
      if (has('leftIndent') || has('rightIndent') || has('firstIndent')) {
        xml.add('<w:ind');
        if (has('leftIndent')) xml.add(' w:left="${style.leftIndentTwips}"');
        if (has('rightIndent')) xml.add(' w:right="${style.rightIndentTwips}"');
        if (has('firstIndent')) {
          final first = style.firstLineIndentTwips;
          xml.add(' w:${first < 0 ? 'hanging' : 'firstLine'}="${first.abs()}"');
        }
        xml.add('/>');
      }
      flag('contextualSpacing', 'contextualSpacing', layout.contextualSpacing);
      flag('mirrorIndents', 'mirrorIndents', layout.mirrorIndents);
      if (has('alignment')) {
        xml.add(
          '<w:jc w:val="${style.alignment == LegacyWordAlignment.justify ? 'both' : style.alignment.name}"/>',
        );
      }
      if (has('outline')) {
        xml.add(
          '<w:outlineLvl w:val="${style.headingLevel == null ? 9 : style.headingLevel! - 1}"/>',
        );
      }
      xml.add('</w:pPr>');
    }
    if (format.characterProperties.isEmpty) return;
    final style = format.character, mask = format.characterProperties;
    bool has(String key) =>
        mask.any((property) => property.name == key) &&
        !format.relativeCharacterToggles.keys.any(
          (property) => property.name == key,
        );
    void flag(String key, String tag, bool value) {
      if (has(key)) xml.add('<w:$tag w:val="${value ? 1 : 0}"/>');
    }

    xml.add('<w:rPr>');
    _runFonts(style, xml, include: has);
    flag('bold', 'b', style.bold);
    flag('italic', 'i', style.italic);
    flag('allCaps', 'caps', style.allCaps);
    flag('smallCaps', 'smallCaps', style.smallCaps);
    flag('strike', 'strike', style.strike);
    flag('doubleStrike', 'dstrike', style.doubleStrike);
    flag('hidden', 'vanish', style.hidden);
    if (has('color')) {
      xml.add(
        '<w:color w:val="${style.colorHex == null ? 'auto' : _StructuredWordWriter._color(style.colorHex!)}"/>',
      );
    }
    if (has('spacing')) {
      xml.add('<w:spacing w:val="${style.spacingTwips ?? 0}"/>');
    }
    if (has('kerning')) {
      xml.add(
        '<w:kern w:val="${_StructuredWordWriter._kerningThreshold(style)}"/>',
      );
    }
    if (has('position')) {
      xml.add('<w:position w:val="${style.positionHalfPoints ?? 0}"/>');
    }
    if (has('fontSize') && style.fontSizeHalfPoints != null) {
      xml.add('<w:sz w:val="${style.fontSizeHalfPoints}"/>');
    }
    if (has('underline')) xml.add('<w:u w:val="${_underlineValue(style)}"/>');
    if (has('verticalAlign')) {
      xml.add('<w:vertAlign w:val="${style.verticalAlign.name}"/>');
    }
    xml.add('</w:rPr>');
  }
}
