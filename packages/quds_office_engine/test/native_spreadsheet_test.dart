import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'new pivots have a connected cache and distinct charts survive sheet reorder',
    () async {
      var book = SmlWorkbook(
        sheets: [
          for (int i = 0; i < 2; i++)
            SmlWorksheet(
              name: 'Tab${i + 1}',
              sheetId: i + 1,
              drawings: [
                SmlDrawing(
                  visual: OfficeVisual(
                    kind: OfficeVisualKind.chartColumn,
                    points: [
                      ChartPoint(label: 'Value', value: i + 1, color: '224466'),
                    ],
                  ),
                  col: 4,
                  row: 1,
                ),
              ],
            ),
        ],
      );
      final sheet = book.sheets.first;
      for (final entry in {
        'A1': 'Region',
        'B1': 'Value',
        'A2': 'North',
        'B2': 2,
        'A3': 'South',
        'B3': 5,
      }.entries) {
        sheet.cell(SmlCellRef.parse(entry.key)).value = entry.value;
      }
      sheet.pivots.add(
        SmlPivotTable(
          name: 'CreatedPivot',
          source: SmlRange.parse('A1:B3'),
          rowField: 0,
          dataField: 1,
        ),
      );
      for (int cycle = 1; cycle <= 3; cycle++) {
        final bytes = await OfficeIsolateSave.workbook(book);
        Directory('build/fidelity-native').createSync(recursive: true);
        File(
          'build/fidelity-native/created-pivot-$cycle.xlsx',
        ).writeAsBytesSync(bytes);
        book = SheetDeserializer().readBytes(bytes);
        expect(book.sheets.first.pivots.single.name, 'CreatedPivot');
        expect(book.sheets.first.drawings.single.visual.points.single.value, 1);
        expect(book.sheets.last.drawings.single.visual.points.single.value, 2);
      }
      final originalUri = book.sheets.first.sourcePartUri;
      final reverse = book.sheets.reversed.toList();
      book.sheets
        ..clear()
        ..addAll(reverse);
      book = SheetDeserializer().readBytes(
        await OfficeIsolateSave.workbook(book),
      );
      expect(book.sheets.last.sourcePartUri, originalUri);
      expect(book.sheets.first.drawings.single.visual.points.single.value, 2);
      expect(book.sheets.last.pivots.single.name, 'CreatedPivot');
    },
  );
  test(
    'independent workbook keeps style details charts pivots and relationships',
    () async {
      for (final edited in [false, true]) {
        var book = SheetDeserializer().readBytes(
          File('test/fixtures/fidelity/native.xlsx').readAsBytesSync(),
        );
        expect(book.sheets.map((s) => s.name), ['Data', 'Summary']);
        if (edited) {
          book.sheets.first.cell(SmlCellRef.parse('B2')).value = 7;
          book.sheets.first.cell(SmlCellRef.parse('B2')).fontBold = true;
        }
        for (var cycle = 1; cycle <= 3; cycle++) {
          final bytes = await OfficeIsolateSave.workbook(book);
          Directory('build/fidelity-native').createSync(recursive: true);
          File(
            'build/fidelity-native/native-sheet-${edited ? 'edited' : 'imported'}-$cycle.xlsx',
          ).writeAsBytesSync(bytes);
          book = SheetDeserializer().readBytes(bytes);
          final sheet = book.sheets.first;
          final a = sheet.cell(SmlCellRef.parse('A1'));
          expect(a.fontBold, true);
          expect(a.fontSize, 14);
          expect(a.fillRgb, '224466');
          final b = sheet.cell(SmlCellRef.parse('B2'));
          expect(
            book.styles!.format(b.value, b.styleIndex),
            edited ? '7.00' : '2.00',
          );
          expect(b.fontBold, edited);
          expect(sheet.drawings.single.visual.points.map((p) => p.value), [
            edited ? 7 : 2,
            5,
          ]);
          expect(book.sheets.last.pivots.single.name, 'NativePivot');
          expect(book.sheets.last.pivots.single.source.start.a1, 'A1');
          expect(book.sheets.last.pivots.single.source.end.a1, 'B3');
          expect(book.sheets.first.pivots, isEmpty);
        }
      }
    },
  );
}
