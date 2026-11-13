// SPDX-License-Identifier: MPL-2.0
// Independently authored binary input for opt-in native review checks. This
// generator never invokes the parser or converter to create its source DOC.
import 'dart:io';

import '../../test/support/structured_word_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart section_review_fixture.dart new-output.doc');
    exitCode = 64;
    return;
  }
  const text = 'FIRST SECTION REVIEW MARKER\fSECOND SECTION REVIEW MARKER\r';
  final boundary = text.indexOf('\f') + 1;
  const date = 45 | (8 << 6) | (12 << 11) | (11 << 16) | (126 << 20);
  List<int> byte(int code, int value) => wordSprm(code, [value]);
  List<int> word(int code, int value) => wordSprm(code, wordU16(value));
  final bytes = StructuredWordFixture(
    pieces: const [WordFixturePiece(text)],
    sections: [
      WordFixtureSection(boundary, [
        ...word(0xb01f, 12240),
        ...word(0xb020, 15840),
        ...word(0xb021, 1440),
        ...word(0xb022, 1440),
        ...word(0x9023, 1440),
        ...word(0x9024, 1440),
        ...byte(0x3009, 0),
        ...byte(0x3228, 1),
        ...byte(0x322a, 1),
        ...byte(0x3239, 1),
        ...word(0xb021, 2880),
        ...word(0x500b, 1),
        ...word(0x900c, 720),
        ...byte(0x3009, 2),
        ...byte(0x3228, 0),
        ...byte(0x322a, 0),
        ...wordSprm(0xd243, [7, 1, ...wordU16(1), ...wordU32(date)]),
        ...wordSprm(0x703a, wordU32(0x12345678)),
      ]),
      WordFixtureSection(text.length, [
        ...word(0xb01f, 12240),
        ...word(0xb020, 15840),
        ...word(0xb021, 1440),
        ...word(0xb022, 1440),
        ...word(0x9023, 1440),
        ...word(0x9024, 1440),
      ]),
    ],
    extraTablePairs: {
      51: [
        ...wordU16(0xffff),
        ...wordU16(2),
        ...wordU16(0),
        for (final author in ['Unknown', 'Alice']) ...[
          ...wordU16(author.length),
          for (final unit in author.codeUnits) ...wordU16(unit),
        ],
      ],
    },
  ).build();
  File(arguments.single)
    ..createSync(exclusive: true)
    ..writeAsBytesSync(bytes, flush: true);
}
