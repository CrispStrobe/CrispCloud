// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/list_word_fixture.dart';
import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

List<int> _fonts() => [
  ...wordU16(3),
  ...wordU16(0),
  for (final name in ['Times New Roman', 'Arial', 'Courier New']) ...[
    41 + name.length * 2,
    ...List.filled(39, 0),
    for (final unit in name.codeUnits) ...wordU16(unit),
    ...wordU16(0),
  ],
];

Uint8List _source({
  int listId = 1,
  int linkedStyle = 0xfff,
  List<int> marker = const [],
  bool directIndent = false,
}) => StructuredWordFixture(
  pieces: const [WordFixturePiece('List item\r')],
  styles: {
    0: WordFixtureStyle(
      name: 'Normal',
      builtinId: 0,
      characterProperties: wordSprm(0x4a4f, wordU16(1)),
    ),
    20: WordFixtureStyle(
      name: 'List Custom',
      parentIndex: 0,
      paragraphProperties: [
        ...wordSprm(0x460b, wordU16(listId)),
        ...wordSprm(0x845e, wordU16(720)),
        ...wordSprm(0x8460, wordU16(0xfe98)),
      ],
    ),
    21: WordFixtureStyle(
      name: 'Linked List',
      parentIndex: 0,
      characterProperties: wordSprm(0x4a4f, wordU16(2)),
      paragraphProperties: [
        ...wordSprm(0x845e, wordU16(1440)),
        ...wordSprm(0x8460, wordU16(0xfd30)),
      ],
    ),
  },
  paragraphRuns: [
    WordFixtureFkpRun(
      8192,
      8202,
      styleIndex: 20,
      properties: [
        ...wordSprm(0x260a, [0]),
        if (directIndent) ...[
          ...wordSprm(0x845e, wordU16(1080)),
          ...wordSprm(0x8460, wordU16(0xff4c)),
        ],
      ],
    ),
  ],
  extraTablePairs: {
    15: _fonts(),
    73: listFixtureDefinitions([
      listFixtureLevel(
        character: marker,
        paragraph: [
          ...wordSprm(0x845e, wordU16(0)),
          ...wordSprm(0x8460, wordU16(0)),
        ],
      ),
    ], style: linkedStyle),
    74: listFixtureInstances(),
  },
).build(mutate: (word, _) => word.setUint32(158 + 73 * 8, 30, Endian.little));

XmlDocument _part(Uint8List bytes, String name) {
  final archive = ZipDecoder().decodeBytes(bytes);
  return XmlDocument.parse(utf8.decode(archive.findFile(name)!.content));
}

void main() {
  test(
    'an absent LVL marker font inherits the authored paragraph mark font',
    () {
      final document = parseLegacyWordDocument(_source());
      final paragraph = document.blocks.single as LegacyWordParagraph;
      expect(paragraph.mark!.style.fontName, 'Arial');
      expect(paragraph.runs.single.style.fontName, 'Arial');
      expect(
        document.numbering.single.levels.single.characterStyle.fontName,
        isNull,
      );
      final output = convertLegacyWordDocument(document).bytes;
      final numbering = _part(output, 'word/numbering.xml');
      expect(numbering.findAllElements('rFonts', namespace: _w), isEmpty);
      final doc = _part(output, 'word/document.xml');
      final paragraphMark = doc
          .findAllElements('pPr', namespace: _w)
          .single
          .getElement('rPr', namespace: _w)!;
      expect(
        paragraphMark
            .getElement('rFonts', namespace: _w)!
            .getAttribute('ascii', namespace: _w),
        'Arial',
      );
      // No guessed replacement font: native inheritance sees the existing mark.
      expect(numbering.toXmlString(), isNot(contains('Times New Roman')));
    },
  );

  test(
    'an explicit LVL font and linked list style font remain authoritative',
    () {
      for (final linked in [false, true]) {
        final document = parseLegacyWordDocument(
          _source(
            linkedStyle: linked ? 21 : 0xfff,
            marker: linked ? const [] : wordSprm(0x4a4f, wordU16(2)),
          ),
        );
        expect(
          document.numbering.single.levels.single.characterStyle.fontName,
          'Courier New',
        );
        final numbering = _part(
          convertLegacyWordDocument(document).bytes,
          'word/numbering.xml',
        );
        expect(
          numbering
              .findAllElements('rFonts', namespace: _w)
              .single
              .getAttribute('ascii', namespace: _w),
          'Courier New',
        );
      }
    },
  );

  test(
    'marker font inheritance does not hide an invalid explicit font index',
    () {
      final document = parseLegacyWordDocument(
        _source(marker: wordSprm(0x4a4f, wordU16(99))),
      );
      expect(
        document.warnings,
        contains(LegacyWordWarning.unsupportedFormatting),
      );
      expect(
        document.numbering.single.levels.single.characterStyle.fontName,
        isNull,
      );
    },
  );

  test(
    'positive ilfo applies LVL after style and direct indent per MS-DOC',
    () {
      for (final direct in [false, true]) {
        for (final linked in [0xfff, 21]) {
          final document = parseLegacyWordDocument(
            _source(directIndent: direct, linkedStyle: linked),
          );
          final style = (document.blocks.single as LegacyWordParagraph).style;
          expect((style.leftIndentTwips, style.firstLineIndentTwips), (0, 0));
          final xml = _part(
            convertLegacyWordDocument(document).bytes,
            'word/document.xml',
          );
          final indent = xml.findAllElements('ind', namespace: _w).single;
          expect(indent.getAttribute('left', namespace: _w), '0');
          expect(indent.getAttribute('firstLine', namespace: _w), '0');
        }
      }
    },
  );

  test(
    'negative ilfo retains paragraph indent against linked style and LVL',
    () {
      for (final direct in [false, true]) {
        final document = parseLegacyWordDocument(
          _source(listId: 0xffff, linkedStyle: 21, directIndent: direct),
        );
        final style = (document.blocks.single as LegacyWordParagraph).style;
        expect(style.listId, -1);
        expect((
          style.leftIndentTwips,
          style.firstLineIndentTwips,
        ), direct ? (1080, -180) : (720, -360));
        final xml = _part(
          convertLegacyWordDocument(document).bytes,
          'word/document.xml',
        );
        final indent = xml.findAllElements('ind', namespace: _w).single;
        expect(
          indent.getAttribute('left', namespace: _w),
          direct ? '1080' : '720',
        );
        expect(
          indent.getAttribute('hanging', namespace: _w),
          direct ? '180' : '360',
        );
      }
    },
  );
}
