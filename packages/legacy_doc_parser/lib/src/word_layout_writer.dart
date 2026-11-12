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
      if (layout.lineNumberStart > 32768) {
        // Valid unsigned DOC data can exceed Word's documented native limit.
        // Retain it, but do not call the resulting layout fully interoperable.
        limitations.add(LegacyWordConversionLimitation.partialFormatting);
      }
      _xml.add(
        '<w:lnNumType w:countBy="${layout.lineNumberInterval}" '
        // Word interprets start as the count skipped (MS-OI29500 2.1.215),
        // matching SLnnMin. The public model exposes the displayed number.
        'w:start="${layout.lineNumberStart - 1}" w:distance="${layout.lineNumberDistanceTwips}" '
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

  void _sectionNotes(LegacyWordSection section, {required bool historical}) {
    final layout = section.layout;
    for (final (kind, numbering, position) in [
      ('footnote', layout.footnoteNumbering, layout.footnotePosition.name),
      ('endnote', layout.endnoteNumbering, layout.endnotePosition?.name),
    ]) {
      if (numbering.start < 0 || numbering.start > 16383) {
        throw const FormatException('Invalid Word note numbering start.');
      }
      final format = numbering.format;
      if (format != null &&
          (format == 'bullet' ||
              (format != 'none' &&
                  !legacyWordMsonfcFormats.contains(format)))) {
        throw const FormatException('Invalid Word note numbering format.');
      }
      if (numbering.usesDecimalFallback && format != 'decimal') {
        throw const FormatException('Invalid Word note numbering fallback.');
      }
      if (format == null || numbering.usesDecimalFallback) {
        limitations.add(LegacyWordConversionLimitation.partialFormatting);
        limitations.add(LegacyWordConversionLimitation.notesComments);
        if (_evidenceRecords.length >= 20000) _tooComplex();
        _evidenceRecords.add({
          'kind': 'noteNumberFormat',
          'noteKind': kind,
          'sectionStartCp': section.startCp,
          'sectionEndCp': section.endCp,
          'historical': historical,
          'sourceFormatCode': numbering.sourceFormatCode,
          'format': format,
          'usesDecimalFallback': numbering.usesDecimalFallback,
        });
      }
      _xml.add('<w:${kind}Pr>');
      if (position != null) _xml.add('<w:pos w:val="$position"/>');
      if (format != null) _xml.add('<w:numFmt w:val="$format"/>');
      _xml.add(
        '<w:numStart w:val="${numbering.start}"/>'
        '<w:numRestart w:val="${numbering.restart.name}"/></w:${kind}Pr>',
      );
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
