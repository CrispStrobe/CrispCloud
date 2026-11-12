// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';
import 'support/table_width_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void main() {
  for (final item in tableWidthCases) {
    test(
      '${item.name} retains preferred width apart from grid and raw no-wrap',
      () {
        final source = tableWidthFixture(item);
        final document = parseLegacyWordDocument(source);
        final table = document.blocks.whereType<LegacyWordTable>().single;
        expect(
          table.rows.single.cells.map((c) => c.widthTwips),
          item.gridWidths ?? [2400, 2400],
        );
        for (final (index, cell) in table.rows.single.cells.indexed) {
          expect(cell.formatting.preferredWidth!.unit.index, item.unit);
          expect(
            cell.formatting.preferredWidth!.value,
            index == 1 ? item.secondValue ?? item.value : item.value,
          );
          expect(cell.formatting.noWrapPreference, !item.resetNoWrap);
          expect(cell.formatting.noWrap, item.unit != 3 && !item.resetNoWrap);
        }
        final archive = ZipDecoder().decodeBytes(
          convertLegacyWordToStructuredDocx(source).bytes,
        );
        final xml = XmlDocument.parse(
          utf8.decode(archive.findFile('word/document.xml')!.content),
        );
        expect(
          xml
              .findAllElements('gridCol', namespace: _w)
              .map((e) => e.getAttribute('w', namespace: _w)),
          (item.gridWidths ?? [2400, 2400]).map((v) => '$v'),
        );
        expect(
          xml
              .findAllElements('tcW', namespace: _w)
              .map((e) => e.getAttribute('type', namespace: _w)),
          List.filled(2, ['nil', 'auto', 'pct', 'dxa'][item.unit]),
        );
        expect(
          xml
              .findAllElements('tcW', namespace: _w)
              .map((e) => e.getAttribute('w', namespace: _w)),
          ['${item.value}', '${item.secondValue ?? item.value}'],
        );
        expect(
          xml
              .findAllElements('noWrap', namespace: _w)
              .map((e) => e.getAttribute('val', namespace: _w)),
          List.filled(2, item.unit != 3 && !item.resetNoWrap ? 'on' : 'off'),
        );
      },
    );
  }

  test(
    'one conditional no-wrap rule resolves separately for auto and dxa cells',
    () {
      final source = tableWidthFixture(
        tableWidthCases.singleWhere((item) => item.name == 'style-auto'),
        conditional: true,
        extra: tablePreferredWidth(1, 2, 3, 1800),
      );
      final table = parseLegacyWordDocument(
        source,
      ).blocks.whereType<LegacyWordTable>().single;
      final cells = table.rows.single.cells;
      expect(cells.map((c) => c.formatting.noWrapPreference), [true, true]);
      expect(cells.map((c) => c.formatting.noWrap), [true, false]);
      expect(cells.map((c) => c.widthTwips), [2400, 2400]);
      final archive = ZipDecoder().decodeBytes(
        convertLegacyWordToStructuredDocx(source).bytes,
      );
      final main = XmlDocument.parse(
        utf8.decode(archive.findFile('word/document.xml')!.content),
      );
      final styles = XmlDocument.parse(
        utf8.decode(archive.findFile('word/styles.xml')!.content),
      );
      expect(
        main
            .findAllElements('noWrap', namespace: _w)
            .map((e) => e.getAttribute('val', namespace: _w)),
        ['on', 'off'],
      );
      final rule = styles.findAllElements('tblStylePr', namespace: _w).single;
      expect(rule.getAttribute('type', namespace: _w), 'firstRow');
      expect(
        rule
            .findAllElements('noWrap', namespace: _w)
            .single
            .getAttribute('val', namespace: _w),
        'on',
      );
      final evidence =
          jsonDecode(
                utf8.decode(
                  archive.findFile('word/evidence/manifest.json')!.content,
                ),
              )
              as Map<String, dynamic>;
      final record = (evidence['records'] as List).cast<Map>().singleWhere(
        (row) => row['kind'] == 'cellNoWrapWidthContext',
      );
      expect(record['tableStartCp'], table.startCp);
      expect(record['cellStartCp'], cells.last.blocks.first.startCp);
      expect(record['sourceNoWrap'], true);
      expect(record['effectiveNoWrap'], false);
      expect(record['preferredWidthUnit'], 'twips');
      expect(record['preferredWidth'], 1800);
    },
  );

  test(
    'TIstd and cell mutations preserve preferred widths with cell identity',
    () {
      final source = tableWidthFixture(
        tableWidthCases.first,
        extra: [
          ...tablePreferredWidth(0, 1, 2, 1750),
          ...tablePreferredWidth(1, 2, 3, 1800),
          ...wordSprm(0x7621, [0, 1, ...wordU16(720)]),
          ...wordSprm(0x5622, [1, 2]),
          ...wordSprm(0x563a, wordU16(11)),
        ],
      );
      final cells = (parseLegacyWordDocument(
        source,
      ).blocks.whereType<LegacyWordTable>().single).rows.single.cells;
      expect(cells.first.formatting.preferredWidth, isNull);
      expect(
        cells.last.formatting.preferredWidth!.unit,
        LegacyWordTableWidthUnit.twips,
      );
      expect(cells.last.formatting.preferredWidth!.value, 1800);
      expect(cells.last.formatting.noWrapPreference, isTrue);
      expect(cells.last.formatting.noWrap, isFalse);
    },
  );

  test(
    'independent Word source keeps preferred widths from modern Data rows',
    () {
      final source = File(
        'test/fixtures/word_native/poi-simple-table2.doc',
      ).readAsBytesSync();
      final table = parseLegacyWordDocument(
        source,
      ).blocks.whereType<LegacyWordTable>().single;
      for (final row in table.rows) {
        expect(row.cells.map((c) => c.widthTwips), [3192, 3192, 3192]);
        expect(
          row.cells.map((c) => c.formatting.preferredWidth!.unit),
          List.filled(3, LegacyWordTableWidthUnit.twips),
        );
        expect(row.cells.map((c) => c.formatting.preferredWidth!.value), [
          3192,
          3192,
          3192,
        ]);
      }
    },
  );

  test('nil ignores its undefined operand without turning into auto', () {
    final source = tableWidthFixture(
      tableWidthCases.first,
      extra: tablePreferredWidth(0, 2, 0, -1),
    );
    final width =
        (parseLegacyWordDocument(
              source,
            ).blocks.whereType<LegacyWordTable>().single)
            .rows
            .single
            .cells
            .first
            .formatting
            .preferredWidth!;
    expect(width.unit, LegacyWordTableWidthUnit.nil);
    expect(width.value, 0);
  });

  for (final entry in <String, List<int>>{
    'bad range': tablePreferredWidth(0, 3, 3, 1440),
    'empty range': tablePreferredWidth(1, 1, 3, 1440),
    'spacing-only unit': tablePreferredWidth(0, 2, 0x13, 100),
    'undefined unit': tablePreferredWidth(0, 2, 4, 100),
    'negative percentage': tablePreferredWidth(0, 2, 2, -1),
    'excessive percentage': tablePreferredWidth(0, 2, 2, 5001),
    'negative twips': tablePreferredWidth(0, 2, 3, -1),
    'excessive twips': tablePreferredWidth(0, 2, 3, 31681),
    'nonzero auto': tablePreferredWidth(0, 2, 1, 1),
    'invalid no-wrap': wordSprm(0xd639, [3, 0, 2, 2]),
  }.entries) {
    test(
      'rejects ${entry.key}',
      () => expect(
        () => parseLegacyWordDocument(
          tableWidthFixture(tableWidthCases.first, extra: entry.value),
        ),
        throwsFormatException,
      ),
    );
  }
}
