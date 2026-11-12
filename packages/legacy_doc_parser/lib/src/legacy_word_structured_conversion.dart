// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

/// Creates a separate macro-free DOCX from supported binary Word structure.
/// Resolved character/paragraph properties, basic tables, page sections and
/// supported insertion/deletion runs are emitted as editable WordprocessingML.
/// Unsupported content is disclosed by [LegacyWordStructuredConversion].
LegacyWordStructuredConversion _convertStructuredDocument(
  LegacyWordDocument document, {
  required LegacyWordOutputFormat format,
}) {
  final writer = _StructuredWordWriter(document, format);
  final bytes = writer.convert();
  return LegacyWordStructuredConversion(
    bytes: bytes,
    limitations: writer.limitations.toList(),
    format: format,
    preservedCounts: writer.counts,
    signatureEvidenceParts: writer.signatureEvidenceParts,
  );
}

class _StructuredWordWriter {
  _StructuredWordWriter(this.document, this.format);

  final LegacyWordDocument document;
  final LegacyWordOutputFormat format;
  var _xml = _BoundedWordXml();
  final _package = _OpcPackageWriter();
  var _part = 'word/document.xml';
  var _storyId = 'main';
  final limitations = <LegacyWordConversionLimitation>{
    LegacyWordConversionLimitation.partialFormatting,
  };
  final counts = <String, int>{};
  final signatureEvidenceParts = <String>[];
  final _stories = <String, LegacyWordStory>{};
  final _storyRanges = <(int, int, String)>[];
  final _events = <String, List<_WordInlineEvent>>{};
  final _eventOffsets = <String, int>{};
  final _headerFooters = <int, List<(bool, String, String)>>{};
  final _storyParts = <String, String>{};
  final _numberingIds = <int>{};
  final _fields = <int, LegacyWordField>{};
  final _fieldChildren = <int, List<LegacyWordField>>{};
  final _mediaAssets = <String, LegacyWordImageAsset>{};
  final _mediaParts = <String, String>{};
  final _embeddedParts = <String, String>{};
  final _renderedTextboxes = <String>{};
  final _unplacedTextboxes = <(LegacyWordTextboxReference, LegacyWordStory)>[];
  final _inertStories = <String, String>{};
  final _hiddenContentRanges = <(int, int)>[];
  final _renderingStories = <String>{};
  final _evidenceRecords = <Map<String, Object?>>[];
  var _inlineEventCount = 0;
  var _drawingId = 0;
  final _styles = <int, LegacyWordParagraphStyle>{};
  final _sectionBreaks = <int, LegacyWordSectionBreak>{};
  final _sectionIndices = <int, int>{};
  var _revisionId = 0;
  var _breaks = 0;

  Uint8List convert() {
    _prepareStories();
    _prepareMedia();
    _prepareSemantics();
    _sortEvents();
    _xml.add(_wordDocumentStart);
    var sectionIndex = 0;
    final sections = document.sections;
    for (var i = 0; i < sections.length; i++) {
      if (_sectionIndices.containsKey(sections[i].startCp)) {
        throw const FormatException('Duplicate Word section start.');
      }
      _sectionIndices[sections[i].startCp] = i;
      // MS-DOC sprmSBkc terminates this section. WordprocessingML w:type
      // instead places this section relative to the previous one. Shift only
      // the break type; dimensions/margins stay with their original section.
      _sectionBreaks[sections[i].startCp] = i == 0
          ? LegacyWordSectionBreak.newPage
          : sections[i - 1].breakKind;
    }
    for (final block in document.blocks) {
      // A section boundary must land at the end of a block. Inventing a
      // different position changes pagination; refuse instead of moving it.
      final section = sectionIndex < sections.length
          ? sections[sectionIndex]
          : null;
      if (section != null && section.endCp < block.endCp) {
        throw const FormatException(
          'A Word section splits an unsupported block.',
        );
      }
      final endingSection =
          section != null &&
              section.endCp == block.endCp &&
              sectionIndex < sections.length - 1
          ? section
          : null;
      switch (block) {
        case LegacyWordParagraph():
          _paragraph(block, section: endingSection);
        case LegacyWordTable():
          _table(block);
          if (endingSection != null) {
            _xml.add('<w:p><w:pPr>');
            _section(endingSection);
            _xml.add('</w:pPr></w:p>');
          }
      }
      if (endingSection != null) sectionIndex++;
    }
    if (document.blocks.isEmpty || document.blocks.last is LegacyWordTable) {
      _xml.add('<w:p/>');
    }
    _finishStoryEvents();
    if (sections.isNotEmpty) {
      _section(sections.last);
    } else if (_headerFooters.isNotEmpty) {
      _section(LegacyWordSection(startCp: 0, endCp: _mainEnd));
    }
    _xml.add('</w:body></w:document>');
    _package.addXml(
      'word/document.xml',
      format == LegacyWordOutputFormat.docx ? _docxMainType : _docmMainType,
      _xml,
    );
    _package.relate('', _officeDocumentRelationship, 'word/document.xml');
    _writeAuxiliaryStories();
    _writeNumbering();
    _writeEvidence();
    if (_styles.isNotEmpty) {
      final styles = _styleDefinitions();
      if (_xml.byteEstimate + styles.byteEstimate > kLegacyWordDocxXmlLimit) {
        _tooComplex();
      }
      _package.addXml('word/styles.xml', _stylesType, styles);
      _package.relate(
        'word/document.xml',
        '$_relationshipNamespace/styles',
        'styles.xml',
      );
    }
    _summarizeLimitations();
    return _package.encode();
  }

  void _paragraph(LegacyWordParagraph paragraph, {LegacyWordSection? section}) {
    _countBreak();
    final style = paragraph.style;
    _styles.putIfAbsent(style.styleIndex, () => style);
    _xml.add('<w:p><w:pPr><w:pStyle w:val="Legacy${style.styleIndex}"/>');
    _bool('keepNext', style.keepNext);
    _bool('keepLines', style.keepTogether);
    _bool('pageBreakBefore', style.pageBreakBefore);
    final listId = style.listId?.abs();
    if (listId != null && listId != 0) {
      if (_numberingIds.contains(listId)) {
        _xml.add(
          '<w:numPr><w:ilvl w:val="${style.listLevel ?? 0}"/><w:numId w:val="$listId"/></w:numPr>',
        );
      } else {
        limitations.add(LegacyWordConversionLimitation.fieldsLists);
      }
    }
    _paragraphDecorations(style, _xml, paragraph.startCp);
    _xml.add(
      '<w:spacing w:before="${style.spaceBeforeTwips}" '
      'w:after="${style.spaceAfterTwips}"',
    );
    final line = style.lineSpacingValue;
    if (line != null) {
      final rule = style.lineSpacingMultiple
          ? 'auto'
          : line < 0
          ? 'exact'
          : 'atLeast';
      _xml.add(' w:line="${line.abs()}" w:lineRule="$rule"');
    }
    _xml.add(
      '/><w:ind w:left="${style.leftIndentTwips}" '
      'w:right="${style.rightIndentTwips}"',
    );
    if (style.firstLineIndentTwips < 0) {
      _xml.add(' w:hanging="${-style.firstLineIndentTwips}"');
    } else {
      _xml.add(' w:firstLine="${style.firstLineIndentTwips}"');
    }
    _xml.add(
      '/><w:jc w:val="${style.alignment == LegacyWordAlignment.justify ? 'both' : style.alignment.name}"/>',
    );
    final heading = style.headingLevel;
    _xml.add('<w:outlineLvl w:val="${heading == null ? 9 : heading - 1}"/>');
    if (section != null) _section(section);
    _xml.add('</w:pPr>');
    _emitEventsThrough(paragraph.startCp);
    for (final run in paragraph.runs) {
      _run(run);
    }
    _emitEventsThrough(paragraph.endCp - 1);
    _emitBoundaryClosures(paragraph.endCp);
    _xml.add('</w:p>');
    _count('paragraphs');
  }

  void _table(LegacyWordTable table) {
    _count('tables');
    _xml.add(
      '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>'
      '</w:tblPr>',
    );
    // Use all row edges so differently split rows share a valid table grid.
    final grid = <int>{0};
    var canWriteGrid = table.rows.isNotEmpty;
    for (final row in table.rows) {
      var offset = 0;
      for (final cell in row.cells) {
        final width = cell.widthTwips;
        if (width == null || width <= 0) {
          canWriteGrid = false;
          break;
        }
        offset += width;
        grid.add(offset);
      }
    }
    final edges = grid.toList()..sort();
    final edgeIndices = {for (var i = 0; i < edges.length; i++) edges[i]: i};
    if (canWriteGrid) {
      _xml.add('<w:tblGrid>');
      for (var i = 1; i < edges.length; i++) {
        _xml.add('<w:gridCol w:w="${edges[i] - edges[i - 1]}"/>');
      }
      _xml.add('</w:tblGrid>');
    }
    for (final row in table.rows) {
      _countBreak();
      _xml.add('<w:tr>');
      if (row.isHeader) _xml.add('<w:trPr><w:tblHeader/></w:trPr>');
      var offset = 0;
      for (final cell in row.cells) {
        _countBreak();
        _count('cells');
        _xml.add('<w:tc><w:tcPr>');
        final width = cell.widthTwips;
        if (width != null && width > 0) {
          _xml.add('<w:tcW w:w="$width" w:type="dxa"/>');
          if (canWriteGrid) {
            final start = edgeIndices[offset]!;
            final end = edgeIndices[offset + width]!;
            if (end - start > 1) {
              _xml.add('<w:gridSpan w:val="${end - start}"/>');
            }
          }
          offset += width;
        }
        if (cell.mergeStart || cell.mergeContinue) {
          _xml.add(
            '<w:hMerge w:val="${cell.mergeStart ? 'restart' : 'continue'}"/>',
          );
        }
        if (cell.verticalMergeStart || cell.verticalMergeContinue) {
          _xml.add(
            '<w:vMerge w:val="${cell.verticalMergeStart ? 'restart' : 'continue'}"/>',
          );
        }
        if (cell.shading != null) {
          _shading(
            cell.shading!,
            _xml,
            'tableCell',
            cell.paragraphs.isEmpty ? null : cell.paragraphs.first.startCp,
          );
        }
        _xml.add('</w:tcPr>');
        if (cell.paragraphs.isEmpty) _xml.add('<w:p/>');
        for (final paragraph in cell.paragraphs) {
          _paragraph(paragraph);
        }
        _xml.add('</w:tc>');
      }
      _xml.add('</w:tr>');
    }
    _xml.add('</w:tbl>');
  }

  void _writeRun(LegacyWordRun run) {
    if (run.inserted) _revisionStart('ins', run);
    if (run.deleted) _revisionStart('del', run);
    _xml.add('<w:r><w:rPr>');
    final style = run.style;
    final font = style.fontName;
    if (font != null && font.isNotEmpty) {
      _xml.add('<w:rFonts w:ascii="');
      _xml.text(font, attribute: true);
      _xml.add('" w:hAnsi="');
      _xml.text(font, attribute: true);
      _xml.add('" w:eastAsia="');
      _xml.text(font, attribute: true);
      _xml.add('"/>');
    }
    _bool('b', style.bold);
    _bool('i', style.italic);
    _bool('caps', style.allCaps);
    _bool('smallCaps', style.smallCaps);
    _bool('strike', style.strike);
    _bool('dstrike', style.doubleStrike);
    _bool('vanish', style.hidden);
    if (style.colorHex != null) {
      _xml.add('<w:color w:val="${_color(style.colorHex!)}"/>');
    }
    if (style.spacingTwips != null) {
      _xml.add('<w:spacing w:val="${style.spacingTwips}"/>');
    }
    if (style.positionHalfPoints != null) {
      _xml.add('<w:position w:val="${style.positionHalfPoints}"/>');
    }
    if (style.fontSizeHalfPoints != null) {
      _xml.add('<w:sz w:val="${style.fontSizeHalfPoints}"/>');
    }
    final highlight = style.highlightHex;
    final highlightName = highlight == null
        ? null
        : _highlights[_color(highlight)];
    if (highlightName != null) {
      _xml.add('<w:highlight w:val="$highlightName"/>');
    }
    _xml.add('<w:u w:val="${_underlineValue(style)}"/>');
    if (highlight != null && highlightName == null) {
      _xml.add(
        '<w:shd w:val="clear" w:color="auto" w:fill="${_color(highlight)}"/>',
      );
    }
    _xml.add('<w:vertAlign w:val="${style.verticalAlign.name}"/>');
    _xml.add('</w:rPr>');
    var start = 0;
    final text = run.text;
    for (var i = 0; i <= text.length; i++) {
      final code = i == text.length ? -1 : text.codeUnitAt(i);
      if (code != -1 && code != 9 && code != 10 && code != 12) continue;
      if (i > start) {
        final tag = run.deleted ? 'delText' : 't';
        _xml.add('<w:$tag xml:space="preserve">');
        _xml.text(text.substring(start, i));
        _xml.add('</w:$tag>');
      }
      if (code != -1) {
        _countBreak();
        _xml.add(switch (code) {
          9 => '<w:tab/>',
          12 => '<w:br w:type="page"/>',
          _ => '<w:br/>',
        });
      }
      start = i + 1;
    }
    _xml.add('</w:r>');
    if (run.deleted) _xml.add('</w:del>');
    if (run.inserted) _xml.add('</w:ins>');
  }

  void _revisionStart(String tag, LegacyWordRun run) {
    _xml.add('<w:$tag w:id="${_revisionId++}" w:author="');
    _xml.text(run.revisionAuthor ?? '', attribute: true);
    _xml.add('"');
    if (run.revisionTime != null) {
      // DTTM carries a wall-clock date/time without a timezone. xsd:dateTime
      // allows an unspecified zone; emitting Z would invent UTC metadata.
      final time = run.revisionTime!;
      String two(int value) => value.toString().padLeft(2, '0');
      _xml.add(
        ' w:date="${time.year.toString().padLeft(4, '0')}-'
        '${two(time.month)}-${two(time.day)}T'
        '${two(time.hour)}:${two(time.minute)}:00"',
      );
    }
    _xml.add('>');
  }

  void _section(LegacyWordSection section) {
    final breakBefore =
        _sectionBreaks[section.startCp] ?? LegacyWordSectionBreak.newPage;
    _xml.add('<w:sectPr>');
    final sectionIndex = _sectionIndices[section.startCp] ?? 0;
    final references = _headerFooters[sectionIndex] ?? const [];
    for (final reference in references) {
      _xml.add(
        '<w:${reference.$1 ? 'header' : 'footer'}Reference w:type="${reference.$2}" r:id="${reference.$3}"/>',
      );
    }
    _xml.add(
      '<w:type w:val="${switch (breakBefore) {
        LegacyWordSectionBreak.continuous => 'continuous',
        LegacyWordSectionBreak.newColumn => 'nextColumn',
        LegacyWordSectionBreak.newPage => 'nextPage',
        LegacyWordSectionBreak.evenPage => 'evenPage',
        LegacyWordSectionBreak.oddPage => 'oddPage',
      }}"/>',
    );
    if (section.pageWidthTwips != null || section.pageHeightTwips != null) {
      _xml.add('<w:pgSz');
      _optional('w', section.pageWidthTwips);
      _optional('h', section.pageHeightTwips);
      _xml.add(' w:orient="${section.landscape ? 'landscape' : 'portrait'}"/>');
    }
    final margins = [
      section.marginTopTwips,
      section.marginRightTwips,
      section.marginBottomTwips,
      section.marginLeftTwips,
      section.headerDistanceTwips,
      section.footerDistanceTwips,
      section.gutterTwips,
    ];
    if (margins.any((value) => value != null)) {
      // All seven attributes are required by CT_PageMar. MS-DOC defaults
      // apply only to values that the source did not override.
      _xml.add(
        '<w:pgMar w:top="${section.marginTopTwips ?? 1440}" '
        'w:right="${section.marginRightTwips ?? 1800}" '
        'w:bottom="${section.marginBottomTwips ?? 1440}" '
        'w:left="${section.marginLeftTwips ?? 1800}" '
        'w:header="${section.headerDistanceTwips ?? 720}" '
        'w:footer="${section.footerDistanceTwips ?? 720}" '
        'w:gutter="${section.gutterTwips ?? 0}"/>',
      );
    }
    _xml.add('<w:cols w:num="${section.columns}"');
    _optional('space', section.columnsSpaceTwips);
    _xml.add('/>');
    if (section.titlePage) {
      _xml.add('<w:titlePg/>');
    }
    _xml.add('</w:sectPr>');
    _count('sections');
  }

  void _optional(String name, int? value) {
    if (value != null) _xml.add(' w:$name="$value"');
  }

  void _bool(String name, bool value) =>
      _xml.add('<w:$name w:val="${value ? 1 : 0}"/>');

  void _countBreak() {
    if (++_breaks > kLegacyWordDocxBreakLimit) _tooComplex();
  }

  void _count(String key, [int amount = 1]) =>
      counts[key] = (counts[key] ?? 0) + amount;

  _BoundedWordXml _styleDefinitions() {
    final xml = _BoundedWordXml();
    xml.add(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/'
      'wordprocessingml/2006/main">',
    );
    for (final entry in _styles.entries) {
      xml.add(
        '<w:style w:type="paragraph" w:styleId="Legacy${entry.key}">'
        '<w:name w:val="',
      );
      xml.text(
        entry.value.styleName ?? 'Imported style ${entry.key}',
        attribute: true,
      );
      xml.add('"/>');
      // The model resolves direct formatting as well as stylesheet values.
      // Do not turn the first paragraph's direct outline/formatting into a
      // shared style that could affect other paragraphs with the same index.
      xml.add('</w:style>');
    }
    xml.add('</w:styles>');
    return xml;
  }

  static String _color(String value) {
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
      throw const LegacyWordConversionException(
        LegacyWordConversionIssue.invalidText,
      );
    }
    return value.toUpperCase();
  }

  static const _highlights = {
    '000000': 'black',
    '0000FF': 'blue',
    '00FFFF': 'cyan',
    '00FF00': 'green',
    'FF00FF': 'magenta',
    'FF0000': 'red',
    'FFFF00': 'yellow',
    'FFFFFF': 'white',
    '000080': 'darkBlue',
    '008080': 'darkCyan',
    '008000': 'darkGreen',
    '800080': 'darkMagenta',
    '800000': 'darkRed',
    '808000': 'darkYellow',
    '808080': 'darkGray',
    'C0C0C0': 'lightGray',
  };
}

/// Bounds markup expansion while writing, including escaped text/attributes.
class _BoundedWordXml {
  final _buffer = StringBuffer();
  var byteEstimate = 0;

  void add(String ascii) {
    byteEstimate += ascii.length;
    if (byteEstimate > kLegacyWordDocxXmlLimit) _tooComplex();
    _buffer.write(ascii);
  }

  void text(String value, {bool attribute = false}) {
    for (final rune in value.runes) {
      if (rune < 0x20 ||
          (rune >= 0xd800 && rune <= 0xdfff) ||
          rune == 0xfffe ||
          rune == 0xffff) {
        throw const LegacyWordConversionException(
          LegacyWordConversionIssue.invalidText,
        );
      }
      switch (rune) {
        case 0x26:
          add('&amp;');
        case 0x3c:
          add('&lt;');
        case 0x3e:
          add('&gt;');
        case 0x22 when attribute:
          add('&quot;');
        case 0x27 when attribute:
          add('&apos;');
        default:
          byteEstimate += rune < 0x80
              ? 1
              : rune < 0x800
              ? 2
              : rune < 0x10000
              ? 3
              : 4;
          if (byteEstimate > kLegacyWordDocxXmlLimit) _tooComplex();
          _buffer.writeCharCode(rune);
      }
    }
  }

  @override
  String toString() => _buffer.toString();
}

Never _tooComplex() => throw const LegacyWordConversionException(
  LegacyWordConversionIssue.tooComplex,
);
