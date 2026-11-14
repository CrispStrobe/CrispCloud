// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';

/// Each marker has its own CHPX visibility, independently from both halves of
/// its cached result. The 3 marker bits are begin, separator and end; the two
/// result bits hide Left and Right respectively.
Uint8List fieldMarkerFormattingFixture({
  required int markerMask,
  int resultMask = 0,
  bool instructionHidden = false,
  bool compressed = true,
}) {
  const text = 'A\x13 REF Missing \x14LeftRight\x15Z\r';
  final begin = text.indexOf('\x13');
  final separator = text.indexOf('\x14');
  final end = text.indexOf('\x15');
  bool hiddenAt(int cp) {
    if (cp == begin) return markerMask & 1 != 0;
    if (cp == separator) return markerMask & 2 != 0;
    if (cp == end) return markerMask & 4 != 0;
    if (cp > begin && cp < separator) return instructionHidden;
    if (cp > separator && cp < end) {
      return resultMask & (cp < separator + 5 ? 1 : 2) != 0;
    }
    return false;
  }

  final width = compressed ? 1 : 2;
  final runs = <WordFixtureFkpRun>[];
  var start = 0;
  for (var cp = 1; cp <= text.length; cp++) {
    if (cp < text.length && hiddenAt(cp) == hiddenAt(start)) continue;
    runs.add(
      WordFixtureFkpRun(
        8192 + start * width,
        8192 + cp * width,
        properties: wordSprm(0x083c, [hiddenAt(start) ? 1 : 0]),
      ),
    );
    start = cp;
  }
  return StructuredWordFixture(
    pieces: [WordFixturePiece(text, compressed: compressed)],
    characterRuns: runs,
  ).build();
}

Uint8List fieldInstructionFormattingFixture(
  String text,
  List<(int, int)> hiddenCpRanges,
) {
  bool hiddenAt(int cp) =>
      hiddenCpRanges.any((range) => cp >= range.$1 && cp < range.$2);
  bool specialAt(int cp) => const [19, 20, 21].contains(text.codeUnitAt(cp));
  final runs = <WordFixtureFkpRun>[];
  var start = 0;
  for (var cp = 1; cp <= text.length; cp++) {
    if (cp < text.length &&
        hiddenAt(cp) == hiddenAt(start) &&
        specialAt(cp) == specialAt(start)) {
      continue;
    }
    runs.add(
      WordFixtureFkpRun(
        8192 + start * 2,
        8192 + cp * 2,
        properties: [
          ...wordSprm(0x083c, [hiddenAt(start) ? 1 : 0]),
          ...wordSprm(0x0855, [specialAt(start) ? 1 : 0]),
        ],
      ),
    );
    start = cp;
  }
  final positions = <int>[], records = <int>[];
  var depth = 0;
  final modes = <bool>[];
  for (var cp = 0; cp < text.length; cp++) {
    final unit = text.codeUnitAt(cp);
    if (!const [19, 20, 21].contains(unit)) continue;
    positions.add(cp);
    var flags = 0;
    if (unit == 19) {
      depth++;
      modes.add(false);
      final type = RegExp(
        r'^\s*(REF|QUOTE|IF)\b',
      ).firstMatch(text.substring(cp + 1))!.group(1);
      flags = {'REF': 3, 'QUOTE': 35, 'IF': 7}[type]!;
    } else if (unit == 20) {
      modes[modes.length - 1] = true;
    } else {
      flags = (modes.removeLast() ? 0x80 : 0) | 0x10 | (depth > 1 ? 0x40 : 0);
      depth--;
    }
    records.addAll([unit, flags]);
  }
  return StructuredWordFixture(
    pieces: [WordFixturePiece(text, compressed: false)],
    characterRuns: runs,
    extraTablePairs: {
      16: storyPlc([...positions, 0xffffffff], records),
    },
  ).build();
}

class FieldInstructionFormattingCase {
  const FieldInstructionFormattingCase(
    this.name,
    this.text,
    this.hiddenCpRanges,
    this.expectedRangesByStart, {
    this.scalarFormattingSplit = false,
  });
  final String name, text;
  final List<(int, int)> hiddenCpRanges;
  final Map<int, List<(int, int)>> expectedRangesByStart;
  final bool scalarFormattingSplit;
  Uint8List bytes() => fieldInstructionFormattingFixture(text, hiddenCpRanges);
}

List<FieldInstructionFormattingCase> fieldInstructionFormattingCases() {
  const partial = 'A\x13 QUOTE "Visible Hidden Visible" \x14Cached\x15Z\r';
  final hidden = partial.indexOf('Hidden');
  const paragraph = 'A\x13 QUOTE "one\rtwo\t😀three" \x14Cached\x15Z\r';
  final one = paragraph.indexOf('one'), three = paragraph.indexOf('three');
  const nested =
      'A\x13 IF \x13 QUOTE "Child" \x14HiddenChild\x15 = "x" "yes" "no" \x14Cached\x15Z\r';
  final child = nested.indexOf('\x13', 2),
      childSeparator = nested.indexOf('\x14');
  final childEnd = nested.indexOf('\x15') + 1,
      outerSeparator = nested.lastIndexOf('\x14');
  const noResult = 'A\x13 QUOTE "none" \x15Z\r';
  final noResultEnd = noResult.indexOf('\x15');
  const scalar = 'A\x13 QUOTE "😀" \x14Cached\x15Z\r';
  final emoji = scalar.indexOf('😀');
  return [
    FieldInstructionFormattingCase(
      'partial',
      partial,
      [(hidden, hidden + 6)],
      {
        1: [(hidden - 2, hidden + 4)],
      },
    ),
    FieldInstructionFormattingCase(
      'paragraph-control',
      paragraph,
      [(one, three)],
      {
        1: [(one - 2, three - 2)],
      },
    ),
    FieldInstructionFormattingCase(
      'nested-ownership',
      nested,
      [(2, outerSeparator)],
      {
        1: [(0, child - 2), (childEnd - 2, outerSeparator - 2)],
        child: [(0, childSeparator - child - 1)],
      },
    ),
    FieldInstructionFormattingCase(
      'no-result',
      noResult,
      [(2, noResultEnd)],
      {
        1: [(0, noResultEnd - 2)],
      },
    ),
    FieldInstructionFormattingCase(
      'scalar-leading-style',
      scalar,
      [(emoji, emoji + 1)],
      {
        1: [(emoji - 2, emoji)],
      },
      scalarFormattingSplit: true,
    ),
    FieldInstructionFormattingCase(
      'scalar-trailing-style',
      scalar,
      [(emoji + 1, emoji + 2)],
      {1: []},
      scalarFormattingSplit: true,
    ),
  ];
}
