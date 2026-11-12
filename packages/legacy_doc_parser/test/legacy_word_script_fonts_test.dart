// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/list_word_fixture.dart';
import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _names = ['ASCII Face', 'East Asian Face', 'Other Face', 'Complex Face'];

List<int> _fonts() => [
  ...wordU16(_names.length),
  ...wordU16(0),
  for (final name in _names) ...[
    41 + name.length * 2,
    ...List.filled(39, 0),
    for (final unit in name.codeUnits) ...wordU16(unit),
    ...wordU16(0),
  ],
];

List<int> _indices({
  int ascii = 0,
  int eastAsia = 1,
  int other = 2,
  int cs = 3,
}) => [
  ...wordSprm(0x4a4f, wordU16(ascii)),
  ...wordSprm(0x4a50, wordU16(eastAsia)),
  ...wordSprm(0x4a51, wordU16(other)),
  ...wordSprm(0x4a5e, wordU16(cs)),
];

Uint8List _source({
  List<int>? normal,
  List<WordFixtureFkpRun> characterRuns = const [],
  Map<int, WordFixtureStyle> styles = const {},
  Map<int, List<int>> pairs = const {},
}) => StructuredWordFixture(
  pieces: const [WordFixturePiece('AB\r')],
  styles: {
    0: WordFixtureStyle(
      name: 'Normal',
      builtinId: 0,
      characterProperties: normal ?? _indices(),
    ),
    ...styles,
  },
  characterRuns: characterRuns,
  extraTablePairs: {15: _fonts(), ...pairs},
).build();

XmlDocument _part(Uint8List source, [String name = 'word/document.xml']) {
  final archive = ZipDecoder().decodeBytes(
    convertLegacyWordToStructuredDocx(source).bytes,
  );
  return XmlDocument.parse(utf8.decode(archive.findFile(name)!.content));
}

Map<String, String?> _faces(XmlElement fonts) => {
  for (final slot in ['ascii', 'hAnsi', 'eastAsia', 'cs'])
    slot: fonts.getAttribute(slot, namespace: _w),
};

void main() {
  test('independent binary font slots remain separate in runs and marks', () {
    final bytes = _source();
    final paragraph =
        parseLegacyWordDocument(bytes).blocks.single as LegacyWordParagraph;
    expect(paragraph.runs.single.style.fontName, _names[0]);
    expect(
      paragraph.runs.single.style.scriptFonts,
      const LegacyWordScriptFonts(
        nonAscii: 'Other Face',
        eastAsia: 'East Asian Face',
        complexScript: 'Complex Face',
      ),
    );
    expect(
      paragraph.mark!.style.scriptFonts,
      paragraph.runs.single.style.scriptFonts,
    );
    for (final font in _part(bytes).findAllElements('rFonts', namespace: _w)) {
      expect(_faces(font), {
        'ascii': _names[0],
        'hAnsi': _names[2],
        'eastAsia': _names[1],
        'cs': _names[3],
      });
    }
  });

  test('STSH default font slots use their own source indices', () {
    final bytes = _source(
      normal: const [],
      pairs: {
        // Independently authored STSHI with a complete 20-byte header and no
        // style overrides. Stshif holds ASCII/FE/Other; STSHI adds ftcBi.
        1: [
          ...wordU16(20),
          ...wordU16(0),
          ...wordU16(10),
          ...wordU16(1),
          ...wordU16(0),
          ...wordU16(15),
          ...wordU16(0),
          ...wordU16(0),
          ...wordU16(1),
          ...wordU16(2),
          ...wordU16(3),
        ],
      },
    );
    final font = _part(bytes).findAllElements('rFonts', namespace: _w).last;
    expect(_faces(font), {
      'ascii': _names[0],
      'hAnsi': _names[2],
      'eastAsia': _names[1],
      'cs': _names[3],
    });
  });

  test(
    'a direct East Asian font neither replaces other slots nor merges runs',
    () {
      final bytes = _source(
        characterRuns: [
          const WordFixtureFkpRun(8192, 8193),
          WordFixtureFkpRun(
            8193,
            8195,
            properties: wordSprm(0x4a50, wordU16(3)),
          ),
        ],
      );
      final paragraph =
          parseLegacyWordDocument(bytes).blocks.single as LegacyWordParagraph;
      expect(paragraph.runs.map((r) => r.text), ['A', 'B']);
      expect(paragraph.runs.map((r) => r.style.scriptFonts!.eastAsia), [
        _names[1],
        _names[3],
      ]);
      expect(paragraph.runs.map((r) => r.style.scriptFonts!.nonAscii), [
        _names[2],
        _names[2],
      ]);
      expect(paragraph.runs.map((r) => r.style.fontName), [
        _names[0],
        _names[0],
      ]);
    },
  );

  test('a character style reset restores every inherited font slot', () {
    final bytes = _source(
      styles: {
        20: WordFixtureStyle(
          name: 'Other override',
          character: true,
          characterProperties: wordSprm(0x4a51, wordU16(3)),
        ),
      },
      characterRuns: [
        WordFixtureFkpRun(
          8192,
          8195,
          properties: [
            ..._indices(ascii: 3, eastAsia: 3, other: 3, cs: 0),
            ...wordSprm(0x4a30, wordU16(20)),
          ],
        ),
      ],
    );
    final font = _part(bytes).findAllElements('rFonts', namespace: _w).last;
    expect(_faces(font), {
      'ascii': _names[0],
      'hAnsi': _names[3],
      'eastAsia': _names[1],
      'cs': _names[3],
    });
  });

  for (final (code, slot) in [
    (0x4a50, 'eastAsia'),
    (0x4a51, 'hAnsi'),
    (0x4a5e, 'cs'),
  ]) {
    test('an invalid $slot index does not silently reuse the ASCII font', () {
      final bytes = _source(
        characterRuns: [
          WordFixtureFkpRun(
            8192,
            8195,
            properties: wordSprm(code, wordU16(99)),
          ),
        ],
      );
      final document = parseLegacyWordDocument(bytes);
      expect(
        document.warnings,
        contains(LegacyWordWarning.unsupportedFormatting),
      );
      final font = _part(bytes).findAllElements('rFonts', namespace: _w).last;
      expect(font.getAttribute('ascii', namespace: _w), _names[0]);
      expect(font.getAttribute(slot, namespace: _w), isNull);
    });
  }

  test(
    'an explicit marker East Asian font leaves other marker faces inherited',
    () {
      final bytes =
          StructuredWordFixture(
            pieces: const [WordFixturePiece('A\r')],
            paragraphRuns: [
              WordFixtureFkpRun(
                8192,
                8194,
                properties: wordSprm(0x460b, wordU16(1)),
              ),
            ],
            styles: {
              0: WordFixtureStyle(
                name: 'Normal',
                characterProperties: _indices(),
              ),
            },
            extraTablePairs: {
              15: _fonts(),
              73: listFixtureDefinitions([
                listFixtureLevel(character: wordSprm(0x4a50, wordU16(3))),
              ]),
              74: listFixtureInstances(),
            },
          ).build(
            mutate: (word, _) =>
                word.setUint32(158 + 73 * 8, 30, Endian.little),
          );
      final font = _part(
        bytes,
        'word/numbering.xml',
      ).findAllElements('rFonts', namespace: _w).single;
      expect(_faces(font), {
        'ascii': null,
        'hAnsi': null,
        'eastAsia': _names[3],
        'cs': null,
      });
    },
  );

  test('table font masks emit only explicitly authored script slots', () {
    final bytes = StructuredWordFixture(
      pieces: const [WordFixturePiece('A\x07\x07')],
      styles: {
        0: const WordFixtureStyle(name: 'Normal'),
        20: WordFixtureStyle(
          name: 'Table fonts',
          table: true,
          characterProperties: wordSprm(0x4a50, wordU16(1)),
        ),
      },
      paragraphRuns: [
        WordFixtureFkpRun(8192, 8194, properties: wordSprm(0x2416, [1])),
        WordFixtureFkpRun(
          8194,
          8195,
          properties: [
            ...wordSprm(0x2416, [1]),
            ...wordSprm(0x2417, [1]),
            ...tableFixtureDefinition([2000]),
            ...wordSprm(0x563a, wordU16(20)),
          ],
        ),
      ],
      extraTablePairs: {15: _fonts()},
    ).build();
    final style = _part(bytes, 'word/styles.xml')
        .findAllElements('style', namespace: _w)
        .singleWhere(
          (style) => style.getAttribute('type', namespace: _w) == 'table',
        );
    final font = style.findAllElements('rFonts', namespace: _w).single;
    expect(_faces(font), {
      'ascii': null,
      'hAnsi': null,
      'eastAsia': _names[1],
      'cs': null,
    });
  });

  test(
    'retained formatting source declares Cambria and a separate CJK face',
    () {
      final bytes = File(
        'test/fixtures/word_native/formatting.doc',
      ).readAsBytesSync();
      final paragraph = parseLegacyWordDocument(bytes).blocks
          .whereType<LegacyWordParagraph>()
          .singleWhere((p) => p.runs.any((r) => r.text.contains('Unicode')));
      final style = paragraph.runs.first.style;
      expect(style.fontName, 'Cambria');
      expect(style.scriptFonts!.nonAscii, 'Cambria');
      expect(style.scriptFonts!.eastAsia, 'ＭＳ 明朝');
      expect(style.scriptFonts!.complexScript, '');
    },
  );
}
