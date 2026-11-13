// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'story_unicode_fixture.dart';
import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';

const invalidTextUnicodeCases = [
  'lone-high',
  'lone-low',
  'high-before-ascii',
  'reversed-pair',
  'hidden-high',
  'hidden-low',
  'control-between-pair',
  'field-between-pair',
  'split-footnote',
  'split-endnote',
];

/// The UTF-16 cases are authored before display controls or field instructions
/// are stripped. Filtering must not hide bad units or join an invalid pair.
Uint8List textUnicodeFixture(String name) {
  if (name == 'split-footnote' || name == 'split-endnote') {
    return storyUnicodeFixture(name);
  }
  if (name == 'split-physical-pieces') {
    return StructuredWordFixture(
      pieces: const [
        WordFixturePiece('A', offset: 12288),
        WordFixturePiece('\ud83d', offset: 8192, compressed: false),
        WordFixturePiece('\ude00Z\r', offset: 16384, compressed: false),
      ],
    ).build();
  }
  if (name == 'unconsumed-auxiliary') {
    // Text-only extraction promises the main body, not auxiliary validation.
    return storyWordFixture(main: 'Main\r', footnotes: '\ud83d\r');
  }
  final text = switch (name) {
    'lone-high' => 'A\ud83d',
    'lone-low' => 'A\ude00\r',
    'high-before-ascii' => 'A\ud83dZ\r',
    'reversed-pair' => 'A\ude00\ud83d\r',
    'hidden-high' => 'A\x13 QUOTE "\ud83d" \x14Visible\x15Z\r',
    'hidden-low' => 'A\x13 QUOTE "\ude00" \x14Visible\x15Z\r',
    'control-between-pair' => 'A\ud83d\x01\ude00Z\r',
    'field-between-pair' => 'A\ud83d\x13 PAGE \x15\ude00Z\r',
    'valid-field' => 'A\x13 QUOTE "\u{1f600}" \x14\u{1f680}\x15Z\r',
    _ => throw ArgumentError.value(name, 'name'),
  };
  return StructuredWordFixture(
    pieces: [WordFixturePiece(text, compressed: false)],
  ).build();
}
