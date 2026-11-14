// SPDX-License-Identifier: MPL-2.0

part of 'conversion.dart';

extension _WordRevisionWriter on _StructuredWordWriter {
  void _displayFieldRevisionEvidence(LegacyWordField field) {
    final change = field.displayRevision;
    if (change == null) return;
    if (_evidenceRecords.length >= 20000) _tooComplex();
    final detail = {
      'original': change.original,
      'hidden': change.hidden,
      'revision': {
        'author': change.revision.author,
        'time': change.revision.time?.toIso8601String(),
        'authorIndex': change.revision.authorIndex,
        'rawDate': change.revision.rawDate,
        'saveId': change.revision.saveId,
        'reason': change.revision.reason,
      },
    };
    final metadata = {
      'fieldId': field.id,
      'story': field.storyId,
      'startCp': field.startCp,
      'authorIndex': change.revision.authorIndex,
      'rawDttm': change.revision.rawDate,
      'privateResult': field.privateResult,
      'hidden': change.hidden,
      'displayRevision': detail,
      'nativeHistoryAvailable': false,
    };
    if (change.sourceRecord != null) {
      _preserveEvidence('displayFieldRevisionRecord', change.sourceRecord!, {
        'sourceStructure': 'DispFldRmOperand',
        ...metadata,
      });
      detail['sourceRecordPart'] = _evidenceRecords.last['part'] as String;
    } else {
      _evidenceRecords.add({'kind': 'displayFieldRevision', ...metadata});
    }
    // Record every typed history before visibility or field-support filtering.
    // Caller-built models need not have a binary DispFldRmOperand. Mark native
    // availability only when the original is actually emitted: ancestors can
    // suppress otherwise supported LISTNUM descendants.
    _displayFieldRevisionRecords[field.id] = _evidenceRecords.last;
    if (field.type != 'LISTNUM' ||
        field.privateResult ||
        change.hidden ||
        !change.original.runes.every(
          (rune) =>
              rune >= 32 &&
              rune != 0xfffe &&
              rune != 0xffff &&
              !(rune >= 0xd800 && rune <= 0xdfff),
        )) {
      _incompleteRevision(
        'displayField',
        field.startCp,
        change.revision,
        marked: true,
        snapshot: false,
      );
    }
  }

  void _displayFieldRevision(LegacyWordField field) {
    final change = field.displayRevision;
    if (change == null ||
        field.type != 'LISTNUM' ||
        field.privateResult ||
        change.hidden) {
      return;
    }
    final safeOriginal = change.original.runes.every(
      (rune) =>
          rune >= 32 &&
          rune != 0xfffe &&
          rune != 0xffff &&
          !(rune >= 0xd800 && rune <= 0xdfff),
    );
    _revisionElementStart(
      'numberingChange',
      change.revision,
      empty: true,
      originalNumbering: safeOriginal ? change.original : null,
    );
    if (safeOriginal &&
        !_part.startsWith('word/inertStoryEvidence') &&
        !_part.startsWith('word/textboxEvidence')) {
      _displayFieldRevisionRecords[field.id]!['nativeHistoryAvailable'] = true;
    }
    _count('displayFieldRevisions');
  }

  void _paragraphNumbering(LegacyWordParagraph paragraph) {
    final style = paragraph.style;
    final listId = style.listId?.abs();
    final change = paragraph.numberingRevision;
    final numbered = listId != null && listId != 0;
    final outputId = _resolvedParagraphNumbering[paragraph];
    final supported = numbered && outputId != null;
    final materialized = _materializedParagraphNumbering.containsKey(paragraph);
    if (change?.sourceRecord != null) {
      _preserveEvidence('numberingRevisionRecord', change!.sourceRecord!, {
        'cp': paragraph.startCp,
        'sourceStructure': 'NumRM',
        'previouslyNumbered': change.previouslyNumbered,
        'numberingInserted': change.inserted,
        'nativeOriginalAvailable': change.original != null,
        'authorIndex': change.revision.authorIndex,
        'rawDttm': change.revision.rawDate,
      });
    }
    if (_suppressedParagraphNumbering.contains(paragraph)) {
      _xml.add('<w:numPr><w:numId w:val="0"/></w:numPr>');
      if (change != null) {
        _incompleteRevision(
          'suppressedFieldNumberingRevision',
          paragraph.startCp,
          change.revision,
          marked: true,
          snapshot: change.original != null,
        );
        _evidenceRecords.last.addAll({
          'originalNumbering': change.original,
          'previouslyNumbered': change.previouslyNumbered,
          'numberingInserted': change.inserted,
          'revision': {
            'author': change.revision.author,
            'time': change.revision.time?.toIso8601String(),
            'authorIndex': change.revision.authorIndex,
            'rawDate': change.revision.rawDate,
            'saveId': change.revision.saveId,
            'reason': change.revision.reason,
          },
          'reason':
              'Source-hidden label remains suppressed; original numbering '
              'history is retained without activating its revision behavior',
        });
      }
      return;
    }
    if (materialized) {
      _xml.add('<w:numPr><w:numId w:val="0"/></w:numPr>');
      if (change != null) {
        _incompleteRevision(
          'materializedNumbering',
          paragraph.startCp,
          change.revision,
          marked: true,
          snapshot: change.original != null,
        );
        _evidenceRecords.last.addAll({
          'originalNumbering': change.original,
          'previouslyNumbered': change.previouslyNumbered,
          'numberingInserted': change.inserted,
          'revision': {
            'author': change.revision.author,
            'time': change.revision.time?.toIso8601String(),
            'authorIndex': change.revision.authorIndex,
            'rawDate': change.revision.rawDate,
            'saveId': change.revision.saveId,
            'reason': change.revision.reason,
          },
          'reason':
              'Literal label is retained as text; automatic numbering '
              'revision accept/reject behavior cannot be reproduced',
        });
      }
      return;
    }
    if (numbered && !supported) {
      limitations.add(LegacyWordConversionLimitation.fieldsLists);
      if (change != null) {
        _incompleteRevision(
          'numbering',
          paragraph.startCp,
          change.revision,
          marked: true,
          snapshot: change.original != null,
        );
      }
      return;
    }
    if (!numbered && change?.inserted == true) {
      _incompleteRevision(
        'numberingInsertion',
        paragraph.startCp,
        change!.revision,
        marked: true,
        snapshot: change.original != null,
      );
    }
    if (!numbered && change?.previouslyNumbered != true) return;

    _xml.add('<w:numPr>');
    if (supported) {
      _xml.add('<w:ilvl w:val="${style.listLevel ?? 0}"/>');
    }
    _xml.add('<w:numId w:val="${supported ? outputId : 0}"/>');
    if (change?.previouslyNumbered == true) {
      final original = change!.original;
      if (original == null) {
        limitations.add(LegacyWordConversionLimitation.revisions);
      } else if (original.length > 1024) {
        _tooComplex();
      }
      _revisionElementStart(
        'numberingChange',
        change.revision,
        empty: true,
        originalNumbering: original,
      );
      _count('numberingRevisions');
    }
    if (change?.inserted == true && supported) {
      _revisionElementStart('ins', change!.revision, empty: true);
      _count('numberingInsertions');
    }
    _xml.add('</w:numPr>');
  }

  void _sectionFormattingRevision(
    LegacyWordSection section,
    LegacyWordSectionBreak currentBreakBefore,
  ) {
    final change = section.formattingRevision;
    final previous = change?.previousSection;
    final ownChange = change != null && change.marked && previous != null;
    if (change != null && !ownChange) {
      _incompleteRevision(
        'sectionFormatting',
        section.startCp,
        change.revision,
        marked: change.marked,
        snapshot: previous != null,
      );
    }

    // A binary SBkc ends the preceding section; OOXML type is owned by this
    // section. Move its revision with the property rather than attributing the
    // preceding section's old break to unrelated layout properties here.
    final index = _sectionIndices[section];
    final preceding = index != null && index > 0
        ? document.sections[index - 1]
        : null;
    final incoming = preceding?.formattingRevision;
    final incomingPrevious = incoming?.previousSection;
    final hasIncomingBreak =
        incoming != null &&
        incoming.marked &&
        incomingPrevious != null &&
        incomingPrevious.breakKind != preceding!.breakKind;
    final mergeIncoming =
        hasIncomingBreak &&
        (!ownChange || incoming.revision == change.revision);
    if (hasIncomingBreak && !mergeIncoming) {
      _sectionBreakRevisionEvidence(
        preceding,
        incoming,
        'the receiving section has a separate property revision; one native '
        'sectPrChange cannot attribute two independent revisions',
      );
    }
    if (ownChange &&
        previous.breakKind != section.breakKind &&
        index == document.sections.length - 1) {
      _sectionBreakRevisionEvidence(
        section,
        change,
        'terminal binary section break has no following OOXML section',
      );
    }

    final revision = ownChange
        ? change.revision
        : mergeIncoming
        ? incoming.revision
        : null;
    if (revision == null) return;
    if (ownChange && !change.previousPropertiesComplete ||
        mergeIncoming && !incoming.previousPropertiesComplete) {
      limitations.add(LegacyWordConversionLimitation.revisions);
    }
    _revisionElementStart('sectPrChange', revision);
    _xml.add('<w:sectPr>');
    _sectionProperties(
      ownChange ? previous : section,
      mergeIncoming ? incomingPrevious.breakKind : currentBreakBefore,
      historical: true,
    );
    _xml.add('</w:sectPr></w:sectPrChange>');
    _count('sectionFormattingRevisions');
  }

  void _sectionBreakRevisionEvidence(
    LegacyWordSection section,
    LegacyWordSectionFormattingRevision change,
    String reason,
  ) {
    limitations.add(LegacyWordConversionLimitation.revisions);
    if (_evidenceRecords.length >= 20000) _tooComplex();
    _evidenceRecords.add({
      'kind': 'sectionBreakRevision',
      'cp': section.endCp,
      'current': section.breakKind.name,
      'previous': change.previousSection?.breakKind.name,
      'authorIndex': change.revision.authorIndex,
      'rawDttm': change.revision.rawDate,
      'saveId': change.revision.saveId,
      'reason': reason,
    });
  }

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
    String? originalNumbering,
  }) {
    if (_revisionId >= 200000) _tooComplex();
    _xml.add('<w:$name w:id="${_revisionId++}" w:author="');
    _xml.text(revision.author ?? '', attribute: true);
    _xml.add('"');
    if (revision.time != null) {
      _xml.add(' w:date="${_wallClock(revision.time!)}"');
    }
    if (originalNumbering != null) {
      _xml.add(' w:original="');
      _xml.text(originalNumbering, attribute: true);
      _xml.add('"');
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
    // CT_ParaRPr places paragraph-mark revisions before EG_RPrBase, unlike
    // ordinary run properties. A styled/hidden mark must retain that order.
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
    _runStyle(mark.style);
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
    final template = _numberingTemplates[(listId, style.listLevel ?? 0)];
    if (template != null && !template.nativeRepresentable) {
      _xml.add('<w:numPr><w:numId w:val="0"/></w:numPr>');
      limitations.add(LegacyWordConversionLimitation.revisions);
      limitations.add(LegacyWordConversionLimitation.fieldsLists);
      if (_evidenceRecords.length >= 20000) _tooComplex();
      _evidenceRecords.add({
        'kind': 'previousLiteralNumbering',
        'cp': cp,
        'definition': listId,
        'level': style.listLevel ?? 0,
        'reason':
            'Previous literal numbering template is retained in evidence; '
            'rejecting the property change cannot restore an automatic label',
      });
    } else if (listId != null &&
        listId != 0 &&
        _numberingIds.contains(listId)) {
      _xml.add(
        '<w:numPr><w:ilvl w:val="${style.listLevel ?? 0}"/><w:numId w:val="${_numberingReferences[listId]}"/></w:numPr>',
      );
    } else if (listId != null && listId != 0) {
      limitations.add(LegacyWordConversionLimitation.revisions);
    }
    _bool('suppressLineNumbers', style.layout.suppressLineNumbers);
    _paragraphDecorations(style, _xml, cp);
    _paragraphLayoutBeforeSpacing(style.layout);
    final line = style.lineSpacingValue;
    final rule = _StructuredWordWriter._lineSpacingRule(style);
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
