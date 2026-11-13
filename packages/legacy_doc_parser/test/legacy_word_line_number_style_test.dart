// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

List<int> _fonts() => [
  ...wordU16(2),
  ...wordU16(0),
  for (final name in ['Body Face', 'Number Face']) ...[
    41 + name.length * 2,
    ...List.filled(39, 0),
    for (final unit in name.codeUnits) ...wordU16(unit),
    ...wordU16(0),
  ],
];

Uint8List _source(Map<int, WordFixtureStyle> styles) => StructuredWordFixture(
  pieces: const [WordFixturePiece('Body\r')],
  styles: {
    0: WordFixtureStyle(
      name: 'Normal',
      builtinId: 0,
      characterProperties: [
        ...wordSprm(0x4a4f, wordU16(0)),
        ...wordSprm(0x4a43, wordU16(22)),
      ],
    ),
    ...styles,
  },
  sections: [
    WordFixtureSection(5, [
      ...wordSprm(0x5015, wordU16(2)),
      ...wordSprm(0x501b, wordU16(3)),
      ...wordSprm(0x9016, wordU16(240)),
    ]),
  ],
  extraTablePairs: {15: _fonts()},
).build();

XmlDocument _xml(LegacyWordDocument document, String part) {
  final zip = ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  );
  return XmlDocument.parse(utf8.decode(zip.findFile(part)!.content));
}

XmlElement _lineStyle(LegacyWordDocument document) =>
    _xml(document, 'word/styles.xml')
        .findAllElements('style', namespace: _w)
        .singleWhere(
          (e) => e.getAttribute('styleId', namespace: _w) == 'LineNumber',
        );

void main() {
  test(
    'native authored Line Number style keeps its source glyph formatting',
    () {
      final bytes = File(
        'test/fixtures/word_native/line-number-style.doc',
      ).readAsBytesSync();
      final document = parseLegacyWordDocument(bytes);
      // Independent STSH inspection: istd16, sti40, character style, parent15;
      // CHPX contains font index8, 28 half-points, CC2233 and bold=true.
      final style = document.lineNumberStyle!;
      expect(style.fontName, 'Courier New');
      expect(style.scriptFonts!.nonAscii, 'Courier New');
      expect(style.fontSizeHalfPoints, 28);
      expect(style.colorHex, 'CC2233');
      expect(style.bold, isTrue);
      final output = _lineStyle(document);
      expect(output.getAttribute('type', namespace: _w), 'character');
      expect(
        output
            .findElements('name', namespace: _w)
            .single
            .getAttribute('val', namespace: _w),
        'line number',
      );
      final props = output.findElements('rPr', namespace: _w).single;
      expect(
        props
            .findElements('sz', namespace: _w)
            .single
            .getAttribute('val', namespace: _w),
        '28',
      );
      expect(
        props
            .findElements('color', namespace: _w)
            .single
            .getAttribute('val', namespace: _w),
        'CC2233',
      );
      expect(document.sections.single.layout.lineNumberInterval, 1);
      expect(document.sections.single.layout.lineNumberStart, 1);
    },
  );

  test(
    'built-in identity survives localized name, index and inherited resets',
    () {
      final document = parseLegacyWordDocument(
        _source({
          21: WordFixtureStyle(
            name: 'Parent format',
            character: true,
            characterProperties: [
              ...wordSprm(0x4a4f, wordU16(1)),
              ...wordSprm(0x4a51, wordU16(1)),
              ...wordSprm(0x4a43, wordU16(28)),
              ...wordSprm(0x0835, [1]),
              ...wordSprm(0x6870, [0x11, 0x22, 0x33, 0]),
            ],
          ),
          25: WordFixtureStyle(
            name: 'Zeilennummer',
            builtinId: 40,
            parentIndex: 21,
            character: true,
            characterProperties: [
              ...wordSprm(0x0835, [0]),
              ...wordSprm(0x0836, [1]),
            ],
          ),
        }),
      );
      final style = document.lineNumberStyle!;
      expect(style.fontName, 'Number Face');
      expect(style.fontSizeHalfPoints, 28);
      expect(style.colorHex, '112233');
      expect(style.bold, isFalse);
      expect(style.italic, isTrue);
      final body = document.blocks.single as LegacyWordParagraph;
      expect(body.runs.single.style.fontName, 'Body Face');
      expect(body.runs.single.style.fontSizeHalfPoints, 22);
      final xml = _xml(document, 'word/document.xml');
      final numbering = xml.findAllElements('lnNumType', namespace: _w).single;
      expect(numbering.getAttribute('start', namespace: _w), '3');
      expect(numbering.getAttribute('countBy', namespace: _w), '2');
      final props = _lineStyle(
        document,
      ).findElements('rPr', namespace: _w).single;
      expect(
        props
            .findElements('b', namespace: _w)
            .single
            .getAttribute('val', namespace: _w),
        '0',
      );
      expect(
        props
            .findElements('i', namespace: _w)
            .single
            .getAttribute('val', namespace: _w),
        '1',
      );
    },
  );

  test('a matching display name does not invent the built-in style', () {
    final document = parseLegacyWordDocument(
      _source({
        25: const WordFixtureStyle(name: 'line number', character: true),
      }),
    );
    expect(document.lineNumberStyle, isNull);
    expect(
      _xml(document, 'word/styles.xml')
          .findAllElements('style', namespace: _w)
          .where((e) => e.getAttribute('type', namespace: _w) == 'character'),
      isEmpty,
    );
  });

  test('absent style preserves source line and note numbering semantics', () {
    final document = parseLegacyWordDocument(
      File(
        'test/fixtures/word_native/word-compatibility.doc',
      ).readAsBytesSync(),
    );
    expect(document.lineNumberStyle, isNull);
    expect(document.sections.first.layout.lineNumberStart, 4);
    expect(
      document.sections.first.layout.lineNumberRestart,
      LegacyWordLineNumberRestart.newSection,
    );
    expect(document.sections.map((s) => s.layout.footnoteNumbering.start), [
      1,
      1,
    ]);
    expect(
      document.compatibility[LegacyWordCompatibilityFlag
          .balanceSingleByteDoubleByteWidth],
      isTrue,
    );
  });

  for (final (name, styles) in <(String, Map<int, WordFixtureStyle>)>[
    (
      'duplicate identity',
      {
        20: const WordFixtureStyle(name: 'A', builtinId: 40, character: true),
        21: const WordFixtureStyle(name: 'B', builtinId: 40, character: true),
      },
    ),
    (
      'paragraph with character identity',
      {20: const WordFixtureStyle(name: 'A', builtinId: 40)},
    ),
    (
      'missing parent',
      {
        20: const WordFixtureStyle(
          name: 'A',
          builtinId: 40,
          character: true,
          parentIndex: 21,
        ),
      },
    ),
    (
      'cyclic parent',
      {
        20: const WordFixtureStyle(
          name: 'A',
          builtinId: 40,
          character: true,
          parentIndex: 21,
        ),
        21: const WordFixtureStyle(name: 'B', character: true, parentIndex: 20),
      },
    ),
  ]) {
    test('rejects ambiguous or invalid line style: $name', () {
      expect(
        () => parseLegacyWordDocument(_source(styles)),
        throwsFormatException,
      );
    });
  }

  test('public optional style serializes without any body or table style', () {
    const document = LegacyWordDocument(
      blocks: [],
      sections: [],
      plainText: '',
      safeHtml: '',
      lineNumberStyle: LegacyWordCharacterStyle(
        fontName: 'Number Face',
        fontSizeHalfPoints: 28,
      ),
    );
    final style = _lineStyle(document);
    final fonts = style.findAllElements('rFonts', namespace: _w).single;
    expect(fonts.getAttribute('ascii', namespace: _w), 'Number Face');
    expect(
      convertLegacyWordDocument(document).preservedCounts['lineNumberStyles'],
      1,
    );
  });
}
