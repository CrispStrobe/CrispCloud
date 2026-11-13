// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/font_charset_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
Archive _archive(LegacyWordDocument document) =>
    ZipDecoder().decodeBytes(convertLegacyWordDocument(document).bytes);
Map<String, String> _charsets(Archive archive) {
  final part = archive.findFile('word/fontTable.xml');
  if (part == null) return {};
  final xml = XmlDocument.parse(utf8.decode(part.content));
  return {
    for (final font in xml.findAllElements('font', namespace: _w))
      font.getAttribute('name', namespace: _w)!: font
          .findElements('charset', namespace: _w)
          .single
          .getAttribute('val', namespace: _w)!,
  };
}

Map<String, dynamic> _evidence(Archive archive) =>
    (jsonDecode(
              utf8.decode(
                archive.findFile('word/evidence/manifest.json')!.content,
              ),
            )['records']
            as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((record) => record['kind'] == 'sourceFontCharsets');

void main() {
  test('FFN charset and source index survive without remapping PUA text', () {
    final source = fontCharsetWordFixture([
      ('Wingdings', 1),
      ('Wingdings', 2),
    ], selectedFont: 1);
    final original = List<int>.of(source);
    final document = parseLegacyWordDocument(source);
    expect(source, original);
    expect(
      document.fontTable.map(
        (font) => (font.sourceIndex, font.name, font.charset),
      ),
      [(0, 'Wingdings', 1), (1, 'Wingdings', 2)],
    );
    expect(() => document.fontTable.clear(), throwsUnsupportedError);
    final run = (document.blocks.single as LegacyWordParagraph).runs.single;
    expect((run.startCp, run.endCp, run.text), (0, 1, '\uf0fc'));
    expect(run.symbol, isNull);
    expect(run.style.scriptFonts?.nonAscii, 'Wingdings');
    final converted = convertLegacyWordDocument(document);
    expect(converted.preservedCounts['fontCharsets'], 1);
    final archive = ZipDecoder().decodeBytes(converted.bytes);
    expect(_charsets(archive), {'Wingdings': '02'});
    final evidence = _evidence(archive);
    expect(evidence['definitions'], [
      {'sourceIndex': 0, 'name': 'Wingdings', 'charset': 1},
      {'sourceIndex': 1, 'name': 'Wingdings', 'charset': 2},
    ]);
    expect(
      (evidence['decisions'] as List).single['qualification'],
      'explicit symbol charset with a default-charset alias',
    );
  });

  test('exact charset bytes and same-charset aliases are serialized', () {
    final fonts = [
      ('Default Face', 1),
      ('Symbol Face', 2),
      ('ANSI Face', 0),
      ('CJK Face', 128),
      ('Arabic Face', 178),
      ('OEM Face', 255),
      ('Symbol Face', 2),
    ];
    final archive = _archive(
      parseLegacyWordDocument(fontCharsetWordFixture(fonts)),
    );
    expect(_charsets(archive), {
      'Default Face': '01',
      'Symbol Face': '02',
      'ANSI Face': '00',
      'CJK Face': '80',
      'Arabic Face': 'B2',
      'OEM Face': 'FF',
    });
    final relationships = XmlDocument.parse(
      utf8.decode(archive.findFile('word/_rels/document.xml.rels')!.content),
    );
    final relation = relationships
        .findAllElements('Relationship')
        .singleWhere(
          (node) => node.getAttribute('Type')!.endsWith('/fontTable'),
        );
    expect(relation.getAttribute('Target'), 'fontTable.xml');
    final types = XmlDocument.parse(
      utf8.decode(archive.findFile('[Content_Types].xml')!.content),
    );
    expect(
      types
          .findAllElements('Override')
          .singleWhere(
            (node) => node.getAttribute('PartName') == '/word/fontTable.xml',
          )
          .getAttribute('ContentType'),
      'application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml',
    );
  });

  test('only the qualified default and symbol alias combination is merged', () {
    for (final fonts in [
      [('Face', 0), ('Face', 2)],
      [('Face', 1), ('Face', 0)],
      [('Face', 1), ('Face', 128)],
      [('Face', 1), ('Face', 2), ('Face', 0)],
      [('Face', 9)],
      [('Face', 2), ('face', 2)],
    ]) {
      final document = parseLegacyWordDocument(fontCharsetWordFixture(fonts));
      final converted = convertLegacyWordDocument(document);
      final archive = ZipDecoder().decodeBytes(converted.bytes);
      expect(_charsets(archive), isEmpty);
      expect(converted.preservedCounts.containsKey('fontCharsets'), isFalse);
      expect(
        converted.limitations,
        contains(LegacyWordConversionLimitation.partialFormatting),
      );
      final evidence = _evidence(archive);
      expect(evidence['definitions'], hasLength(fonts.length));
      final decision = (evidence['decisions'] as List).single;
      expect(decision['emittedCharset'], isNull);
      expect(decision['qualification'], isNotEmpty);
    }
  });

  test('a guarded font does not suppress independent unambiguous fonts', () {
    final archive = _archive(
      parseLegacyWordDocument(
        fontCharsetWordFixture([
          ('Ambiguous', 0),
          ('Ambiguous', 2),
          ('Other', 128),
        ]),
      ),
    );
    expect(_charsets(archive), {'Other': '80'});
    expect((_evidence(archive)['decisions'] as List), hasLength(2));
  });

  test(
    'font serialization leaves document XML and source glyphs unchanged',
    () {
      final document = parseLegacyWordDocument(
        File(
          'test/fixtures/word_native/symbol-source-control.doc',
        ).readAsBytesSync(),
      );
      expect(document.fontTable[5].name, 'Wingdings');
      expect(document.fontTable[5].charset, 1);
      expect(document.fontTable[6].name, 'Wingdings');
      expect(document.fontTable[6].charset, 2);
      final withoutFonts = LegacyWordDocument(
        blocks: document.blocks,
        sections: document.sections,
        plainText: document.plainText,
        safeHtml: document.safeHtml,
      );
      final before = _archive(withoutFonts), after = _archive(document);
      expect(
        after.findFile('word/document.xml')!.content,
        before.findFile('word/document.xml')!.content,
      );
      expect(_charsets(after)['Wingdings'], '02');
      expect(_charsets(after)['Symbol'], '02');
      final xml = XmlDocument.parse(
        utf8.decode(after.findFile('word/document.xml')!.content),
      );
      expect(xml.findAllElements('sym', namespace: _w), hasLength(1));
      expect(
        xml
            .findAllElements('t', namespace: _w)
            .map((node) => node.innerText)
            .join(),
        contains('\uf0fc'),
      );
    },
  );

  test('absent source font metadata does not invent a font table', () {
    const document = LegacyWordDocument(
      blocks: [],
      sections: [],
      plainText: '',
      safeHtml: '',
    );
    expect(_archive(document).findFile('word/fontTable.xml'), isNull);
  });

  test('empty source names remain evidence without blocking valid fonts', () {
    for (final document in [
      parseLegacyWordDocument(
        fontCharsetWordFixture([('', 1), ('Wingdings', 2)], selectedFont: 1),
      ),
      parseLegacyWordDocument(
        File('test/fixtures/word_native/formatting.doc').readAsBytesSync(),
      ),
    ]) {
      final empty = document.fontTable.singleWhere((font) => font.name.isEmpty);
      final archive = _archive(document);
      expect(_charsets(archive), isNotEmpty);
      expect(_charsets(archive).containsKey(''), isFalse);
      final evidence = _evidence(archive);
      expect(
        (evidence['definitions'] as List).singleWhere(
          (item) => item['sourceIndex'] == empty.sourceIndex,
        ),
        {'sourceIndex': empty.sourceIndex, 'name': '', 'charset': 1},
      );
      expect(
        (evidence['decisions'] as List).singleWhere(
          (item) => item['name'] == '',
        ),
        {
          'name': '',
          'sourceIndices': [empty.sourceIndex],
          'emittedCharset': null,
          'qualification': 'empty source font name',
        },
      );
    }
  });

  test(
    'invalid public font metadata and duplicate source indices fail closed',
    () {
      for (final fonts in [
        [
          const LegacyWordFontDefinition(
            sourceIndex: -1,
            name: 'Face',
            charset: 2,
          ),
        ],
        [
          const LegacyWordFontDefinition(
            sourceIndex: 4096,
            name: 'Face',
            charset: 2,
          ),
        ],
        [
          const LegacyWordFontDefinition(
            sourceIndex: 0,
            name: 'Bad\nFace',
            charset: 2,
          ),
        ],
        [
          const LegacyWordFontDefinition(
            sourceIndex: 0,
            name: 'Face',
            charset: -1,
          ),
        ],
        [
          const LegacyWordFontDefinition(
            sourceIndex: 0,
            name: 'Face',
            charset: 256,
          ),
        ],
        [
          const LegacyWordFontDefinition(sourceIndex: 0, name: 'A', charset: 2),
          const LegacyWordFontDefinition(sourceIndex: 0, name: 'B', charset: 2),
        ],
      ]) {
        final document = LegacyWordDocument(
          blocks: const [],
          sections: const [],
          plainText: '',
          safeHtml: '',
          fontTable: fonts,
        );
        expect(
          () => convertLegacyWordDocument(document),
          throwsFormatException,
        );
      }
    },
  );
}
