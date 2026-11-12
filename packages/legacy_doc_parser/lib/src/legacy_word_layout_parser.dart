// SPDX-License-Identifier: MPL-2.0
part of 'legacy_word_structured_parser.dart';

// MS-DOC 2.6.2, 2.6.4, 2.9.215, 2.9.237, 2.9.241–242 and 2.9.250.
const _paragraphLayoutBooleans = <int, String>{
  0x240c: 'suppressLineNumbers',
  0x242a: 'suppressAutoHyphens',
  0x2431: 'widowControl',
  0x2433: 'kinsoku',
  0x2434: 'wordWrap',
  0x2435: 'overflowPunctuation',
  0x2437: 'autoSpaceEastAsianLatin',
  0x2438: 'autoSpaceEastAsianNumbers',
  0x2441: 'rightToLeft',
  0x245b: 'spaceBeforeAuto',
  0x245c: 'spaceAfterAuto',
  0x246d: 'contextualSpacing',
  0x2470: 'mirrorIndents',
};

bool _applyParagraphLayout(_Sprm operation, _Props output) {
  final key = _paragraphLayoutBooleans[operation.code];
  if (key == null) return false;
  output[key] = _boolean(operation.data);
  return true;
}

LegacyWordParagraphLayout _paragraphLayout(_Props properties) =>
    LegacyWordParagraphLayout(
      widowControl: properties['widowControl'] as bool? ?? true,
      suppressAutoHyphens: properties['suppressAutoHyphens'] == true,
      suppressLineNumbers: properties['suppressLineNumbers'] == true,
      contextualSpacing: properties['contextualSpacing'] == true,
      mirrorIndents: properties['mirrorIndents'] == true,
      rightToLeft: properties['rightToLeft'] == true,
      spaceBeforeAuto: properties['spaceBeforeAuto'] == true,
      spaceAfterAuto: properties['spaceAfterAuto'] == true,
      kinsoku: properties['kinsoku'] as bool?,
      wordWrap: properties['wordWrap'] as bool?,
      overflowPunctuation: properties['overflowPunctuation'] as bool?,
      autoSpaceEastAsianLatin: properties['autoSpaceEastAsianLatin'] as bool?,
      autoSpaceEastAsianNumbers:
          properties['autoSpaceEastAsianNumbers'] as bool?,
    );

bool _applySectionLayout(
  _Sprm operation,
  _Props output,
  Set<LegacyWordWarning> warnings,
) {
  final value = operation.data;
  int bounded(int number, int minimum, int maximum) {
    if (number < minimum || number > maximum) {
      throw const FormatException('Invalid Word section layout property.');
    }
    return number;
  }

  switch (operation.code) {
    case 0x3005:
      output['equalColumnWidths'] = _boolean(value);
    case 0xf203:
    case 0xf204:
      final index = bounded(value.u8(0), 0, 43);
      final width = operation.code == 0xf203;
      final amount = bounded(value.u16(1), width ? 718 : 0, 31680);
      final key = width ? 'columnWidths' : 'columnSpaces';
      final columns = <int, int>{...?output[key] as Map<int, int>?};
      columns[index] = amount;
      output[key] = columns;
    case 0x3019:
      output['columnSeparator'] = _boolean(value);
    case 0x301a:
      output['pageVerticalAlignment'] = bounded(value.u8(0), 0, 3);
    case 0x3013:
      output['lineNumberRestart'] = bounded(value.u8(0), 0, 2);
    case 0x5015:
      output['lineNumberInterval'] = bounded(value.u16(0), 0, 100);
    case 0x501b:
      output['lineNumberStart'] = value.u16(0) + 1;
    case 0x9016:
      output['lineNumberDistance'] = bounded(value.u16(0), 0, 31680);
    case 0x3011:
      output['restartPageNumbering'] = _boolean(value);
    case 0x3012:
      output['suppressEndnotes'] = !_boolean(value);
    case 0x303b:
      output['footnotePosition'] = bounded(value.u8(0), 1, 2);
    case 0x303c:
      output['footnoteRestart'] = bounded(value.u8(0), 0, 2);
    case 0x303e:
      output['endnoteRestart'] = bounded(value.u8(0), 0, 1);
    case 0x503f:
    case 0x5041:
      output[operation.code == 0x503f
          ? 'footnoteContinuousOffset'
          : 'endnoteContinuousOffset'] = bounded(
        value.u16(0),
        0,
        16383,
      );
    case 0x5040:
    case 0x5042:
      _applyNoteNumberFormat(
        output,
        operation.code == 0x5040 ? 'footnote' : 'endnote',
        value.u16(0),
        warnings,
      );
    case 0x501c:
      output['pageNumberStart'] = value.u16(0);
    case 0x7044:
      output['pageNumberStart'] = bounded(value.u32(0), 0, 2147483646);
    case 0x300e:
      const formats = [
        'decimal',
        'upperRoman',
        'lowerRoman',
        'upperLetter',
        'lowerLetter',
      ];
      final index = value.u8(0);
      if (index < formats.length) {
        output['pageNumberFormat'] = formats[index];
      } else {
        output.remove('pageNumberFormat');
        output['_unsupportedSection'] = true;
        warnings.add(LegacyWordWarning.unsupportedFormatting);
      }
    case 0x5032:
      output['documentGrid'] = bounded(value.u16(0), 0, 3);
    case 0x9031:
      output['gridLinePitch'] = bounded(value.i16(0), 1, 31680);
    case 0x7030:
      output['gridCharacterSpace'] = bounded(value.i32(0), -670925, 6488064);
    default:
      return false;
  }
  return true;
}

LegacyWordSectionLayout _sectionLayout(_Props properties) {
  final count = properties['columns'] as int? ?? 1;
  final equal = properties['equalColumnWidths'] as bool? ?? true;
  final widths = properties['columnWidths'] as Map<int, int>? ?? const {};
  final spaces = properties['columnSpaces'] as Map<int, int>? ?? const {};
  if (!equal &&
      count > 1 &&
      (widths.length != count ||
          List.generate(count, (i) => i).any((i) => !widths.containsKey(i)))) {
    throw const FormatException('Incomplete unequal Word page columns.');
  }
  if (!equal &&
      (widths.keys.any((i) => i >= count) ||
          spaces.keys.any((i) => i >= count))) {
    throw const FormatException('Word column properties exceed column count.');
  }
  final grid =
      LegacyWordDocumentGrid.values[properties['documentGrid'] as int? ?? 0];
  if (grid != LegacyWordDocumentGrid.none &&
      properties['gridLinePitch'] == null) {
    throw const FormatException('Word document grid has no line pitch.');
  }
  return LegacyWordSectionLayout(
    equalColumnWidths: equal,
    columns: List.unmodifiable(
      !equal && widths.isNotEmpty
          ? [
              for (var i = 0; i < count; i++)
                LegacyWordPageColumn(
                  widthTwips: widths[i]!,
                  spaceAfterTwips: spaces[i] ?? 0,
                ),
            ]
          : const <LegacyWordPageColumn>[],
    ),
    columnSeparator: properties['columnSeparator'] == true,
    verticalAlignment: LegacyWordPageVerticalAlignment
        .values[properties['pageVerticalAlignment'] as int? ?? 0],
    lineNumberInterval: properties['lineNumberInterval'] as int? ?? 0,
    lineNumberStart: properties['lineNumberStart'] as int? ?? 1,
    lineNumberDistanceTwips: properties['lineNumberDistance'] as int? ?? 0,
    lineNumberRestart: LegacyWordLineNumberRestart
        .values[properties['lineNumberRestart'] as int? ?? 0],
    restartPageNumbering: properties['restartPageNumbering'] == true,
    pageNumberStart: properties['pageNumberStart'] as int? ?? 0,
    pageNumberFormat: properties['pageNumberFormat'] as String?,
    grid: grid,
    gridLinePitchTwips: properties['gridLinePitch'] as int?,
    gridCharacterSpace: properties['gridCharacterSpace'] as int?,
    footnoteNumbering: _noteNumbering(properties, 'footnote'),
    endnoteNumbering: _noteNumbering(properties, 'endnote'),
    footnotePosition: switch (properties['footnotePosition'] as int? ?? 1) {
      0 => LegacyWordFootnotePosition.sectEnd,
      1 => LegacyWordFootnotePosition.pageBottom,
      _ => LegacyWordFootnotePosition.beneathText,
    },
    endnotePosition: switch (properties['endnotePosition']) {
      0 => LegacyWordEndnotePosition.sectEnd,
      3 => LegacyWordEndnotePosition.docEnd,
      _ => null,
    },
    suppressEndnotes: properties['suppressEndnotes'] == true,
  );
}

const _noteFormats = <int, String>{
  0: 'decimal',
  1: 'upperRoman',
  2: 'lowerRoman',
  3: 'upperLetter',
  4: 'lowerLetter',
  9: 'chicago',
  22: 'decimalZero',
};

void _applyNoteNumberFormat(
  _Props output,
  String kind,
  int code,
  Set<LegacyWordWarning> warnings,
) {
  output['${kind}FormatCode'] = code;
  output['${kind}Format'] = _noteFormats[code];
  if (!_noteFormats.containsKey(code)) {
    output['_unsupportedSection'] = true;
    warnings.add(LegacyWordWarning.unsupportedFormatting);
  }
}

LegacyWordNoteNumbering _noteNumbering(_Props properties, String kind) {
  final restart =
      LegacyWordNoteRestart.values[properties['${kind}Restart'] as int? ?? 0];
  final offset = properties['${kind}ContinuousOffset'] as int?;
  return LegacyWordNoteNumbering(
    format: properties.containsKey('${kind}Format')
        ? properties['${kind}Format'] as String?
        : kind == 'footnote'
        ? 'decimal'
        : 'lowerRoman',
    start: restart == LegacyWordNoteRestart.continuous && offset != null
        ? offset
        : properties['${kind}Start'] as int? ?? 1,
    restart: restart,
    sourceFormatCode: properties['${kind}FormatCode'] as int?,
    sourceContinuousOffset: offset,
  );
}

extension _DocumentNoteSettings on _StructuredWordParser {
  _Props _documentNoteProperties() {
    final (offset, length) = source.pair(31);
    if (length == 0) return {};
    final dop = _Bytes(source.table.slice(offset, length));
    final endPosition = dop.u16(54) & 3;
    if (endPosition != 0 && endPosition != 3) {
      throw const FormatException('Invalid Word endnote placement.');
    }
    final result = <String, Object?>{'endnotePosition': endPosition};
    // The older document-wide fields are reserved for later versions. Do not
    // allow stale bytes to override the section SPRMs of Word 2002 or later.
    final version = source.compatibility.sourceFibNewVersion ?? source.version;
    if (version > 0x00d9) return result;
    final footPosition = (dop.u8(0) >> 5) & 3;
    final foot = dop.u16(2), end = dop.u16(52);
    if (footPosition == 3 || (foot & 3) == 3 || (end & 3) == 3) {
      throw const FormatException('Invalid Word document note numbering.');
    }
    result.addAll({
      'footnotePosition': footPosition,
      'footnoteRestart': foot & 3,
      'footnoteStart': foot >> 2,
      'endnoteRestart': end & 3,
      'endnoteStart': end >> 2,
    });
    if (length >= 500) {
      _applyNoteNumberFormat(result, 'footnote', dop.u16(492), warnings);
      _applyNoteNumberFormat(result, 'endnote', dop.u16(494), warnings);
    }
    return result;
  }
}
