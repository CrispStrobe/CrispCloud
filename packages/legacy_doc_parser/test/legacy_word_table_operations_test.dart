// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/decorated_word_fixture.dart';
import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
List<int> _style(int id) => wordSprm(0x563a, wordU16(id));
List<int> _insert(int count, [int width = 1440]) =>
    wordSprm(0x7621, [0, count, ...wordU16(width)]);
List<int> _shade(int color) =>
    wordSprm(0xd687, [10, ...wordShading(background: color)]);
List<int> _margin(int first, int limit, int width) =>
    wordSprm(0xd632, [6, first, limit, 2, 3, ...wordU16(width)]);
Uint8List _source(
  List<int> properties, {
  int cells = 2,
  List<int> widths = const [],
  Map<int, WordFixtureStyle> styles = const {},
}) => tableFixture(
  [
    for (var i = 0; i < cells; i++)
      TableFixtureParagraph('Cell$i\x07', depth: 1),
    TableFixtureParagraph(
      '\x07',
      depth: 1,
      row: true,
      widths: widths,
      extra: properties,
    ),
  ],
  styles: {
    0: const WordFixtureStyle(name: 'Normal'),
    ...styles,
  },
);
LegacyWordTable _table(Uint8List bytes) =>
    parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable;
XmlDocument _xml(Uint8List bytes) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder()
        .decodeBytes(convertLegacyWordToStructuredDocx(bytes).bytes)
        .findFile('word/document.xml')!
        .content,
  ),
);

void main() {
  test(
    'TIstd replaces row defaults while preserving cell state and exemptions',
    () {
      final source = _source(
        [
          ...tableFixtureDefinition([720, 720]),
          ...wordSprm(0xd634, [6, 0, 1, 2, 3, ...wordU16(480)]),
          ..._margin(0, 2, 720),
          ...wordSprm(0xd670, [
            20,
            ...wordShading(background: 0xff),
            ...wordShading(background: 0xff),
          ]),
          ...wordSprm(0x3466, [1]),
          ...wordSprm(0x3403, [1]),
          ...wordSprm(0x3404, [1]),
          ...wordSprm(0x9601, wordU16(500)),
          ...wordSprm(0x9602, wordU16(100)),
          ...wordSprm(0x9407, wordU16(-480)),
          ...wordSprm(0x560b, wordU16(1)),
          ...wordSprm(0x3615, [1]),
          ...wordSprm(0x740a, [...wordU16(0), ...wordU16(0x1e0)]),
          ..._style(15),
        ],
        styles: {
          15: WordFixtureStyle(
            name: 'Replacement',
            table: true,
            tableProperties: [
              ..._shade(0x00332211),
              ...wordSprm(0xd63e, [6, 0, 1, 2, 3, ...wordU16(240)]),
            ],
          ),
        },
      );
      final row = _table(source).rows.single;
      expect(row.cells.map((v) => v.widthTwips), [720, 720]);
      expect(
        row.cells.map((v) => v.formatting.margins[LegacyWordBorderSide.left]),
        [720, 720],
      );
      expect(row.cells.map((v) => v.shading?.backgroundHex), [
        'FF0000',
        'FF0000',
      ]);
      expect(row.cantSplit, isNull);
      expect(row.isHeader, isFalse);
      expect(row.originTwips, 400);
      expect(row.heightTwips, -480);
      expect(row.halfGapTwips, 100);
      expect(row.styleOptions, 0x1e0);
      expect(_table(source).rightToLeft, isTrue);
      expect(_table(source).autoFit, isTrue);
    },
  );

  test(
    'TDelete and TDxaCol keep borders, layout, shading and margins attached to cells',
    () {
      final bytes = _source(
        [
          ..._margin(1, 2, 360),
          ...wordSprm(0xd62c, [3, 1, 2, 2]),
          ...wordSprm(0xd62f, [11, 1, 2, 1, ...wordU32(0xff), 8, 1, 0, 0]),
          ...wordSprm(0xd670, [
            20,
            ...wordShading(background: 0),
            ...wordShading(background: 0x00332211),
          ]),
          ...wordSprm(0x7621, [0, 1, ...wordU16(720)]),
          ...wordSprm(0x5622, [1, 2]),
          ...wordSprm(0x7623, [0, 1, ...wordU16(1080)]),
        ],
        widths: [1440, 1440],
      );
      final cells = _table(bytes).rows.single.cells;
      expect(cells.map((v) => v.widthTwips), [1080, 1440]);
      expect(cells[1].formatting.margins[LegacyWordBorderSide.left], 360);
      expect(
        cells[1].formatting.verticalAlignment,
        LegacyWordCellAlignment.bottom,
      );
      expect(
        cells[1].formatting.borders[LegacyWordTableBorderSide.top]!.colorHex,
        'FF0000',
      );
      expect(cells[1].shading?.backgroundHex, '112233');
      expect(
        cells[0].formatting.borders[LegacyWordTableBorderSide.top],
        isNull,
      );
    },
  );

  test('TMerge and TSplit retain distinct editable cell merge state', () {
    final merge = _source([
      ..._insert(2),
      ...wordSprm(0x5624, [0, 2]),
    ]);
    final cells = _table(merge).rows.single.cells;
    expect(cells.first.mergeStart, isTrue);
    expect(cells.last.mergeContinue, isTrue);
    expect(
      _xml(merge)
          .findAllElements('hMerge', namespace: _w)
          .map((v) => v.getAttribute('val', namespace: _w)),
      ['restart', 'continue'],
    );
    final split = _source([
      ..._insert(2),
      ...wordSprm(0x5624, [0, 2]),
      ...wordSprm(0x5625, [0, 2]),
    ]);
    expect(
      _table(
        split,
      ).rows.single.cells.any((v) => v.mergeStart || v.mergeContinue),
      isFalse,
    );
    expect(_xml(split).findAllElements('hMerge', namespace: _w), isEmpty);
  });

  test(
    'adjacent style identities split tables before resolving conditional text',
    () {
      final source = tableFixture(
        [
          const TableFixtureParagraph('A\x07', depth: 1),
          TableFixtureParagraph(
            '\x07',
            depth: 1,
            row: true,
            extra: [..._style(15), ..._insert(1)],
          ),
          const TableFixtureParagraph('B\x07', depth: 1),
          TableFixtureParagraph(
            '\x07',
            depth: 1,
            row: true,
            extra: [..._style(16), ..._insert(1)],
          ),
        ],
        styles: {
          0: const WordFixtureStyle(name: 'Normal'),
          15: WordFixtureStyle(
            name: 'Bold',
            table: true,
            characterProperties: wordSprm(0x0835, [1]),
          ),
          16: WordFixtureStyle(
            name: 'Italic',
            table: true,
            characterProperties: wordSprm(0x0836, [1]),
          ),
        },
      );
      final tables = parseLegacyWordDocument(
        source,
      ).blocks.cast<LegacyWordTable>();
      expect(tables.length, 2);
      expect(tables[0].startCp, 0);
      expect(tables[0].endCp, 3);
      expect(tables[1].startCp, 3);
      expect(tables[1].endCp, 6);
      expect(
        tables[0]
            .rows
            .single
            .cells
            .single
            .paragraphs
            .single
            .runs
            .single
            .style
            .bold,
        isTrue,
      );
      expect(
        tables[1]
            .rows
            .single
            .cells
            .single
            .paragraphs
            .single
            .runs
            .single
            .style
            .italic,
        isTrue,
      );
      expect(_xml(source).findAllElements('tbl', namespace: _w).length, 2);
    },
  );

  test(
    'source direction changes and floating identities separate adjacent rows',
    () {
      for (final property in [
        wordSprm(0x560b, wordU16(1)),
        wordSprm(0x7469, wordU32(9)),
        wordSprm(0x940e, wordU16(120)),
      ]) {
        final source = tableFixture([
          const TableFixtureParagraph('A\x07', depth: 1),
          const TableFixtureParagraph(
            '\x07',
            depth: 1,
            row: true,
            widths: [1440],
          ),
          const TableFixtureParagraph('B\x07', depth: 1),
          TableFixtureParagraph(
            '\x07',
            depth: 1,
            row: true,
            widths: const [1440],
            extra: property,
          ),
        ]);
        final tables = parseLegacyWordDocument(
          source,
        ).blocks.whereType<LegacyWordTable>();
        expect(tables, hasLength(2));
        expect(tables.last.rows, hasLength(1));
      }
    },
  );

  test('physical and logical alignment remain distinct for RTL tables', () {
    for (final rtl in [false, true]) {
      for (var alignment = 0; alignment < 3; alignment++) {
        for (final code in [0x5400, 0x548a]) {
          final source = _source([
            ..._insert(2),
            ...wordSprm(0x560b, wordU16(rtl ? 1 : 0)),
            ...wordSprm(code, wordU16(alignment)),
          ]);
          final logical = code == 0x5400 && rtl ? 2 - alignment : alignment;
          expect(_table(source).alignment, LegacyWordAlignment.values[logical]);
          expect(
            _xml(source)
                .findAllElements('jc', namespace: _w)
                .first
                .getAttribute('val', namespace: _w),
            LegacyWordAlignment.values[logical].name,
          );
        }
      }
    }
  });

  test(
    'fixed column layout is the default; auto-fit remains an explicit choice',
    () {
      for (final auto in [false, true]) {
        final source = _source([
          ..._insert(2),
          ...wordSprm(0x3615, [auto ? 1 : 0]),
        ]);
        expect(_table(source).autoFit, auto);
        expect(
          _xml(source)
              .findAllElements('tblLayout', namespace: _w)
              .single
              .getAttribute('type', namespace: _w),
          auto ? 'autofit' : 'fixed',
        );
        expect(
          _xml(source)
              .findAllElements('tblW', namespace: _w)
              .single
              .getAttribute('w', namespace: _w),
          '2880',
        );
      }
    },
  );

  test('native Word table styles retain the optional istd prefix in PAPX', () {
    final bytes = File(
      'test/fixtures/word_native/poi-simple-table2.doc',
    ).readAsBytesSync();
    final original = Uint8List.fromList(bytes);
    final doc = parseLegacyWordDocument(bytes);
    expect(doc.tableStyles.map((v) => v.id), [11, 15]);
    expect(doc.tableStyles.map((v) => v.name), ['Table Normal', 'Table Grid']);
    expect(doc.blocks.whereType<LegacyWordTable>().single.rows, hasLength(3));
    for (final row in doc.blocks.whereType<LegacyWordTable>().single.rows) {
      // Its real modern Data row has TInsert -> TDxaCol -> TIstd. Geometry
      // must survive style application; the obsolete inline tail is ignored.
      expect(row.cells.map((cell) => cell.widthTwips), [3192, 3192, 3192]);
    }
    final cfb = BoundedCfbReader(bytes),
        fib = ByteData.sublistView(cfb.readPath('WordDocument')!);
    final raw = cfb.readPath('1Table')!, input = ByteData.sublistView(raw);
    int u16(int at) => input.getUint16(at, Endian.little);
    final start = fib.getUint32(154 + 8, Endian.little), base = u16(start + 4);
    var pos = start + 2 + u16(start);
    final prefixes = <int, List<int>>{};
    for (var id = 0; id < u16(start + 2); id++) {
      final size = u16(pos);
      pos += 2;
      if (size == 0) continue;
      final record = pos;
      pos += size;
      if ((u16(record + 2) & 15) != 3) continue;
      var upx = record + base + 4 + u16(record + base) * 2;
      final tapxLength = u16(upx);
      upx += 2 + tapxLength;
      if ((upx - record).isOdd) upx++;
      final papxLength = u16(upx);
      upx += 2;
      prefixes[id] = raw.sublist(upx, upx + papxLength);
    }
    expect(prefixes, {
      11: [11, 0],
      15: [15, 0],
    });
    expect(bytes, original);
  });

  test(
    'row alignment and automatic sizing retain explicit reset exceptions',
    () {
      final bytes = tableFixture([
        const TableFixtureParagraph('A\x07', depth: 1),
        TableFixtureParagraph(
          '\x07',
          depth: 1,
          row: true,
          widths: [1440],
          extra: [
            ...wordSprm(0x548a, wordU16(1)),
            ...wordSprm(0x3615, [1]),
          ],
        ),
        const TableFixtureParagraph('B\x07', depth: 1),
        const TableFixtureParagraph(
          '\x07',
          depth: 1,
          row: true,
          widths: [1440],
        ),
      ]);
      final table = _table(bytes);
      expect(table.alignment, LegacyWordAlignment.center);
      expect(table.autoFit, isTrue);
      expect(table.rows[1].alignment, LegacyWordAlignment.left);
      expect(table.rows[1].autoFit, isFalse);
      final xml = _xml(bytes);
      final exception = xml.findAllElements('tblPrEx', namespace: _w).single;
      expect(
        exception
            .getElement('jc', namespace: _w)!
            .getAttribute('val', namespace: _w),
        'left',
      );
      expect(
        exception
            .getElement('tblLayout', namespace: _w)!
            .getAttribute('type', namespace: _w),
        'fixed',
      );
    },
  );

  for (final entry in <String, List<int>>{
    'deletion of every cell': wordSprm(0x5622, [0, 2]),
    'width past defined cells': wordSprm(0x7623, [0, 3, ...wordU16(12)]),
    'negative column width': wordSprm(0x7623, [0, 1, ...wordU16(-1)]),
    'oversized column width': wordSprm(0x7623, [0, 2, ...wordU16(20000)]),
    'empty merge range': wordSprm(0x5624, [1, 1]),
    'alignment past defined cells': wordSprm(0xd62c, [3, 0, 3, 1]),
    'margin past defined cells': _margin(0, 3, 120),
    'invalid table direction': wordSprm(0x560b, wordU16(2)),
    'invalid table alignment': wordSprm(0x548a, wordU16(3)),
  }.entries) {
    test(
      'rejects ${entry.key}',
      () => expect(
        () => _table(_source([..._insert(2), ...entry.value])),
        throwsFormatException,
      ),
    );
  }
}
