// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';

const invalidStoryUnicodeCases = [
  'split-footnote',
  'split-endnote',
  'split-spare-textbox',
];

/// Independently assembled story boundaries; each complete CLX text buffer has
/// valid UTF-16. The invalid cases split a scalar across independently owned
/// text ranges, rather than across permissible physical piece/FKP boundaries.
Uint8List storyUnicodeFixture(String name) {
  if (name == 'split-footnote' || name == 'split-endnote') {
    final endnote = name == 'split-endnote';
    return storyWordFixture(
      main: 'A\ud83d',
      footnotes: endnote ? '' : '\ude00\r\r',
      endnotes: endnote ? '\ude00\r\r' : '',
      tablePairs: {
        endnote ? 46 : 2: storyPlc([0, 0xffffffff], wordU16(0)),
        endnote ? 47 : 3: storyPlc([0, 2, 0xffffffff]),
      },
    );
  }
  if (name == 'split-spare-textbox') {
    return storyWordFixture(
      main: 'A\r',
      textboxes: '\ud83d\ude00\r\r',
      tablePairs: {
        56: storyPlc(
          [0, 1, 3, 4],
          [
            ..._textboxRecord(reusable: true),
            ..._textboxRecord(shape: 77),
            ..._textboxRecord(),
          ],
        ),
      },
    );
  }
  if (name == 'supplementary-stories') {
    const main = 'A\u{1f600}\x02\r', note = '\x02B\u{1f680}\r';
    return storyWordFixture(
      main: main,
      footnotes: '$note\r',
      tablePairs: {
        2: storyPlc([3, 0xffffffff], wordU16(1)),
        3: storyPlc([0, note.length, 0xffffffff]),
      },
    );
  }
  throw ArgumentError.value(name, 'name', 'Unknown story Unicode case');
}

List<int> _textboxRecord({int shape = 0, bool reusable = false}) => [
  ...wordU32(1),
  ...wordU32(0),
  ...wordU16(reusable ? 1 : 0),
  ...wordU32(0),
  ...wordU32(shape),
  ...wordU32(0),
];
