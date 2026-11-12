// SPDX-License-Identifier: MPL-2.0

part of 'legacy_word_structured_parser.dart';

// Independently implemented from MS-DOC §§2.6.1–2.6.2 and PropRMarkOperand.
// A wall captures the already resolved state; later SPRMs change the current
// state. A false wall clears the snapshot instead of accepting any edits.
_Props _revisionSnapshot(_Props properties) => Map.unmodifiable({
  for (final entry in properties.entries)
    if (entry.key != '_oldCharacter' &&
        entry.key != '_oldParagraph' &&
        entry.key != '_oldSection')
      entry.key: entry.value,
});

void _applyPropertyRevision(_Bytes value, _Props output, String prefix) {
  if (value.length != 7) {
    throw const FormatException('Invalid Word property-revision record.');
  }
  output['${prefix}RevisionMarked'] = _boolean(value);
  output['${prefix}RevisionAuthor'] = value.i16(1);
  output['${prefix}RevisionDate'] = value.u32(3);
}

const _paragraphStylePreserved = {
  'inTable',
  'tableDepth',
  'rowEnd',
  'innerCellEnd',
  'innerRowEnd',
  'tableDefinition',
  'rowHeader',
  'cellShading',
  '_oldParagraph',
  'paragraphSaveId',
  '_unsupportedParagraph',
};

extension _WordRevisions on _StructuredWordParser {
  LegacyWordSection _sectionFromProperties(
    _Props properties,
    int start,
    int end, {
    bool includeRevision = true,
  }) {
    for (final key in ['width', 'height']) {
      final value = properties[key] as int?;
      if (value != null && (value < 144 || value > 31680)) {
        throw const FormatException('Invalid Word page dimension.');
      }
    }
    return LegacyWordSection(
      startCp: start,
      endCp: end,
      layout: _sectionLayout(properties),
      formattingRevision: includeRevision
          ? _sectionRevision(properties, start, end)
          : null,
      revisionSaveId: properties['sectionSaveId'] as int?,
      pageWidthTwips: properties['width'] as int?,
      pageHeightTwips: properties['height'] as int?,
      marginTopTwips: properties['top'] as int?,
      marginBottomTwips: properties['bottom'] as int?,
      marginLeftTwips: properties['left'] as int?,
      marginRightTwips: properties['right'] as int?,
      gutterTwips: properties['gutter'] as int?,
      headerDistanceTwips: properties['header'] as int?,
      footerDistanceTwips: properties['footer'] as int?,
      columnsSpaceTwips: properties['columnsSpace'] as int?,
      landscape: properties['landscape'] == true,
      titlePage: properties['titlePage'] == true,
      footnotes: _sectionFootnoteSettings(properties, source.footnotes),
      endnotes: _sectionEndnoteSettings(properties, source.endnotes),
      suppressEndnotes: properties['suppressEndnotes'] == true,
      columns: properties['columns'] as int? ?? 1,
      breakKind:
          LegacyWordSectionBreak.values[properties['breakKind'] as int? ?? 2],
    );
  }

  LegacyWordSectionFormattingRevision? _sectionRevision(
    _Props properties,
    int start,
    int end,
  ) {
    final previous = properties['_oldSection'] as _Props?;
    final marked = properties['sectionRevisionMarked'] == true;
    if (previous == null && !marked) return null;
    final complete =
        previous != null && previous['_unsupportedSection'] != true;
    if (!marked || !complete) {
      warnings.add(LegacyWordWarning.revisionMetadataIncomplete);
    }
    return LegacyWordSectionFormattingRevision(
      previousSection: previous == null
          ? null
          : _sectionFromProperties(
              previous,
              start,
              end,
              includeRevision: false,
            ),
      revision: marked
          ? _revisionInfo(
              properties,
              'sectionRevision',
              saveIdKey: 'sectionSaveId',
            )
          : const LegacyWordRevisionInfo(),
      marked: marked,
      previousPropertiesComplete: complete,
    );
  }

  LegacyWordRevisionInfo _revisionInfo(
    _Props properties,
    String prefix, {
    String? saveIdKey,
  }) {
    final index = properties['${prefix}Author'] as int?;
    final raw = properties['${prefix}Date'] as int?;
    final author = index != null && index >= 0 && index < authors.length
        ? authors[index]
        : null;
    final time = _revisionDate(raw);
    if (author == null || time == null) {
      warnings.add(LegacyWordWarning.revisionMetadataIncomplete);
    }
    return LegacyWordRevisionInfo(
      author: author,
      time: time,
      authorIndex: index,
      rawDate: raw,
      saveId: properties[saveIdKey ?? '${prefix}SaveId'] as int?,
      reason: properties['${prefix}Reason'] as int?,
    );
  }

  LegacyWordCharacterFormattingRevision? _characterRevision(_Props properties) {
    final previous = properties['_oldCharacter'] as _Props?;
    final marked = properties['characterRevisionMarked'] == true;
    if (previous == null && !marked) return null;
    final complete = previous?['_unsupportedCharacter'] != true;
    if (!marked || previous == null || !complete) {
      warnings.add(LegacyWordWarning.revisionMetadataIncomplete);
    }
    return LegacyWordCharacterFormattingRevision(
      previousStyle: previous == null ? null : _characterStyle(previous),
      revision: marked
          ? _revisionInfo(
              properties,
              'characterRevision',
              saveIdKey: 'formattingSaveId',
            )
          : const LegacyWordRevisionInfo(),
      marked: marked,
      previousPropertiesComplete: complete && previous != null,
    );
  }

  LegacyWordParagraphFormattingRevision? _paragraphRevision(_Props properties) {
    final snapshot = properties['_oldParagraph'] as _Props?;
    final previous = snapshot == null ? null : <String, Object?>{...snapshot};
    if (previous != null) _applyListFormatting(previous, const {});
    final marked = properties['paragraphRevisionMarked'] == true;
    if (previous == null && !marked) return null;
    final complete = previous?['_unsupportedParagraph'] != true;
    if (!marked || previous == null || !complete) {
      warnings.add(LegacyWordWarning.revisionMetadataIncomplete);
    }
    return LegacyWordParagraphFormattingRevision(
      previousStyle: previous == null
          ? null
          : _paragraphStyle(previous, previous['styleIndex'] as int? ?? 0),
      revision: marked
          ? _revisionInfo(
              properties,
              'paragraphRevision',
              saveIdKey: 'paragraphSaveId',
            )
          : const LegacyWordRevisionInfo(),
      marked: marked,
      previousPropertiesComplete: complete && previous != null,
    );
  }

  _Props _characterAt(int cp, _Props characterBase) {
    final piece = source.pieceAt(cp);
    final fc = piece.fc(cp);
    final chpx = characterFormatting.at(fc);
    if (chpx.endFc - fc < (piece.compressed ? 1 : 2)) {
      throw const FormatException('Unaligned Word character formatting.');
    }
    final character = <String, Object?>{...characterBase};
    _applyCharacter(
      [...chpx.operations, ..._pieceProperties(piece)],
      character,
      characterBase,
      budget,
      warnings,
      paragraphStyle: characterBase,
      resolveCharacterStyle: (index) {
        if (index == 10 && !styles.containsKey(index)) return const {};
        if (styles[index]?.kind != 2) {
          throw const FormatException(
            'Invalid Word character-style reference.',
          );
        }
        return _resolveStyle(index).character;
      },
    );
    return character;
  }

  LegacyWordParagraphMark? _paragraphMark(int cp, _Props base) {
    if (_terminalMarkFormattingUnavailable(cp)) {
      warnings.add(LegacyWordWarning.terminalMarkFormattingUnavailable);
      warnings.add(LegacyWordWarning.revisionMetadataIncomplete);
      return null;
    }
    final properties = _characterAt(cp, base);
    final inserted = properties['inserted'] == true;
    final deleted = properties['deleted'] == true;
    return LegacyWordParagraphMark(
      style: _characterStyle(properties),
      inserted: inserted,
      deleted: deleted,
      insertionRevision: inserted
          ? _revisionInfo(properties, 'insertion')
          : null,
      deletionRevision: deleted ? _revisionInfo(properties, 'deletion') : null,
      formattingRevision: _characterRevision(properties),
      formattingSaveId: properties['formattingSaveId'] as int?,
    );
  }

  bool _terminalMarkFormattingUnavailable(int cp) {
    // Some native exports omit exactly the last main-story CR from both the
    // CHPX bin table and its final page. MS-DOC 2.4.6.2 makes those endpoints
    // exclusive: there is no character formatting to inherit or reconstruct.
    // Retain the paragraph, report the unknown mark, and never borrow the
    // preceding run (which can be a drawing or a tracked deletion).
    if (cp <= 0 ||
        cp != source.bodyLength - 1 ||
        source.totalLength != source.bodyLength ||
        body[cp] != 0x0d ||
        characterFormatting.fallback != null ||
        characterFormatting.runs.isEmpty ||
        paragraphFormatting.fallback != null ||
        paragraphFormatting.runs.isEmpty) {
      return false;
    }
    final piece = source.pieceAt(cp);
    if (cp <= piece.startCp ||
        piece.endCp != source.totalLength ||
        piece.prm != 0) {
      return false;
    }
    final width = piece.compressed ? 1 : 2;
    final fc = piece.fc(cp);
    final lastCharacter = characterFormatting.runs.last;
    if (lastCharacter.endFc != fc ||
        characterFormatting.finalPageEndFc != fc ||
        lastCharacter.startFc > fc - width) {
      return false;
    }
    // Require an independently covered complete mark and an exact final
    // physical paragraph boundary, not a partial UTF-16 unit or an unrelated
    // larger range. All other missing-format cases still use strict lookup.
    final lastParagraph = paragraphFormatting.runs.last;
    return lastParagraph.startFc <= fc &&
        lastParagraph.endFc == fc + width &&
        paragraphFormatting.finalPageEndFc == fc + width;
  }
}
