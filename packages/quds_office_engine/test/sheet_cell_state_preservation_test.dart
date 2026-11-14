import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  for (final ascending in [true, false]) {
    test(
      'sorting ${ascending ? 'up' : 'down'} carries locks and PDF borders',
      () {
        final sheet = SmlWorkbook().firstSheet;
        sheet.cellA1('A1').value = 'Header';
        sheet.cellA1('A2')
          ..value = 2
          ..borderRgb = 'FF0000'
          ..borderWidth = 2
          ..locked = false;
        sheet.cellA1('A3')
          ..value = 1
          ..borderRgb = '0000FF'
          ..borderWidth = 0.75
          ..locked = true;
        sheet.cellA1('A4')
          ..value = 3
          ..locked = false;

        SmlAnalysis.sort(sheet, SmlRange.parse('A1:A4'), [
          SmlSortKey(column: 0, ascending: ascending),
        ]);

        final values = ascending ? [1, 2, 3] : [3, 2, 1];
        for (var i = 0; i < values.length; i++) {
          final cell = sheet.cellA1('A${i + 2}');
          expect(cell.value, values[i]);
          expect(cell.locked, values[i] == 1);
          expect(cell.borderRgb, switch (values[i]) {
            1 => '0000FF',
            2 => 'FF0000',
            _ => '',
          });
          expect(cell.borderWidth, switch (values[i]) {
            1 => 0.75,
            2 => 2,
            _ => 0,
          });
        }
        expect(sheet.cellA1('A1').value, 'Header');
        expect(sheet.cellA1('A1').locked, isTrue);
        expect(sheet.cellA1('A1').borderRgb, isEmpty);
      },
    );
  }
}
