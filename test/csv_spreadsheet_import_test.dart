import 'dart:convert';

import 'package:crisp_cloud/services/csv_spreadsheet_import.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'support/workflow_fake_client.dart';

void main() {
  test('dialect detection ignores quoted separators and multiline headings', () {
    const csv =
        '"first,\nheading";note;last\r\n001;"a; b";\r\n\r\nend;"say ""hi""";x';
    expect(detectSpreadsheetDelimiter(csv), ';');
    expect(parseSpreadsheetText(csv), [
      ['first,\nheading', 'note', 'last'],
      ['001', 'a; b', ''],
      [''],
      ['end', 'say "hi"', 'x'],
    ]);
    expect(parseSpreadsheetText('\ufeffa\tb\nα\tβ'), [
      ['a', 'b'],
      ['α', 'β'],
    ]);
  });

  test(
    'text import round trips literal formulas, exact IDs and blank rows',
    () {
      final rows = parseSpreadsheetText(
        '00123,=1+1,9007199254740993\n\n"a\nb",α,',
      );
      final book = SheetDeserializer().readBytes(
        buildSpreadsheetCopy((rows, false)),
      );
      final sheet = book.sheets.single;
      expect(sheet.cell(const SmlCellRef(0, 0)).value, '00123');
      expect(sheet.cell(const SmlCellRef(1, 0)).value, '=1+1');
      expect(sheet.cell(const SmlCellRef(1, 0)).formula, isNull);
      expect(sheet.cell(const SmlCellRef(2, 0)).value, '9007199254740993');
      expect(sheet.cell(const SmlCellRef(0, 2)).value, 'a\nb');
      expect(sheet.cell(const SmlCellRef(1, 2)).value, 'α');
    },
  );

  test(
    'optional numeric recognition protects IDs and never creates formulas',
    () {
      final values = [
        '0',
        '-12.5',
        '1e3',
        '001',
        '9007199254740993',
        '=3+4',
        'NaN',
        '1e999',
      ];
      final sheet = SheetDeserializer()
          .readBytes(buildSpreadsheetCopy(([values], true)))
          .sheets
          .single;
      for (var c = 0; c < 3; c++) {
        expect(sheet.cell(SmlCellRef(c, 0)).type, SmlCellType.number);
      }
      for (var c = 3; c < values.length; c++) {
        expect(sheet.cell(SmlCellRef(c, 0)).value, values[c]);
        expect(sheet.cell(SmlCellRef(c, 0)).formula, isNull);
      }
    },
  );

  test('malformed and oversized tables are rejected without truncation', () {
    expect(
      () => parseSpreadsheetText('a,"unterminated'),
      throwsA(isA<ReportDataException>()),
    );
    expect(
      () => parseSpreadsheetText(List.filled(16385, 'x').join(',')),
      throwsFormatException,
    );
    expect(
      () => parseSpreadsheetText('x' * (csvSpreadsheetInputLimit + 1)),
      throwsFormatException,
    );
  });

  group('verified copy publication', () {
    late WorkflowFakeClient cloud;
    late CloudOperationBackend backend;
    final original = utf8.encode('id,amount\n001,2');
    final bytes = buildSpreadsheetCopy((
      parseSpreadsheetText(utf8.decode(original)),
      false,
    ));
    setUp(() {
      cloud = WorkflowFakeClient()..put('/tables/input.csv', original);
      backend = CloudOperationBackend(cloud, isCurrent: () => cloud.current);
    });
    Future<dynamic> create(String name) => createSpreadsheetCopy(
      backend: backend,
      sourcePath: '/tables/input.csv',
      name: name,
      bytes: bytes,
    );
    test('creates sibling XLSX and preserves source', () async {
      final output = await create('input-imported.xlsx');
      expect(output.path, '/tables/input-imported.xlsx');
      expect(cloud.files[output.path], bytes);
      expect(cloud.files['/tables/input.csv'], original);
    });
    test('existing output is never overwritten', () async {
      cloud.put('/tables/existing.xlsx', [1, 2, 3]);
      await expectLater(create('existing.xlsx'), throwsStateError);
      expect(cloud.files['/tables/existing.xlsx'], [1, 2, 3]);
      expect(cloud.writes, isEmpty);
    });
    test('path escapes and reserved names fail before writing', () async {
      for (final name in [
        '../x.xlsx',
        '/x.xlsx',
        'CON.xlsx',
        'bad.csv',
        'a\\b.xlsx',
      ]) {
        await expectLater(create(name), throwsFormatException);
      }
      expect(cloud.writes, isEmpty);
    });
    test('disconnected captured storage blocks publication', () async {
      cloud.current = false;
      await expectLater(create('new.xlsx'), throwsStateError);
      expect(cloud.writes, isEmpty);
    });
  });
}
