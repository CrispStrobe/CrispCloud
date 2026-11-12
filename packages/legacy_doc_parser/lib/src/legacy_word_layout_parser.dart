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
    case 0x3228:
      output['sectionRightToLeft'] = _boolean(value);
    case 0x322a:
      output['rightToLeftGutter'] = _boolean(value);
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
    rightToLeft: properties['sectionRightToLeft'] == true,
    rightToLeftGutter: properties['rightToLeftGutter'] == true,
  );
}
