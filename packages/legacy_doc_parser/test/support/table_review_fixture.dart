// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';
import 'table_word_fixture.dart';

const tableReviewDate = 45 | (8 << 6) | (12 << 11) | (11 << 16) | (126 << 20);

List<int> rowReviewProperties({int? height, bool? cantSplit, bool? header}) => [
  if (height != null) ...wordSprm(0x9407, wordU16(height)),
  if (cantSplit != null) ...[
    ...wordSprm(0x3403, [cantSplit ? 1 : 0]),
    ...wordSprm(0x3466, [cantSplit ? 1 : 0]),
  ],
  if (header != null) ...wordSprm(0x3404, [header ? 1 : 0]),
];

List<int> rowReviewMark({int author = 1, int marked = 1}) => wordSprm(0xd667, [
  7,
  marked,
  ...wordU16(author),
  ...wordU32(tableReviewDate),
]);

/// Literal PAPX table rows, with an independently declared font and page size.
/// Source DOC controls never use conversion or review-projection helpers.
Uint8List tableReviewFixture(
  List<(String, List<int>)> rows, {
  bool defineBeforeProperties = true,
  bool explicitMargins = true,
}) {
  final name = 'Liberation Serif'.codeUnits;
  final font = [
    ...List<int>.filled(40, 0),
    for (final unit in name) ...wordU16(unit),
    ...wordU16(0),
  ];
  font[0] = font.length - 1;
  final paragraphs = <(String, List<int>)>[
    ('BODY\r', []),
    for (final (text, properties) in rows) ...[
      ('$text\x07', wordSprm(0x2416, [1])),
      (
        '\x07',
        [
          ...wordSprm(0x2416, [1]),
          ...wordSprm(0x2417, [1]),
          if (defineBeforeProperties) ...tableFixtureDefinition([4320]),
          if (explicitMargins)
            ...wordSprm(0xd634, [6, 0, 1, 10, 3, ...wordU16(108)]),
          ...properties,
          if (!defineBeforeProperties) ...tableFixtureDefinition([4320]),
        ],
      ),
    ],
    ('AFTER\r', []),
  ];
  var cp = 0;
  final runs = <WordFixtureFkpRun>[];
  for (final (text, properties) in paragraphs) {
    runs.add(
      WordFixtureFkpRun(
        8192 + cp,
        8192 + cp + text.length,
        properties: properties,
      ),
    );
    cp += text.length;
  }
  return StructuredWordFixture(
    pieces: [WordFixturePiece(paragraphs.map((p) => p.$1).join())],
    paragraphRuns: runs,
    extraTablePairs: {
      15: [...wordU16(1), ...wordU16(0), ...font],
      51: storyBookmarkNames(['Unknown', 'Alice']),
    },
    styles: {
      0: WordFixtureStyle(
        name: 'Normal',
        builtinId: 0,
        paragraphProperties: [
          ...wordSprm(0x6412, [...wordU16(-240), ...wordU16(0)]),
          ...wordSprm(0xa413, wordU16(0)),
          ...wordSprm(0xa414, wordU16(0)),
          ...wordSprm(0x2431, [0]),
          ...wordSprm(0x2405, [0]),
          ...wordSprm(0x2406, [0]),
        ],
        characterProperties: [
          ...wordSprm(0x4a4f, wordU16(0)),
          ...wordSprm(0x4a43, wordU16(24)),
        ],
      ),
    },
    sections: [
      WordFixtureSection(cp, [
        ...wordSprm(0xb01f, wordU16(7200)),
        ...wordSprm(0xb020, wordU16(4320)),
        ...wordSprm(0xb021, wordU16(720)),
        ...wordSprm(0xb022, wordU16(720)),
        ...wordSprm(0x9023, wordU16(720)),
        ...wordSprm(0x9024, wordU16(720)),
      ]),
    ],
  ).build(
    mutate: (word, _) {
      word.setUint16(2, 0x101, Endian.little);
      word.setUint16(152, 136, Endian.little);
    },
  );
}

const tableReviewCases = ['height', 'split', 'header'];

Uint8List tableReviewControl(
  String kind,
  String state, {
  bool explicitMargins = true,
  bool dormantSecondHeader = false,
}) {
  if (!tableReviewCases.contains(kind) ||
      !const ['review', 'accepted', 'rejected'].contains(state)) {
    throw ArgumentError('Unknown table review fixture.');
  }
  final old = switch (kind) {
    'height' => rowReviewProperties(height: 240, cantSplit: false),
    'split' => rowReviewProperties(height: 0, cantSplit: false),
    _ => rowReviewProperties(height: 240, header: true),
  };
  final current = switch (kind) {
    'height' => rowReviewProperties(height: 720, cantSplit: true),
    'split' => rowReviewProperties(height: 0, cantSplit: true),
    _ => rowReviewProperties(height: 240, header: false),
  };
  final properties = switch (state) {
    // The native DOC reader treats a present TTableHeader=0 as enabled in
    // the measured build. The independent accepted control uses the format's
    // absent/default false state; the review source retains explicit true->0.
    'accepted' when kind == 'header' => rowReviewProperties(height: 240),
    'accepted' => current,
    'rejected' => old,
    _ => [
      ...old,
      ...wordSprm(0x3668, [1]),
      ...current,
      ...rowReviewMark(),
    ],
  };
  return tableReviewFixture(switch (kind) {
    'height' => [
      ('CELL', properties),
      ('NEXT', rowReviewProperties(height: 0)),
    ],
    'split' => [
      ('PREFIX', rowReviewProperties(height: 1800)),
      ('ROW2A\x0bROW2B\x0bROW2C\x0bROW2D\x0bROW2E\x0bROW2F', properties),
    ],
    _ => [
      ('HEADER_ONE', properties),
      (
        'HEADER_TWO',
        rowReviewProperties(
          height: 240,
          header: dormantSecondHeader ? true : null,
        ),
      ),
      ('TALL', rowReviewProperties(height: 2000)),
      ('LAST', rowReviewProperties(height: 240)),
    ],
  }, explicitMargins: explicitMargins);
}
