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
  final _commentsById = <int, LegacyWordCommentReference>{};
  final _commentParagraphIds = <String, String>{};
  var _commentParagraphSequence = 0;
  final _storyRanges = <(int, int, String)>[];
  final _events = <String, List<_WordInlineEvent>>{};
  final _eventOffsets = <String, int>{};
  final _headerFooters = <int, List<(bool, String, String)>>{};
  final _storyParts = <String, String>{};
  final _numberingIds = <int>{};
  final _numberingReferences = <int, int>{};
  final _resolvedParagraphNumbering = <LegacyWordParagraph, int>{};
  final _numberingInstances = <int, _WordNumberingInstance>{};
  final _tableStyleDefinitions = <int, LegacyWordTableStyle>{};
  var _tableDepth = 0;
  final _fields = <int, LegacyWordField>{};
  final _fieldChildren = <int, List<LegacyWordField>>{};
  final _mediaAssets = <String, LegacyWordImageAsset>{};
  final _mediaParts = <String, String>{};
  final _embeddedParts = <String, String>{};
  final _renderedTextboxes = <(String, String?)>{};
  final _unplacedTextboxes = <(LegacyWordTextboxReference, LegacyWordStory)>[];
  final _inertStories = <String, String>{};
  final _hiddenContentRanges = <(int, int)>[];
  final _renderingStories = <String>{};
  final _evidenceRecords = <Map<String, Object?>>[];
  var _inlineEventCount = 0;
  var _drawingId = 0;
  final _styles = <int, LegacyWordParagraphStyle>{};
  final _sectionBreaks = <LegacyWordSection, LegacyWordSectionBreak>{};
  final _sectionIndices = <LegacyWordSection, int>{};
  var _revisionId = 0;
  var _breaks = 0;

  Uint8List convert() {
    _prepareTableStyleDefinitions();
    _prepareStories();
    _prepareNumbering();
    _prepareMedia();
    _prepareSemantics();
    _sortEvents();
    _xml.add(_wordDocumentStart);
    var sectionIndex = 0;
    final sections = document.sections;
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      final emptyInitial =
          i == 0 &&
          sections.length > 1 &&
          section.startCp == 0 &&
          section.endCp == 0;
      if (_sectionIndices.containsKey(section) ||
          section.startCp < 0 ||
          (section.endCp <= section.startCp && !emptyInitial) ||
          (i > 0 && section.startCp != sections[i - 1].endCp)) {
        throw const FormatException('Invalid or duplicate Word section range.');
      }
      _sectionIndices[section] = i;
      // MS-DOC sprmSBkc terminates this section. WordprocessingML w:type
      // instead places this section relative to the previous one. Shift only
      // the break type; dimensions/margins stay with their original section.
      _sectionBreaks[section] = i == 0
          ? LegacyWordSectionBreak.newPage
          : sections[i - 1].breakKind;
    }
    for (final block in document.blocks) {
      if (sectionIndex == 0 &&
          sections.length > 1 &&
          sections.first.endCp == 0) {
        _xml.add('<w:p><w:pPr>');
        _section(sections.first);
        _xml.add('</w:pPr></w:p>');
        _evidenceRecords.add({
          'kind': 'emptyInitialSection',
          'sourceCp': 0,
          'reason':
              'native zero-length section retained as an empty OOXML section; exact reflow not claimed',
        });
        sectionIndex++;
      }
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
    if (_styles.isNotEmpty || document.tableStyles.isNotEmpty) {
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
    // Style serialization can add preservation counts and fallback evidence.
    // Serialize that evidence only once every native style has been emitted.
    _writeEvidence();
    _summarizeLimitations();
    return _package.encode();
  }

  void _paragraph(LegacyWordParagraph paragraph, {LegacyWordSection? section}) {
    _countBreak();
    final style = paragraph.style;
    _styles.putIfAbsent(style.styleIndex, () => style);
    _xml.add('<w:p');
    _revisionSaveAttribute('rsidP', paragraph.revisionSaveId);
    _revisionSaveAttribute('rsidR', paragraph.mark?.insertionRevision?.saveId);
    _revisionSaveAttribute('rsidDel', paragraph.mark?.deletionRevision?.saveId);
    _revisionSaveAttribute('rsidRPr', paragraph.mark?.formattingSaveId);
    _commentParagraphAttribute();
    _xml.add('><w:pPr><w:pStyle w:val="Legacy${style.styleIndex}"/>');
    _bool('keepNext', style.keepNext);
    _bool('keepLines', style.keepTogether);
    _bool('pageBreakBefore', style.pageBreakBefore);
    _bool('widowControl', style.layout.widowControl);
    _paragraphNumbering(paragraph);
    _bool('suppressLineNumbers', style.layout.suppressLineNumbers);
    _paragraphDecorations(style, _xml, paragraph.startCp);
    _paragraphLayoutBeforeSpacing(style.layout);
    _xml.add(
      '<w:spacing w:before="${style.spaceBeforeTwips}" '
      'w:after="${style.spaceAfterTwips}"',
    );
    if (style.layout.spaceBeforeAuto) _xml.add(' w:beforeAutospacing="1"');
    if (style.layout.spaceAfterAuto) _xml.add(' w:afterAutospacing="1"');
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
    _xml.add('/>');
    _bool('contextualSpacing', style.layout.contextualSpacing);
    _bool('mirrorIndents', style.layout.mirrorIndents);
    _xml.add(
      '<w:jc w:val="${style.alignment == LegacyWordAlignment.justify ? 'both' : style.alignment.name}"/>',
    );
    final heading = style.headingLevel;
    _xml.add('<w:outlineLvl w:val="${heading == null ? 9 : heading - 1}"/>');
    _paragraphMarkProperties(paragraph.mark, paragraph.endCp - 1);
    if (section != null) _section(section);
    _paragraphFormattingRevision(paragraph);
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

  void _writeRun(LegacyWordRun run) {
    if (run.inserted) _revisionStart('ins', run);
    if (run.deleted) _revisionStart('del', run);
    _xml.add('<w:r');
    _revisionSaveAttribute('rsidR', run.insertionRevision?.saveId);
    _revisionSaveAttribute('rsidDel', run.deletionRevision?.saveId);
    _revisionSaveAttribute('rsidRPr', run.formattingSaveId);
    _xml.add('><w:rPr>');
    _runStyle(run.style);
    _characterFormattingRevision(run.formattingRevision, run.startCp);
    _xml.add('</w:rPr>');
    _writeRunText(run);
    _xml.add('</w:r>');
    if (run.deleted) _xml.add('</w:del>');
    if (run.inserted) _xml.add('</w:ins>');
  }

  void _runStyle(LegacyWordCharacterStyle style, {bool resetDefaults = false}) {
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
    if (style.colorHex != null || resetDefaults) {
      _xml.add(
        '<w:color w:val="${style.colorHex == null ? 'auto' : _color(style.colorHex!)}"/>',
      );
    }
    if (style.spacingTwips != null || resetDefaults) {
      _xml.add('<w:spacing w:val="${style.spacingTwips ?? 0}"/>');
    }
    _xml.add('<w:kern w:val="${_kerningThreshold(style)}"/>');
    if (style.positionHalfPoints != null || resetDefaults) {
      _xml.add('<w:position w:val="${style.positionHalfPoints ?? 0}"/>');
    }
    if (style.fontSizeHalfPoints != null || resetDefaults) {
      _xml.add('<w:sz w:val="${style.fontSizeHalfPoints ?? 20}"/>');
    }
    final highlight = style.highlightHex;
    final highlightName = highlight == null
        ? null
        : _highlights[_color(highlight)];
    if (highlightName != null || resetDefaults) {
      _xml.add('<w:highlight w:val="${highlightName ?? 'none'}"/>');
    }
    _xml.add('<w:u w:val="${_underlineValue(style)}"/>');
    if (highlight != null && highlightName == null) {
      _xml.add(
        '<w:shd w:val="clear" w:color="auto" w:fill="${_color(highlight)}"/>',
      );
    }
    _xml.add('<w:vertAlign w:val="${style.verticalAlign.name}"/>');
  }

  static int _kerningThreshold(LegacyWordCharacterStyle style) {
    final value = style.kerningThresholdHalfPoints;
    if (value < 0 || value > 3276) {
      throw const FormatException('Invalid Word kerning threshold.');
    }
    return value;
  }

  void _writeRunText(LegacyWordRun run) {
    var start = 0;
    final text = run.text;
    for (var i = 0; i <= text.length; i++) {
      final code = i == text.length ? -1 : text.codeUnitAt(i);
      if (code != -1 && code != 9 && code != 10 && code != 12 && code != 14) {
        continue;
      }
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
          14 => '<w:br w:type="column"/>',
          _ => '<w:br/>',
        });
      }
      start = i + 1;
    }
  }

  void _revisionStart(String tag, LegacyWordRun run) {
    final info =
        (tag == 'del' ? run.deletionRevision : run.insertionRevision) ??
        LegacyWordRevisionInfo(
          author: run.revisionAuthor,
          time: run.revisionTime,
        );
    _revisionElementStart(tag, info);
  }

  void _section(LegacyWordSection section) {
    final breakBefore =
        _sectionBreaks[section] ?? LegacyWordSectionBreak.newPage;
    _xml.add('<w:sectPr');
    _revisionSaveAttribute('rsidR', section.revisionSaveId);
    _xml.add('>');
    _sectionProperties(section, breakBefore, includeReferences: true);
    _sectionFormattingRevision(section, breakBefore);
    _xml.add('</w:sectPr>');
    _count('sections');
  }

  void _sectionProperties(
    LegacyWordSection section,
    LegacyWordSectionBreak breakBefore, {
    bool includeReferences = false,
    bool historical = false,
  }) {
    // CT_SectPrBase (inside sectPrChange) cannot contain header/footer
    // references or a nested change record.
    if (includeReferences) {
      final sectionIndex = _sectionIndices[section] ?? 0;
      final references = _headerFooters[sectionIndex] ?? const [];
      for (final reference in references) {
        _xml.add(
          '<w:${reference.$1 ? 'header' : 'footer'}Reference w:type="${reference.$2}" r:id="${reference.$3}"/>',
        );
      }
    }
    _sectionNotes(section, historical: historical);
    _xml.add(
      '<w:type w:val="${switch (breakBefore) {
        LegacyWordSectionBreak.continuous => 'continuous',
        LegacyWordSectionBreak.newColumn => 'nextColumn',
        LegacyWordSectionBreak.newPage => 'nextPage',
        LegacyWordSectionBreak.evenPage => 'evenPage',
        LegacyWordSectionBreak.oddPage => 'oddPage',
      }}"/>',
    );
    if (section.pageWidthTwips != null ||
        section.pageHeightTwips != null ||
        section.landscape) {
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
    _sectionNumbering(section.layout);
    _sectionColumns(section);
    if (section.layout.suppressEndnotes) _xml.add('<w:noEndnote/>');
    if (section.titlePage) {
      _xml.add('<w:titlePg/>');
    }
    _sectionGrid(section.layout);
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
    _tableStyleXml(xml);
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
