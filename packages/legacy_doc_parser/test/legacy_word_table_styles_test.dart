// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/decorated_word_fixture.dart';
import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

List<int> _cnf(int code, int condition, List<int> operations) => wordSprm(
  code,
  [operations.length + 2, ...wordU16(condition), ...operations],
);
List<int> _color(int value) => wordSprm(0x6870, wordU32(value));
List<int> _styleRow(int columns, {int id = 15, int look = 0x1e0}) => [
  ...wordSprm(0x563a, wordU16(id)),
  ...wordSprm(0x740a, [...wordU16(0), ...wordU16(look)]),
  ...wordSprm(0x7621, [0, columns, ...wordU16(1440)]),
];
List<int> _shade(int background) =>
    wordSprm(0xd687, [10, ...wordShading(background: background)]);
Uint8List _matrix(
  int rows,
  int columns,
  WordFixtureStyle style, {
  int look = 0x1e0,
  int headers = 0,
  List<int> rowExtra = const [],
  Map<int, WordFixtureStyle> moreStyles = const {},
  List<int> normalCharacter = const [],
}) => tableFixture(
  [
    for (var row = 0; row < rows; row++) ...[
      for (var cell = 0; cell < columns; cell++)
        TableFixtureParagraph('$row$cell\x07', depth: 1),
      TableFixtureParagraph(
        '\x07',
        depth: 1,
        row: true,
        extra: [
          ..._styleRow(columns, look: look),
          if (row < headers) ...wordSprm(0x3404, [1]),
          ...rowExtra,
        ],
      ),
    ],
  ],
  styles: {
    0: WordFixtureStyle(
      name: 'Normal',
      builtinId: 0,
      characterProperties: normalCharacter,
    ),
    15: style,
    ...moreStyles,
  },
);

XmlDocument _documentXml(Uint8List source) {
  final result = convertLegacyWordToStructuredDocx(source);
  final archive = ZipDecoder().decodeBytes(result.bytes);
  return XmlDocument.parse(
    utf8.decode(archive.findFile('word/document.xml')!.content),
  );
}

void main() {
  test(
    'resolves inherited CNFC layers in specified band/edge/corner order',
    () {
      final bytes = _matrix(
        4,
        3,
        WordFixtureStyle(
          name: 'Conditional test',
          table: true,
          tableProperties: [
            ...wordSprm(0x3488, [1]),
            ...wordSprm(0x3489, [1]),
            ..._shade(0x00eeeeee),
            ..._cnf(0xd66a, 1, _shade(0x00ccddff)),
            ...wordSprm(0x347c, [1]),
          ],
          paragraphProperties: _cnf(0xc666, 1, wordSprm(0x2403, [1])),
          characterProperties: [
            ...wordSprm(0x0835, [1]),
            for (final entry in <int, int>{
              0x40: 0x0000ffff,
              0x80: 0x00ffff00,
              0x10: 0x00888888,
              0x20: 0x00999999,
              4: 0x00aa0000,
              8: 0x00aa00aa,
              1: 0x000000aa,
              2: 0x0000aa00,
              0x100: 0x00222222,
              0x200: 0x00111111,
              0x400: 0x00444444,
              0x800: 0x00333333,
            }.entries)
              ..._cnf(0xca85, entry.key, _color(entry.value)),
          ],
        ),
      );
      final before = Uint8List.fromList(bytes);
      final doc = parseLegacyWordDocument(bytes);
      final table = doc.blocks.single as LegacyWordTable;
      expect(
        table.rows.map(
          (r) => r.cells
              .map((c) => c.paragraphs.single.runs.single.style.colorHex)
              .toList(),
        ),
        [
          ['111111', 'AA0000', '222222'],
          ['0000AA', '888888', 'AA00AA'],
          ['0000AA', '888888', 'AA00AA'],
          ['333333', '00AA00', '444444'],
        ],
      );
      expect(table.rows[1].cells[1].conditionalFlags, 0x40 | 0x10);
      expect(table.rows[2].cells[1].conditionalFlags, 0x80 | 0x10);
      expect(
        table.rows[0].cells[1].paragraphs.single.style.alignment,
        LegacyWordAlignment.center,
      );
      expect(table.rows[0].cells[0].shading?.backgroundHex, 'FFDDCC');
      expect(table.rows[1].cells[0].shading?.backgroundHex, 'EEEEEE');
      expect(
        table.rows.every(
          (r) => r.cells.every(
            (c) =>
                c.verticalAlignment == LegacyWordCellVerticalAlignment.center,
          ),
        ),
        isTrue,
      );
      expect(doc.safeHtml, contains('color:#111111'));
      final xml = _documentXml(bytes);
      expect(
        xml.findAllElements('w:color').map((e) => e.getAttribute('w:val')),
        containsAll(['111111', '444444', '888888']),
      );
      expect(
        xml.findAllElements('w:shd').map((e) => e.getAttribute('w:fill')),
        contains('FFDDCC'),
      );
      expect(bytes, before);
    },
  );

  test('leading header rows are excluded from horizontal band counting', () {
    final bytes = _matrix(
      5,
      2,
      WordFixtureStyle(
        name: 'Bands',
        table: true,
        tableProperties: wordSprm(0x3488, [1]),
        characterProperties: [
          ..._cnf(0xca85, 1, _color(0x000000aa)),
          ..._cnf(0xca85, 0x40, _color(0x0000aa00)),
          ..._cnf(0xca85, 0x80, _color(0x00aa0000)),
        ],
      ),
      look: 0x20,
      headers: 2,
    );
    final table =
        parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable;
    expect(
      table.rows.map(
        (r) => r.cells.first.paragraphs.single.runs.single.style.colorHex,
      ),
      ['AA0000', 'AA0000', '00AA00', '0000AA', '00AA00'],
    );
    expect(table.rows.map((r) => r.isHeader), [
      true,
      true,
      false,
      false,
      false,
    ]);
  });

  test(
    'TIstd resets preceding table overrides but preserves explicit exemptions',
    () {
      final bytes = _matrix(
        1,
        2,
        WordFixtureStyle(
          name: 'Reset target',
          table: true,
          tableProperties: [
            ..._shade(0x00332211),
            ...wordSprm(0xd63e, [6, 0, 1, 2, 3, ...wordU16(240)]),
          ],
        ),
        rowExtra: [
          ...wordSprm(0xd632, [6, 0, 2, 2, 3, ...wordU16(720)]),
          ...wordSprm(0xd670, [
            20,
            ...wordShading(background: 0xff),
            ...wordShading(background: 0xff),
          ]),
          ...wordSprm(0x3466, [1]),
          ...wordSprm(0x9407, wordU16(-480)),
          ...wordSprm(0x560b, wordU16(1)),
          ...wordSprm(0x563a, wordU16(15)),
          ...wordSprm(0x7621, [0, 2, ...wordU16(1440)]),
        ],
      );
      final table =
          parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable;
      expect(table.rows.single.cells.length, 2);
      expect(table.rows.single.cells.map((c) => c.shading?.backgroundHex), [
        '112233',
        '112233',
      ]);
      expect(
        table.rows.single.cells.map(
          (c) => c.marginsTwips[LegacyWordCellBorderSide.left],
        ),
        [240, 240],
      );
      expect(table.rows.single.cantSplit, isFalse);
      expect(table.rows.single.heightTwips, 480);
      expect(table.rows.single.exactHeight, isTrue);
      expect(table.rightToLeft, isTrue);
      expect(table.look.flags, 0x1e0);
    },
  );

  test(
    'single-cell corner precedence and paragraph/direct overrides are explicit',
    () {
      final bytes = _matrix(
        1,
        1,
        WordFixtureStyle(
          name: 'Child',
          table: true,
          parentIndex: 16,
          characterProperties: [
            ..._cnf(0xca85, 0x200, _color(0x000000ff)),
            ..._cnf(0xca85, 0x400, _color(0x0000ff00)),
          ],
        ),
        moreStyles: {
          16: WordFixtureStyle(
            name: 'Parent',
            table: true,
            characterProperties: wordSprm(0x0835, [1]),
          ),
        },
        normalCharacter: wordSprm(0x0835, [0]),
      );
      final table =
          parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable;
      final cell = table.rows.single.cells.single;
      expect(cell.conditionalFlags, 1 | 4 | 0x200);
      expect(cell.paragraphs.single.runs.single.style.bold, isFalse);
      expect(cell.paragraphs.single.runs.single.style.colorHex, 'FF0000');
    },
  );

  test(
    'raw Nil inherits conditional shading and Auto explicitly clears it',
    () {
      final raw = wordSprm(0xd670, [
        20,
        ...wordShading(pattern: 0xffff),
        ...wordShading(foreground: 0xff000000, background: 0xff000000),
      ]);
      final bytes = _matrix(
        1,
        2,
        WordFixtureStyle(
          name: 'Shading',
          table: true,
          tableProperties: _shade(0x00332211),
        ),
        rowExtra: raw,
      );
      final table =
          parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable;
      expect(table.rows.single.cells[0].shading?.backgroundHex, '112233');
      expect(table.rows.single.cells[1].shading?.backgroundHex, isNull);
      expect(table.rows.single.cells[1].shading?.pattern, 'clear');
    },
  );

  test(
    'PTableProps consumes modern table properties and stops legacy tail',
    () {
      final modern = _styleRow(2);
      final bytes = StructuredWordFixture(
        pieces: const [WordFixturePiece('A\x07B\x07\x07')],
        paragraphRuns: [
          WordFixtureFkpRun(8192, 8194, properties: wordSprm(0x2416, [1])),
          WordFixtureFkpRun(8194, 8196, properties: wordSprm(0x2416, [1])),
          WordFixtureFkpRun(
            8196,
            8197,
            properties: [
              ...wordSprm(0x2416, [1]),
              ...wordSprm(0x2417, [1]),
              ...wordSprm(0x646b, wordU32(0)),
              ...tableFixtureDefinition([100, 200, 300]),
              // PTableProps ends processing of this containing array, even
              // when an older-reader tail cannot be decoded as modern Prls.
              0x35, 0x08,
            ],
          ),
        ],
        extraStreams: {
          'Data': Uint8List.fromList([...wordU16(modern.length), ...modern]),
        },
        styles: {
          0: const WordFixtureStyle(name: 'Normal', builtinId: 0),
          15: WordFixtureStyle(
            name: 'Modern',
            table: true,
            characterProperties: wordSprm(0x0835, [1]),
          ),
        },
      ).build();
      final table =
          parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable;
      expect(table.rows.single.cells.map((c) => c.widthTwips), [1440, 1440]);
      expect(
        table.rows.single.cells.first.paragraphs.single.runs.single.style.bold,
        isTrue,
      );
    },
  );

  test('cell mutations retain shifted overrides and ordered table origin', () {
    final bytes = _matrix(
      1,
      2,
      WordFixtureStyle(
        name: 'Cell margins',
        table: true,
        tableProperties: wordSprm(0xd63e, [6, 0, 1, 2, 3, ...wordU16(240)]),
      ),
      rowExtra: [
        ...wordSprm(0xd632, [6, 1, 2, 2, 3, ...wordU16(360)]),
        ...wordSprm(0x7621, [0, 1, ...wordU16(720)]),
        ...wordSprm(0x5622, [1, 2]),
        ...wordSprm(0x7623, [0, 1, ...wordU16(1080)]),
        ...wordSprm(0x5624, [0, 2]),
        ...wordSprm(0x5625, [0, 2]),
        ...wordSprm(0x9601, wordU16(500)),
        ...wordSprm(0x9602, wordU16(100)),
      ],
    );
    final table =
        parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable;
    expect(table.indentTwips, 400);
    expect(table.rows.single.cells.map((c) => c.widthTwips), [1080, 1440]);
    expect(table.rows.single.cells.map((c) => c.mergeStart), [false, false]);
    expect(
      table.rows.single.cells.map(
        (c) => c.marginsTwips[LegacyWordCellBorderSide.left],
      ),
      [240, 360],
    );
    final xml = _documentXml(bytes);
    expect(xml.findAllElements('w:tblInd').single.getAttribute('w:w'), '640');
    expect(xml.findAllElements('w:gridCol').map((e) => e.getAttribute('w:w')), [
      '1080',
      '1440',
    ]);
  });

  test(
    'preserves authored native cell borders, margins, and negative table origin',
    () {
      final bytes = File(
        'test/fixtures/word_native/formatting.doc',
      ).readAsBytesSync();
      final source = Uint8List.fromList(bytes);
      final table = parseLegacyWordDocument(
        bytes,
      ).blocks.whereType<LegacyWordTable>().single;
      expect(table.indentTwips, -108);
      expect(table.rows.first.cells.first.marginsTwips, {
        LegacyWordCellBorderSide.top: 0,
        LegacyWordCellBorderSide.left: 108,
        LegacyWordCellBorderSide.bottom: 0,
        LegacyWordCellBorderSide.right: 108,
      });
      expect(
        table.rows.first.cells.first.borders.values.every(
          (b) => b.style == 'single' && b.widthEighthPoints == 4,
        ),
        isTrue,
      );
      final xml = _documentXml(bytes);
      expect(xml.findAllElements('w:tblInd').single.getAttribute('w:w'), '0');
      expect(xml.findAllElements('w:tblW').single.getAttribute('w:w'), '8640');
      expect(
        xml.findAllElements('w:tblLayout').single.getAttribute('w:type'),
        'fixed',
      );
      expect(
        xml
            .findAllElements('w:tcMar')
            .first
            .getElement('w:left')!
            .getAttribute('w:w'),
        '108',
      );
      expect(
        xml
            .findAllElements('w:tcBorders')
            .first
            .getElement('w:top')!
            .getAttribute('w:sz'),
        '4',
      );
      expect(bytes, source);
    },
  );

  test(
    'separates adjacent rows with different table identity and keeps row controls',
    () {
      final bytes = tableFixture(
        [
          const TableFixtureParagraph('A\x07', depth: 1),
          TableFixtureParagraph(
            '\x07',
            depth: 1,
            row: true,
            extra: [
              ..._styleRow(1),
              ...wordSprm(0x3466, [1]),
              ...wordSprm(0x9407, wordU16(-480)),
            ],
          ),
          const TableFixtureParagraph('B\x07', depth: 1),
          TableFixtureParagraph(
            '\x07',
            depth: 1,
            row: true,
            extra: [..._styleRow(1, id: 16), ...wordSprm(0x560b, wordU16(1))],
          ),
        ],
        styles: {
          0: const WordFixtureStyle(name: 'Normal', builtinId: 0),
          15: const WordFixtureStyle(name: 'First', table: true),
          16: const WordFixtureStyle(name: 'Second', table: true),
        },
      );
      final doc = parseLegacyWordDocument(bytes);
      expect(doc.blocks.whereType<LegacyWordTable>().length, 2);
      final first = doc.blocks.first as LegacyWordTable;
      expect(first.rows.single.cantSplit, isTrue);
      expect(first.rows.single.heightTwips, 480);
      expect(first.rows.single.exactHeight, isTrue);
      final xml = _documentXml(bytes);
      expect(
        xml.findAllElements('w:bidiVisual').single.getAttribute('w:val'),
        'on',
      );
      expect(
        xml.findAllElements('w:trHeight').single.getAttribute('w:hRule'),
        'exact',
      );
    },
  );

  test('keeps the source automatic table sizing opt-in', () {
    final bytes = _matrix(
      1,
      1,
      const WordFixtureStyle(name: 'Automatic', table: true),
      rowExtra: wordSprm(0x3615, [1]),
    );
    final table =
        parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable;
    expect(table.autoFit, isTrue);
    expect(
      _documentXml(
        bytes,
      ).findAllElements('w:tblLayout').single.getAttribute('w:type'),
      'autofit',
    );
  });

  for (final entry in <String, List<int>>{
    'combined conditional flags': _cnf(0xd66a, 3, _shade(0)),
    'nested conditional': _cnf(0xd66a, 1, _cnf(0xd66a, 4, _shade(0))),
    'wrong property group': _cnf(0xd66a, 1, wordSprm(0x0835, [1])),
    'structural property in style': tableFixtureDefinition([100]),
    'zero band size': wordSprm(0x3488, [0]),
    'oversized band size': wordSprm(0x3488, [4]),
    'truncated conditional operand': wordSprm(0xd66a, [4, 1, 0, 0x87, 0xd6]),
    'empty conditional border': _cnf(0xd66a, 1, wordSprm(0xd47f, [0])),
  }.entries) {
    test(
      'rejects ${entry.key}',
      () => expect(
        () => parseLegacyWordDocument(
          _matrix(
            1,
            1,
            WordFixtureStyle(
              name: 'Invalid',
              table: true,
              tableProperties: entry.value,
            ),
          ),
        ),
        throwsFormatException,
      ),
    );
  }

  for (final entry in <String, List<int>>{
    'deletion of every cell': wordSprm(0x5622, [0, 2]),
    'cell width past the defined range': wordSprm(0x7623, [
      0,
      3,
      ...wordU16(10),
    ]),
    'cell alignment past the defined range': wordSprm(0xd62c, [3, 0, 3, 1]),
    'cell margin past the defined range': wordSprm(0xd632, [
      6,
      0,
      3,
      2,
      3,
      ...wordU16(10),
    ]),
  }.entries) {
    test(
      'rejects ${entry.key}',
      () => expect(
        () => parseLegacyWordDocument(
          _matrix(
            1,
            2,
            const WordFixtureStyle(name: 'Bounds', table: true),
            rowExtra: entry.value,
          ),
        ),
        throwsFormatException,
      ),
    );
  }
}
