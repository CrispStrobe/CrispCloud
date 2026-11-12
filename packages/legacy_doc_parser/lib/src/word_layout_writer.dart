// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

extension _WordLayout on _StructuredWordWriter {
  void _paragraphLayoutBeforeSpacing(LegacyWordParagraphLayout layout) {
    _bool('suppressAutoHyphens', layout.suppressAutoHyphens);
    for (final (name, value) in [
      ('kinsoku', layout.kinsoku),
      // OOXML wordWrap=false also permits breaking inside a Latin word.
      ('wordWrap', layout.wordWrap),
      ('overflowPunct', layout.overflowPunctuation),
      ('autoSpaceDE', layout.autoSpaceEastAsianLatin),
      ('autoSpaceDN', layout.autoSpaceEastAsianNumbers),
    ]) {
      if (value != null) _bool(name, value);
    }
    _bool('bidi', layout.rightToLeft);
  }

  void _sectionNumbering(LegacyWordSectionLayout layout) {
    if (layout.lineNumberInterval < 0 ||
        layout.lineNumberInterval > 100 ||
        layout.lineNumberStart < 1 ||
        layout.lineNumberStart > 65536 ||
        layout.lineNumberDistanceTwips < 0 ||
        layout.lineNumberDistanceTwips > 31680 ||
        layout.pageNumberStart < 0 ||
        layout.pageNumberStart > 2147483646) {
      throw const FormatException('Invalid Word section numbering.');
    }
    if (layout.lineNumberInterval != 0) {
      _xml.add(
        '<w:lnNumType w:countBy="${layout.lineNumberInterval}" '
        'w:start="${layout.lineNumberStart}" w:distance="${layout.lineNumberDistanceTwips}" '
        'w:restart="${layout.lineNumberRestart.name}"/>',
      );
    }
    final format = layout.pageNumberFormat;
    if (format != null &&
        !const {
          'decimal',
          'upperRoman',
          'lowerRoman',
          'upperLetter',
          'lowerLetter',
        }.contains(format)) {
      throw const FormatException('Invalid Word page number format.');
    }
    if (format != null || layout.restartPageNumbering) {
      _xml.add('<w:pgNumType');
      if (format != null) _xml.add(' w:fmt="$format"');
      if (layout.restartPageNumbering) {
        _xml.add(' w:start="${layout.pageNumberStart}"');
      }
      _xml.add('/>');
    }
  }

  void _sectionColumns(LegacyWordSection section) {
    final layout = section.layout;
    if (section.columns < 1 ||
        section.columns > 44 ||
        (!layout.equalColumnWidths &&
            section.columns > 1 &&
            layout.columns.length != section.columns)) {
      throw const FormatException('Invalid Word page columns.');
    }
    _xml.add(
      '<w:cols w:num="${section.columns}" w:equalWidth="${layout.equalColumnWidths ? 1 : 0}" '
      'w:sep="${layout.columnSeparator ? 1 : 0}"',
    );
    _optional('space', section.columnsSpaceTwips);
    _xml.add('>');
    if (!layout.equalColumnWidths) {
      for (final column in layout.columns) {
        if (column.widthTwips < 718 ||
            column.widthTwips > 31680 ||
            column.spaceAfterTwips < 0 ||
            column.spaceAfterTwips > 31680) {
          throw const FormatException('Invalid Word page column dimension.');
        }
        _xml.add(
          '<w:col w:w="${column.widthTwips}" w:space="${column.spaceAfterTwips}"/>',
        );
      }
    }
    _xml.add('</w:cols><w:vAlign w:val="${layout.verticalAlignment.name}"/>');
  }

  void _sectionGrid(LegacyWordSectionLayout layout) {
    final line = layout.gridLinePitchTwips, spacing = layout.gridCharacterSpace;
    if (line != null && (line < 1 || line > 31680) ||
        spacing != null && (spacing < -670925 || spacing > 6488064) ||
        layout.grid != LegacyWordDocumentGrid.none && line == null) {
      throw const FormatException('Invalid Word document grid.');
    }
    if (line == null &&
        spacing == null &&
        layout.grid == LegacyWordDocumentGrid.none) {
      return;
    }
    _xml.add(
      '<w:docGrid w:type="${layout.grid == LegacyWordDocumentGrid.none ? 'default' : layout.grid.name}"',
    );
    _optional('linePitch', line);
    _optional('charSpace', spacing);
    _xml.add('/>');
  }
}
