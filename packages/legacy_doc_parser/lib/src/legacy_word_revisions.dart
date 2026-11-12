// SPDX-License-Identifier: MPL-2.0

part of 'legacy_word_structured_parser.dart';

// Independently implemented from MS-DOC §§2.6.1–2.6.2 and PropRMarkOperand.
// A wall captures the already resolved state; later SPRMs change the current
// state. A false wall clears the snapshot instead of accepting any edits.
_Props _revisionSnapshot(_Props properties) => Map.unmodifiable({
  for (final entry in properties.entries)
    if (entry.key != '_oldCharacter' && entry.key != '_oldParagraph')
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
    final chpx = characterFormatting.at(piece.fc(cp));
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

  LegacyWordParagraphMark _paragraphMark(int cp, _Props base) {
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
}
