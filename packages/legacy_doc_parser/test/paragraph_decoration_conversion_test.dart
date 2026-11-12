// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
Map<String, Uint8List> _parts(LegacyWordStructuredConversion result) => {
  for (final file in ZipDecoder().decodeBytes(result.bytes))
    if (file.isFile) file.name: file.content,
};
XmlDocument _xml(
  Map<String, Uint8List> files, [
  String path = 'word/document.xml',
]) => XmlDocument.parse(utf8.decode(files[path]!));
Iterable<XmlElement> _elements(XmlNode node, String name) =>
    node.findAllElements(name, namespace: _w);
String? _attr(XmlElement element, String name) =>
    element.getAttribute(name, namespace: _w);

LegacyWordDocument _document(
  LegacyWordParagraphStyle style, {
  int? defaultTabs,
}) => LegacyWordDocument(
  blocks: [
    LegacyWordParagraph(
      startCp: 0,
      endCp: 6,
      runs: const [LegacyWordRun(startCp: 0, endCp: 5, text: 'A\tB\tC')],
      style: style,
    ),
  ],
  sections: const [],
  plainText: 'A\tB\tC',
  safeHtml: '',
  defaultTabStopTwips: defaultTabs,
);

void main() {
  test('binary underline variants retain exact WordprocessingML values', () {
    for (final (kind, expected) in [
      (0, 'none'),
      (2, 'words'),
      (3, 'double'),
      (4, 'dotted'),
      (7, 'dash'),
      (11, 'wave'),
      (20, 'dottedHeavy'),
      (43, 'wavyDouble'),
    ]) {
      final source = StructuredWordFixture(
        pieces: const [WordFixturePiece('Text\r')],
        characterRuns: [
          WordFixtureFkpRun(8192, 8197, properties: wordSprm(0x2a3e, [kind])),
        ],
      ).build();
      final xml = _xml(_parts(convertLegacyWordToStructuredDocx(source)));
      final run = _elements(xml, 'r').singleWhere((r) => r.innerText == 'Text');
      expect(_attr(_elements(run, 'u').single, 'val'), expected);
      final paragraphProperties = _elements(xml, 'pPr').first;
      expect(
        _attr(_elements(paragraphProperties, 'u').single, 'val'),
        expected,
      );
    }
  });

  test(
    'binary DOC tab, border, shading and default interval survive the full conversion path',
    () {
      const text = 'Label\tValue\r';
      final dop = Uint8List(84);
      ByteData.sublistView(dop).setUint16(10, 40000, Endian.little);
      final source = StructuredWordFixture(
        pieces: const [WordFixturePiece(text)],
        extraTablePairs: {31: dop},
        paragraphRuns: [
          WordFixtureFkpRun(
            8192,
            8192 + text.length,
            properties: [
              // PChgTabsPapx: no deletions, two positions, then TBD descriptors.
              ...wordSprm(0xc60d, [
                8,
                0,
                2,
                ...wordU16(720),
                ...wordU16(1440),
                9,
                3,
              ]),
              // Modern right paragraph Brc: RGB, eighth-points, type, space/flags.
              ...wordSprm(0xc651, [8, 0x11, 0x22, 0x33, 0, 12, 3, 0x62, 0]),
              // Modern Shd: distinct foreground/background plus clear pattern.
              ...wordSprm(0xc64d, [
                10,
                0x10,
                0x20,
                0x30,
                0,
                0xab,
                0xcd,
                0xef,
                0,
                0,
                0,
              ]),
            ],
          ),
        ],
      ).build();
      final files = _parts(convertLegacyWordToStructuredDocx(source)),
          xml = _xml(_parts(convertLegacyWordToStructuredDocx(source)));
      final tabs = _elements(_elements(xml, 'tabs').single, 'tab').toList();
      expect(tabs.map((tab) => _attr(tab, 'pos')), ['720', '1440']);
      expect(tabs.map((tab) => _attr(tab, 'val')), ['center', 'decimal']);
      expect(tabs.map((tab) => _attr(tab, 'leader')), ['dot', 'none']);
      final border = _elements(_elements(xml, 'pBdr').single, 'right').single;
      expect(_attr(border, 'val'), 'double');
      expect(_attr(border, 'sz'), '12');
      expect(_attr(border, 'color'), '112233');
      expect(_attr(border, 'space'), '2');
      expect(_attr(border, 'shadow'), '1');
      expect(_attr(border, 'frame'), '1');
      final shading = _elements(xml, 'shd').single;
      expect(_attr(shading, 'val'), 'clear');
      expect(_attr(shading, 'color'), '102030');
      expect(_attr(shading, 'fill'), 'ABCDEF');
      expect(
        _attr(
          _elements(_xml(files, 'word/settings.xml'), 'defaultTabStop').single,
          'val',
        ),
        '40000',
      );
    },
  );

  test(
    'custom tab alignment and leaders preserve positions and the default interval',
    () {
      final result = convertLegacyWordDocument(
        _document(
          const LegacyWordParagraphStyle(
            tabs: [
              LegacyWordTabStop(
                positionTwips: 1440,
                alignment: LegacyWordTabAlignment.decimal,
                leader: LegacyWordTabLeader.dot,
              ),
              LegacyWordTabStop(
                positionTwips: 720,
                alignment: LegacyWordTabAlignment.center,
                leader: LegacyWordTabLeader.hyphen,
              ),
              LegacyWordTabStop(
                positionTwips: 2160,
                alignment: LegacyWordTabAlignment.list,
                leader: LegacyWordTabLeader.heavy,
              ),
            ],
          ),
          defaultTabs: 600,
        ),
      );
      final files = _parts(result), xml = _xml(_parts(result));
      final stops = _elements(_elements(xml, 'tabs').single, 'tab').toList();
      expect(stops.map((stop) => _attr(stop, 'pos')), ['720', '1440', '2160']);
      expect(stops.map((stop) => _attr(stop, 'val')), [
        'center',
        'decimal',
        'num',
      ]);
      expect(stops.map((stop) => _attr(stop, 'leader')), [
        'hyphen',
        'dot',
        'heavy',
      ]);
      expect(
        _elements(xml, 'r').expand((run) => _elements(run, 'tab')),
        hasLength(2),
      );
      expect(
        _attr(
          _elements(_xml(files, 'word/settings.xml'), 'defaultTabStop').single,
          'val',
        ),
        '600',
      );
    },
  );

  test(
    'paragraph border units, colors and flags remain distinct while inactive bar stays inert',
    () {
      final result = convertLegacyWordDocument(
        _document(
          const LegacyWordParagraphStyle(
            borders: {
              LegacyWordBorderSide.top: LegacyWordBorder(
                style: 'double',
                rawType: 3,
                widthEighthPoints: 12,
                colorHex: '1256AB',
                spacingPoints: 7,
                shadow: true,
                frame: true,
              ),
              LegacyWordBorderSide.between: LegacyWordBorder(
                style: 'dotted',
                rawType: 6,
                widthEighthPoints: 4,
              ),
              LegacyWordBorderSide.right: LegacyWordBorder(
                style: 'single',
                widthEighthPoints: 8,
                shadow: true,
                frame: true,
              ),
              LegacyWordBorderSide.bar: LegacyWordBorder(
                style: 'single',
                rawType: 1,
                widthEighthPoints: 8,
                colorHex: 'FF0000',
              ),
            },
          ),
        ),
      );
      final files = _parts(result),
          borders = _elements(_xml(_parts(result)), 'pBdr').single;
      final top = _elements(borders, 'top').single;
      expect(_attr(top, 'val'), 'double');
      expect(_attr(top, 'sz'), '12');
      expect(_attr(top, 'space'), '7');
      expect(_attr(top, 'color'), '1256AB');
      expect(_attr(top, 'shadow'), '0');
      expect(_attr(top, 'frame'), '0');
      expect(_attr(_elements(borders, 'right').single, 'shadow'), '1');
      expect(_attr(_elements(borders, 'right').single, 'frame'), '1');
      expect(_attr(_elements(borders, 'between').single, 'color'), 'auto');
      expect(_elements(borders, 'bar'), isEmpty);
      expect(
        utf8.decode(files['word/evidence/manifest.json']!),
        contains('inactiveParagraphBarBorder'),
      );
    },
  );

  test(
    'clear and solid paragraph shading retain foreground and background without swapping',
    () {
      for (final pattern in ['clear', 'solid', 'diagStripe']) {
        final result = convertLegacyWordDocument(
          _document(
            LegacyWordParagraphStyle(
              shading: LegacyWordShading(
                pattern: pattern,
                foregroundHex: '102030',
                backgroundHex: 'ABCDEF',
              ),
            ),
          ),
        );
        final shading = _elements(_xml(_parts(result)), 'shd').single;
        expect(_attr(shading, 'val'), pattern);
        expect(_attr(shading, 'color'), '102030');
        expect(_attr(shading, 'fill'), 'ABCDEF');
      }
    },
  );

  test(
    'cell shading is emitted in cell properties independently of paragraph shading',
    () {
      final document = LegacyWordDocument(
        blocks: const [
          LegacyWordTable(
            startCp: 0,
            endCp: 5,
            rows: [
              LegacyWordTableRow(
                cells: [
                  LegacyWordTableCell(
                    widthTwips: 2400,
                    shading: LegacyWordShading(
                      pattern: 'clear',
                      backgroundHex: 'EEDDCC',
                    ),
                    paragraphs: [
                      LegacyWordParagraph(
                        startCp: 0,
                        endCp: 5,
                        style: LegacyWordParagraphStyle(
                          shading: LegacyWordShading(
                            pattern: 'solid',
                            foregroundHex: '112233',
                          ),
                        ),
                        runs: [
                          LegacyWordRun(startCp: 0, endCp: 4, text: 'Cell'),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
        sections: const [],
        plainText: 'Cell',
        safeHtml: '',
      );
      final xml = _xml(_parts(convertLegacyWordDocument(document)));
      final cell = _elements(_elements(xml, 'tcPr').single, 'shd').single;
      final paragraph = _elements(_elements(xml, 'pPr').single, 'shd').single;
      expect(_attr(cell, 'val'), 'clear');
      expect(_attr(cell, 'fill'), 'EEDDCC');
      expect(_attr(cell, 'color'), 'auto');
      expect(_attr(paragraph, 'val'), 'solid');
      expect(_attr(paragraph, 'color'), '112233');
    },
  );

  test(
    'unrepresentable binary shading remains evidence without an invented fill',
    () {
      final result = convertLegacyWordDocument(
        _document(
          const LegacyWordParagraphStyle(
            shading: LegacyWordShading(
              pattern: null,
              rawPattern: 35,
              foregroundHex: 'FF0000',
              backgroundHex: 'FFFFFF',
            ),
          ),
        ),
      );
      final files = _parts(result);
      expect(_elements(_xml(files), 'shd'), isEmpty);
      final manifest =
          jsonDecode(utf8.decode(files['word/evidence/manifest.json']!)) as Map;
      final records = manifest['records'] as List;
      final shading =
          records.singleWhere((record) => record['kind'] == 'shading') as Map;
      expect(shading['rawPattern'], 35);
      expect(shading['foregroundHex'], 'FF0000');
      expect(shading['backgroundHex'], 'FFFFFF');
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.partialFormatting),
      );
    },
  );

  test('untrusted decoration strings cannot become new XML elements', () {
    expect(
      () => convertLegacyWordDocument(
        _document(
          const LegacyWordParagraphStyle(
            borders: {
              LegacyWordBorderSide.top: LegacyWordBorder(
                style: 'single"/><w:t>Injected',
                widthEighthPoints: 8,
              ),
            },
          ),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => convertLegacyWordDocument(
        _document(
          const LegacyWordParagraphStyle(
            shading: LegacyWordShading(pattern: 'clear"/><w:t>Injected'),
          ),
        ),
      ),
      throwsFormatException,
    );
  });
}
