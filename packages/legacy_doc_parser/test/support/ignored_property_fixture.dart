// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'decorated_word_fixture.dart';
import 'list_word_fixture.dart';
import 'structured_word_fixture.dart';
import 'table_word_fixture.dart';

const ignoredListLevelModes = [
  'direct',
  'inherited',
  'piece',
  'removed-after',
  'sentinel',
];

Uint8List ignoredListLevelFixture(int level, String mode) {
  final property = wordSprm(0x260a, [level]);
  return StructuredWordFixture(
    pieces: [
      WordFixturePiece(
        'Text\r',
        prm: mode == 'piece' ? (level << 8) | (0x0c << 1) : 0,
      ),
    ],
    styles: {
      0: WordFixtureStyle(
        name: 'Normal',
        builtinId: 0,
        paragraphProperties: mode == 'inherited' ? property : const [],
      ),
    },
    paragraphRuns: [
      WordFixtureFkpRun(
        8192,
        8197,
        properties: [
          if (mode == 'removed-after') ...wordSprm(0x460b, wordU16(1)),
          if (mode != 'inherited' && mode != 'piece') ...property,
          if (mode == 'removed-after') ...wordSprm(0x460b, wordU16(0)),
          if (mode == 'sentinel') ...wordSprm(0x460b, wordU16(0xf801)),
        ],
      ),
    ],
  ).build();
}

Uint8List activeListLevelFixture(int level, {bool levelFirst = false}) =>
    listWordFixture(
      paragraph: [
        if (levelFirst) ...wordSprm(0x260a, [level]),
        ...wordSprm(0x460b, wordU16(1)),
        if (!levelFirst) ...wordSprm(0x260a, [level]),
      ],
    );

Uint8List historicalListLevelFixture({required bool previousNumbered}) =>
    listWordFixture(
      paragraph: [
        ...wordSprm(0x460b, wordU16(previousNumbered ? 1 : 0)),
        ...wordSprm(0x260a, [255]),
        ...wordSprm(0x2664, [1]),
        ...wordSprm(0x460b, wordU16(previousNumbered ? 0 : 1)),
        ...wordSprm(0x260a, [0]),
      ],
    );

Uint8List legacyNumberingParentFixture({
  bool resolved = true,
  bool history = false,
  bool linked = false,
  bool replaceLevel = true,
  int legacyId = 2047,
}) => listWordFixture(
  paragraph: [
    ...wordSprm(0x4600, wordU16(20)),
    if (history) ...wordSprm(0x2664, [1]),
    if (resolved) ...wordSprm(0x4600, wordU16(21)),
  ],
  listStyle: linked ? 21 : 0x0fff,
  styles: {
    0: const WordFixtureStyle(name: 'Normal', builtinId: 0),
    20: WordFixtureStyle(
      name: 'Legacy list',
      parentIndex: 0,
      paragraphProperties: [
        ...wordSprm(0x260a, [10]),
        ...wordSprm(0x460b, wordU16(legacyId)),
        // ANLD80: decimal number with a dot suffix and a start of one.
        // The old numbering is deliberately retained, never interpreted as
        // a modern list index or fabricated numbering definition.
        ...wordSprm(0xc63e, [
          84,
          0,
          0,
          1,
          0,
          0,
          0,
          ...wordU16(0),
          ...wordU16(24),
          ...wordU16(1),
          ...wordU16(0),
          ...wordU16(0),
          0,
          0,
          0,
          0,
          ...wordU16(46),
          ...List.filled(62, 0),
        ]),
      ],
    ),
    21: WordFixtureStyle(
      name: 'Modern list',
      parentIndex: 20,
      paragraphProperties: [
        if (replaceLevel) ...wordSprm(0x260a, [0]),
        ...wordSprm(0x460b, wordU16(1)),
      ],
    ),
  },
);

const ignoredBorderModes = [
  'paragraph-direct',
  'paragraph-inherited',
  'paragraph-absent',
  'row',
  'range',
  'tc80',
  'tc80-repeat',
  'table-style',
  'conditional-style',
];

List<int> _border({bool old = false, int type = 1, bool nil = false}) => nil
    ? List.filled(old ? 4 : 8, 255)
    : old
    ? [8, type, 6, 0]
    : type == 255
    ? [255, 255, 255, 255, 255, 255, 224, 255]
    : [255, 0, 0, 0, 8, type, 0, 0];

List<int> _rowBorders({bool old = false, int type = 1}) =>
    wordSprm(old ? 0xd605 : 0xd613, [
      old ? 24 : 48,
      for (var side = 0; side < 6; side++) ..._border(old: old, type: type),
    ]);

List<int> _rangeBorder({bool old = false, int type = 1, bool nil = false}) =>
    wordSprm(old ? 0xd620 : 0xd62f, [
      old ? 7 : 11,
      0,
      1,
      1,
      ..._border(old: old, type: type, nil: nil),
    ]);

List<int> _definition(int topType) {
  final data = [
    1,
    ...wordU16(0),
    ...wordU16(1000),
    ...wordU16(0),
    ...wordU16(0),
    ..._border(old: true, type: topType),
    ...List.filled(12, 0),
  ];
  return wordSprm(0xd608, [...wordU16(data.length + 1), ...data]);
}

Uint8List ignoredBorderFixture(
  String mode, {
  bool old = false,
  int ignoredType = 255,
  bool nil = false,
}) {
  if (mode.startsWith('paragraph-')) {
    final first = wordParagraphBorder(0, old: old, color: old ? 6 : 255);
    final ignored = wordParagraphBorder(
      0,
      old: old,
      type: ignoredType,
      color: old ? 255 : 0xff000000,
      width: 255,
      unused: old ? 128 : 255,
    );
    return paragraphDecorationFixture([
      ...(mode == 'paragraph-direct' ? first : const <int>[]),
      ...ignored,
    ], inherited: mode == 'paragraph-inherited' ? first : const []);
  }
  final conditionFirst = wordSprm(0xd47f, [8, ..._border()]);
  final conditionIgnored = wordSprm(0xd47f, [8, ..._border(type: ignoredType)]);
  final conditionProperties = [...conditionFirst, ...conditionIgnored];
  final tableStyle = <int>[
    ..._rowBorders(old: old),
    if (mode == 'table-style') ..._rowBorders(old: old, type: ignoredType),
    if (mode == 'conditional-style')
      ...wordSprm(0xd66a, [
        conditionProperties.length + 2,
        ...wordU16(1),
        ...conditionProperties,
      ]),
  ];
  return tableFixture(
    [
      const TableFixtureParagraph('Cell\x07', depth: 1, cell: true),
      TableFixtureParagraph(
        '\x07',
        depth: 1,
        row: true,
        widths: const [1000],
        extra: [
          if (mode.endsWith('style')) ...[
            ...wordSprm(0x563a, wordU16(20)),
            ...wordSprm(0x740a, [...wordU16(0), ...wordU16(0x20)]),
          ],
          if (mode == 'row' || mode == 'tc80') ..._rowBorders(old: old),
          if (mode == 'row') ..._rowBorders(old: old, type: ignoredType),
          if (mode == 'range') ...[
            ..._rangeBorder(old: old),
            ..._rangeBorder(old: old, type: ignoredType, nil: nil),
          ],
          if (mode == 'tc80-repeat') ..._definition(1),
          if (mode == 'tc80' || mode == 'tc80-repeat')
            ..._definition(ignoredType),
        ],
      ),
    ],
    styles: {
      0: const WordFixtureStyle(name: 'Normal', builtinId: 0),
      if (mode.endsWith('style'))
        20: WordFixtureStyle(
          name: 'Border style',
          table: true,
          tableProperties: tableStyle,
        ),
    },
  );
}

Uint8List invalidAuthorTableFixture() => StructuredWordFixture(
  pieces: const [WordFixturePiece('Text\r')],
  extraTablePairs: {51: List.filled(22, 0)},
).build();
