// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';

/// Literal DOP and SEPX data with one automatically numbered note of each
/// kind. The input is authored without consulting the parser's format table.
Uint8List noteFormatFixture({
  int? dopFootnoteFormat,
  int? dopEndnoteFormat,
  int dopSize = 500,
  List<int> sectionProperties = const [],
  int? fibNewVersion,
}) {
  const main = 'Foot\x02 End\x02\r',
      foot = '\x02Footnote text\r',
      end = '\x02Endnote text\r';
  final dop = Uint8List(dopSize), data = ByteData.sublistView(dop);
  if (dopFootnoteFormat != null || dopEndnoteFormat != null) {
    // DOP starts are 4 and 7, both restarting per section. A source offset
    // from a section SPRM must not overwrite these dormant-start cases.
    data.setUint16(0, 1 << 5, Endian.little);
    data.setUint16(2, (4 << 2) | 1, Endian.little);
    data.setUint16(52, (7 << 2) | 1, Endian.little);
    data.setUint16(54, 3, Endian.little);
    if (dopSize >= 496) {
      data.setUint16(492, dopFootnoteFormat ?? 0, Endian.little);
      data.setUint16(494, dopEndnoteFormat ?? 2, Endian.little);
    }
  }
  return storyWordFixture(
    main: main,
    footnotes: '$foot\r',
    endnotes: '$end\r',
    sections: [WordFixtureSection(main.length, sectionProperties)],
    tablePairs: {
      2: storyPlc([4, 0xffffffff], wordU16(1)),
      3: storyPlc([0, foot.length, 0xffffffff]),
      46: storyPlc([9, 0xffffffff], wordU16(1)),
      47: storyPlc([0, end.length, 0xffffffff]),
      51: storyBookmarkNames(['Unknown', 'Alice']),
      if (dopFootnoteFormat != null || dopEndnoteFormat != null) 31: dop,
    },
    mutate: (word, _) {
      if (fibNewVersion != null) {
        word.setUint16(154 + 93 * 8, 2, Endian.little);
        word.setUint16(156 + 93 * 8, fibNewVersion, Endian.little);
      }
    },
  );
}

List<int> noteFormatSection(int foot, int end) => [
  ...wordSprm(0x5040, wordU16(foot)),
  ...wordSprm(0x5042, wordU16(end)),
];

const noteFormatSchemaCases = <String, (int, int, bool)>{
  'note-formats-east-asian-sepx': (0x0b, 0x26, false),
  'note-formats-korean-sepx': (0x29, 0x2b, false),
  'note-formats-rtl-dop': (0x2d, 0x30, true),
  'note-formats-south-asian-dop': (0x31, 0x37, true),
  'note-formats-cyrillic-sepx': (0x3a, 0x3b, false),
  'note-formats-none-sepx': (0xff, 0xff, false),
  'note-formats-fallback-sepx': (0x17, 0x28, false),
  'note-formats-unknown-sepx': (0xffff, 0x3c, false),
};

Uint8List noteFormatRevisionFixture({bool fallbackHistory = false}) {
  const date = 45 | (8 << 6) | (12 << 11) | (11 << 16) | (126 << 20);
  return noteFormatFixture(
    sectionProperties: [
      ...noteFormatSection(fallbackHistory ? 0x17 : 0x0b, 0x2d),
      ...wordSprm(0x3239, [1]),
      ...noteFormatSection(0xff, 0x37),
      ...wordSprm(0xd243, [7, 1, ...wordU16(1), ...wordU32(date)]),
    ],
  );
}
