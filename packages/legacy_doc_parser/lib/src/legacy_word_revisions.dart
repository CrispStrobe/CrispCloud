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
  'numberingInserted',
  'numberingRevisionRecord',
  '_unsupportedParagraph',
};

class _DisplayFieldRevisionData {
  _DisplayFieldRevisionData(this.source, this.original, this.author, this.date);
  final Uint8List source;
  final String original;
  final int author;
  final int date;
}

class _DisplayFieldRevisionCapture {
  _DisplayFieldRevisionCapture(this.data, this.hidden);
  final _DisplayFieldRevisionData data;
  bool hidden;
}

// DispFldRmOperand's cb prefix is already consumed by the SPRM reader. Its f
// member is explicitly any nonzero value, unlike the format's Bool8 operands.
_DisplayFieldRevisionData? _displayFieldRevisionRecord(_Bytes value) {
  if (value.length != 39) {
    throw const FormatException('Invalid Word display-field revision record.');
  }
  if (value.u8(0) == 0) return null;
  final length = value.u16(7);
  if (length > 15) {
    throw const FormatException('Invalid Word display-field revision length.');
  }
  final units = [for (var i = 0; i < length; i++) value.u16(9 + i * 2)];
  _validateUnicode(units);
  return _DisplayFieldRevisionData(
    Uint8List.fromList(value.bytes).asUnmodifiableView(),
    String.fromCharCodes(units),
    value.u16(1),
    value.u32(3),
  );
}

// MS-DOC NumRMOperand: the length prefix was consumed by the SPRM reader.
Uint8List _numberingRevisionRecord(_Bytes value) {
  if (value.length != 128) {
    throw const FormatException('Invalid Word numbering revision record.');
  }
  final numbered = _boolean(value);
  if (numbered) {
    final length = value.u16(64);
    if (length > 31) {
      throw const FormatException(
        'Invalid Word numbering revision text length.',
      );
    }
    final units = [for (var i = 0; i < length; i++) value.u16(66 + i * 2)];
    _validateUnicode(units);
    final used = <int>{};
    for (var level = 0; level < 9; level++) {
      final position = value.u8(8 + level);
      if (position == 0) continue;
      if (position > length ||
          !used.add(position) ||
          units[position - 1] >= 0xd800 && units[position - 1] <= 0xdfff) {
        throw const FormatException(
          'Invalid Word numbering revision placeholder.',
        );
      }
    }
  }
  return Uint8List.fromList(value.bytes).asUnmodifiableView();
}

String? _numberingRevisionOriginal(_Bytes value) {
  if (value.u8(0) == 0) return null;
  final length = value.u16(64);
  final units = [for (var i = 0; i < length; i++) value.u16(66 + i * 2)];
  final placeholders = <int, int>{
    for (var level = 0; level < 9; level++)
      if (value.u8(8 + level) != 0) value.u8(8 + level) - 1: level,
  };
  if (placeholders.isEmpty || !placeholders.containsKey(0)) return null;
  final positions = placeholders.keys.toList()..sort();
  final original = StringBuffer();
  for (var i = 0; i < positions.length; i++) {
    final position = positions[i], level = placeholders[position]!;
    final format = value.u8(17 + level);
    if (format == 40 || format >= 60) return null;
    final end = i + 1 < positions.length ? positions[i + 1] : units.length;
    final separator = units.sublist(position + 1, end);
    // The native string grammar has no literal-percent escape. Neither emit a
    // new placeholder nor copy invalid XML controls from a source separator.
    if (separator.any(
      (unit) => unit == 0x25 || unit < 0x20 || unit == 0xfffe || unit == 0xffff,
    )) {
      return null;
    }
    original.write('%${level + 1}:${value.u32(28 + level * 4)}:$format:');
    original.write(String.fromCharCodes(separator));
  }
  return original.toString();
}

extension _WordRevisions on _StructuredWordParser {
  void _prepareFieldRevisions(int firstField) {
    _fieldIndicesByStart.clear();
    _activeFieldIndices.clear();
    _displayFieldRevisions.clear();
    _hiddenFieldMarkers.clear();
    _hiddenFieldInstructions.clear();
    for (var index = firstField; index < fields.length; index++) {
      _fieldIndicesByStart[fields[index].startCp] = index;
    }
  }

  void _captureFieldRevision(int cp, int unit, _Props properties, bool hidden) {
    if (unit == 19) {
      final index = _fieldIndicesByStart[cp];
      if (index == null || _activeFieldIndices.length >= 64) {
        throw const FormatException('Invalid Word revision field boundary.');
      }
      _activeFieldIndices.add(index);
    }
    // Capture the actual marker's resolved CHPX, paragraph, character-style
    // and table context while visiting it. Cached result formatting cannot
    // determine whether the original begin/separator/end marker was hidden.
    if (hidden && (unit == 19 || unit == 20 || unit == 21)) {
      final flag = switch (unit) {
        19 => 1,
        20 => 2,
        _ => 4,
      };
      final index = _activeFieldIndices.last;
      _hiddenFieldMarkers[index] = (_hiddenFieldMarkers[index] ?? 0) | flag;
    }
    if (unit != 19 && unit != 20 && unit != 21) {
      _captureFieldInstructionVisibility(cp, hidden);
    }
    final data =
        properties['displayFieldRevision'] as _DisplayFieldRevisionData?;
    if (data != null) {
      if (_activeFieldIndices.isEmpty ||
          fields[_activeFieldIndices.last].type != 'LISTNUM') {
        throw const FormatException(
          'Word display-field revision is not attached to a LISTNUM field.',
        );
      }
      final index = _activeFieldIndices.last;
      final private = _activeFieldIndices.any(
        (index) => fields[index].privateResult,
      );
      final capture = _displayFieldRevisions[index];
      if (capture == null) {
        _displayFieldRevisions[index] = _DisplayFieldRevisionCapture(
          data,
          hidden || private,
        );
      } else {
        final previous = capture.data;
        if (!identical(previous, data) &&
            (previous.original != data.original ||
                previous.author != data.author ||
                previous.date != data.date)) {
          throw const FormatException(
            'Conflicting Word display-field revisions.',
          );
        }
        capture.hidden |= hidden || private;
      }
    }
    if (unit == 21) {
      if (_activeFieldIndices.isEmpty) {
        throw const FormatException('Unmatched Word revision field boundary.');
      }
      _activeFieldIndices.removeLast();
    }
  }

  void _captureFieldInstructionVisibility(int cp, bool hidden) {
    if (!hidden || _activeFieldIndices.isEmpty) return;
    final index = _activeFieldIndices.last;
    final field = fields[index];
    if (cp >= (field.separatorCp ?? field.endCp - 1)) return;
    final offset = cp - field.startCp - 1;
    final ranges = _hiddenFieldInstructions.putIfAbsent(index, () => []);
    if (ranges.isNotEmpty && ranges.last.$2 == offset) {
      ranges[ranges.length - 1] = (ranges.last.$1, offset + 1);
    } else {
      if (++_hiddenFieldInstructionRangeCount > 200000) {
        throw const FormatException('Word field visibility is too complex.');
      }
      ranges.add((offset, offset + 1));
    }
  }

  void _finishFieldRevisions() {
    if (_activeFieldIndices.isNotEmpty) {
      throw const FormatException('Unclosed Word revision field.');
    }
    for (final index in {
      ..._displayFieldRevisions.keys,
      ..._hiddenFieldMarkers.keys,
      ..._hiddenFieldInstructions.keys,
    }) {
      final field = fields[index];
      final capture = _displayFieldRevisions[index];
      final markerFlags = _hiddenFieldMarkers[index] ?? 0;
      final data = capture?.data;
      fields[index] = LegacyWordField(
        id: field.id,
        storyId: field.storyId,
        startCp: field.startCp,
        endCp: field.endCp,
        instruction: field.instruction,
        storedResult: field.storedResult,
        type: field.type,
        separatorCp: field.separatorCp,
        parentId: field.parentId,
        locked: field.locked,
        dirty: field.dirty,
        privateResult: field.privateResult,
        beginHidden: field.beginHidden || markerFlags & 1 != 0,
        separatorHidden: field.separatorHidden || markerFlags & 2 != 0,
        endHidden: field.endHidden || markerFlags & 4 != 0,
        instructionVisibility: _hiddenFieldInstructions.containsKey(index)
            ? LegacyWordFieldInstructionVisibility(
                _hiddenFieldInstructions[index]!,
              )
            : field.instructionVisibility,
        displayRevision: data == null
            ? field.displayRevision
            : LegacyWordDisplayFieldRevision(
                original: data.original,
                revision: _revisionInfo({
                  'displayAuthor': data.author,
                  'displayDate': data.date,
                }, 'display'),
                hidden: capture!.hidden,
                sourceRecord: data.source,
              ),
      );
    }
  }

  LegacyWordNumberingRevision? _numberingRevision(_Props properties) {
    final record = properties['numberingRevisionRecord'] as Uint8List?;
    final inserted = properties['numberingInserted'] == true;
    if (record == null && !inserted) return null;
    final value = record == null ? null : _Bytes(record);
    final numbered = value == null ? null : value.u8(0) != 0;
    final original = value == null ? null : _numberingRevisionOriginal(value);
    if (numbered == true && original == null || value == null) {
      warnings.add(LegacyWordWarning.revisionMetadataIncomplete);
    }
    return LegacyWordNumberingRevision(
      previouslyNumbered: numbered,
      original: original,
      inserted: inserted,
      sourceRecord: record,
      revision: _revisionInfo({
        if (value != null) ...{
          'numberingAuthor': value.u16(2),
          'numberingDate': value.u32(4),
        },
      }, 'numbering'),
    );
  }

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
    final symbolChanged =
        previous != null &&
        (previous['symbolCharacterCode'] != null ||
            properties['symbolCharacterCode'] != null) &&
        (previous['special'] != properties['special'] ||
            previous['symbolFontIndex'] != properties['symbolFontIndex'] ||
            previous['symbolCharacterCode'] !=
                properties['symbolCharacterCode']);
    // rPrChange cannot express a previous glyph as ordinary font properties.
    // Preserve the current symbol and disclose that content-history boundary.
    final complete =
        previous?['_unsupportedCharacter'] != true && !symbolChanged;
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
        // Character styles are differences applied over the paragraph/table
        // context; evaluating their 0x80/0x81 toggles against an empty base
        // would discard a conditional table character style.
        return _resolveStyleOverTable(
          index,
          _TableTextContext(_ResolvedStyle(const {}, characterBase)),
        ).character;
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
