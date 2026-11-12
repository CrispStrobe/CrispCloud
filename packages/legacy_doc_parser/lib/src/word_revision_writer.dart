// SPDX-License-Identifier: MPL-2.0

part of 'conversion.dart';

extension _WordRevisionWriter on _StructuredWordWriter {
  void _revisionSaveAttribute(String attribute, int? value) {
    if (value == null) return;
    if (value < 0 || value > 0xffffffff) {
      throw const FormatException('Invalid Word revision save identifier.');
    }
    _xml.add(
      ' w:$attribute="${value.toRadixString(16).padLeft(8, '0').toUpperCase()}"',
    );
  }

  void _revisionElementStart(
    String name,
    LegacyWordRevisionInfo revision, {
    bool empty = false,
  }) {
    if (_revisionId >= 200000) _tooComplex();
    _xml.add('<w:$name w:id="${_revisionId++}" w:author="');
    _xml.text(revision.author ?? '', attribute: true);
    _xml.add('"');
    if (revision.time != null) {
      _xml.add(' w:date="${_wallClock(revision.time!)}"');
    }
    _xml.add(empty ? '/>' : '>');
    if (revision.author == null || revision.time == null) {
      limitations.add(LegacyWordConversionLimitation.revisions);
    }
  }

  void _characterFormattingRevision(
    LegacyWordCharacterFormattingRevision? change,
    int cp,
  ) {
    if (change == null) return;
    final previous = change.previousStyle;
    if (!change.marked || previous == null) {
      _incompleteRevision(
        'characterFormatting',
        cp,
        change.revision,
        marked: change.marked,
        snapshot: previous != null,
      );
      return;
    }
    if (!change.previousPropertiesComplete) {
      limitations.add(LegacyWordConversionLimitation.revisions);
    }
    _revisionElementStart('rPrChange', change.revision);
    _xml.add('<w:rPr>');
    _runStyle(previous, resetDefaults: true);
    _xml.add('</w:rPr></w:rPrChange>');
    _count('characterFormattingRevisions');
  }

  void _paragraphMarkProperties(LegacyWordParagraphMark? mark, int cp) {
    if (mark == null) return;
    _xml.add('<w:rPr>');
    _runStyle(mark.style);
    if (mark.inserted) {
      _revisionElementStart(
        'ins',
        mark.insertionRevision ?? const LegacyWordRevisionInfo(),
        empty: true,
      );
      _count('paragraphMarkInsertions');
    }
    if (mark.deleted) {
      _revisionElementStart(
        'del',
        mark.deletionRevision ?? const LegacyWordRevisionInfo(),
        empty: true,
      );
      _count('paragraphMarkDeletions');
    }
    _characterFormattingRevision(mark.formattingRevision, cp);
    _xml.add('</w:rPr>');
  }

  void _paragraphFormattingRevision(LegacyWordParagraph paragraph) {
    final change = paragraph.formattingRevision;
    if (change == null) return;
    final previous = change.previousStyle;
    if (!change.marked || previous == null) {
      _incompleteRevision(
        'paragraphFormatting',
        paragraph.startCp,
        change.revision,
        marked: change.marked,
        snapshot: previous != null,
      );
      return;
    }
    if (!change.previousPropertiesComplete) {
      limitations.add(LegacyWordConversionLimitation.revisions);
    }
    _revisionElementStart('pPrChange', change.revision);
    _xml.add('<w:pPr>');
    _previousParagraphStyle(previous, paragraph.startCp);
    _xml.add('</w:pPr></w:pPrChange>');
    _count('paragraphFormattingRevisions');
  }

  // The snapshot is deliberately a single previous property set: nested
  // change records are not invented from the one MS-DOC wall snapshot.
  void _previousParagraphStyle(LegacyWordParagraphStyle style, int cp) {
    _styles.putIfAbsent(style.styleIndex, () => style);
    _xml.add('<w:pStyle w:val="Legacy${style.styleIndex}"/>');
    _bool('keepNext', style.keepNext);
    _bool('keepLines', style.keepTogether);
    _bool('pageBreakBefore', style.pageBreakBefore);
    _bool('widowControl', style.layout.widowControl);
    final listId = style.listId?.abs();
    if (listId != null && listId != 0 && _numberingIds.contains(listId)) {
      _xml.add(
        '<w:numPr><w:ilvl w:val="${style.listLevel ?? 0}"/><w:numId w:val="$listId"/></w:numPr>',
      );
    } else if (listId != null && listId != 0) {
      limitations.add(LegacyWordConversionLimitation.revisions);
    }
    _bool('suppressLineNumbers', style.layout.suppressLineNumbers);
    _paragraphDecorations(style, _xml, cp);
    _paragraphLayoutBeforeSpacing(style.layout);
    final line = style.lineSpacingValue;
    final rule = style.lineSpacingMultiple
        ? 'auto'
        : (line ?? 240) < 0
        ? 'exact'
        : 'atLeast';
    _xml.add(
      '<w:spacing w:before="${style.spaceBeforeTwips}" w:after="${style.spaceAfterTwips}"',
    );
    if (style.layout.spaceBeforeAuto) _xml.add(' w:beforeAutospacing="1"');
    if (style.layout.spaceAfterAuto) _xml.add(' w:afterAutospacing="1"');
    if (line != null) _xml.add(' w:line="${line.abs()}" w:lineRule="$rule"');
    _xml.add(
      '/><w:ind w:left="${style.leftIndentTwips}" w:right="${style.rightIndentTwips}"',
    );
    _xml.add(
      style.firstLineIndentTwips < 0
          ? ' w:hanging="${-style.firstLineIndentTwips}"'
          : ' w:firstLine="${style.firstLineIndentTwips}"',
    );
    _xml.add('/>');
    _bool('contextualSpacing', style.layout.contextualSpacing);
    _bool('mirrorIndents', style.layout.mirrorIndents);
    _xml.add(
      '<w:jc w:val="${style.alignment == LegacyWordAlignment.justify ? 'both' : style.alignment.name}"/>',
    );
    _xml.add(
      '<w:outlineLvl w:val="${style.headingLevel == null ? 9 : style.headingLevel! - 1}"/>',
    );
  }

  void _incompleteRevision(
    String kind,
    int cp,
    LegacyWordRevisionInfo revision, {
    required bool marked,
    required bool snapshot,
  }) {
    limitations.add(LegacyWordConversionLimitation.revisions);
    if (_evidenceRecords.length >= 20000) _tooComplex();
    _evidenceRecords.add({
      'kind': kind,
      'cp': cp,
      'marked': marked,
      'previousPropertiesAvailable': snapshot,
      'authorIndex': revision.authorIndex,
      'rawDttm': revision.rawDate,
      'saveId': revision.saveId,
      'reason':
          'incomplete revision retained without inventing previous formatting',
    });
  }
}
