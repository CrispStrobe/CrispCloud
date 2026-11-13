// SPDX-License-Identifier: MPL-2.0
// Independently authored FFN bytes, including exact primary-name duplicates.
import 'dart:typed_data';

import 'structured_word_fixture.dart';

Uint8List fontCharsetWordFixture(
  List<(String, int)> fonts, {
  int selectedFont = 0,
  String text = '\uf0fc',
}) => StructuredWordFixture(
  pieces: [WordFixturePiece('$text\r', compressed: false)],
  characterRuns: [
    WordFixtureFkpRun(
      8192,
      8192 + (text.length + 1) * 2,
      properties: [
        ...wordSprm(0x4a4f, wordU16(selectedFont)),
        ...wordSprm(0x4a51, wordU16(selectedFont)),
      ],
    ),
  ],
  extraTablePairs: {
    15: [
      ...wordU16(fonts.length),
      ...wordU16(0),
      for (final (name, charset) in fonts) ...[
        41 + name.length * 2,
        0x16, // FFID: variable pitch, Roman family, TrueType.
        ...wordU16(400),
        charset,
        ...List.filled(35, 0),
        for (final unit in name.codeUnits) ...wordU16(unit),
        ...wordU16(0),
      ],
    ],
  },
).build();
