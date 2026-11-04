import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  SmlWorksheet sheetWith(Map<String, Object> values) {
    final SmlWorksheet sheet = SmlWorksheet(name: 'Sheet1', sheetId: 1);
    for (final MapEntry<String, Object> entry in values.entries) {
      sheet.cellA1(entry.key).value = entry.value;
    }
    return sheet;
  }

  test('Ctrl-arrow jumps to the last cell of the same occupancy', () {
    final SmlWorksheet sheet = sheetWith(<String, Object>{
      'A1': 1,
      'B1': 2,
      'D1': 4,
      'A3': 3,
    });

    expect(sheet.sameOccupancy(SmlCellRef.parse('A1'), 1, 0).a1, 'B1');
    expect(sheet.sameOccupancy(SmlCellRef.parse('B1'), 1, 0).a1, 'D1');
    expect(sheet.sameOccupancy(SmlCellRef.parse('C1'), 1, 0).a1, 'C1');
    expect(sheet.sameOccupancy(SmlCellRef.parse('C1'), -1, 0).a1, 'C1');
    expect(sheet.sameOccupancy(SmlCellRef.parse('D1'), -1, 0).a1, 'A1');
    expect(sheet.sameOccupancy(SmlCellRef.parse('A1'), 0, 1).a1, 'A3');
    expect(sheet.sameOccupancy(SmlCellRef.parse('A2'), 0, 1).a1, 'A2');
    expect(sheet.sameOccupancy(SmlCellRef.parse('A2'), 0, -1).a1, 'A2');
  });

  test('Ctrl-arrow stays on the current row or column', () {
    final SmlWorksheet sheet = sheetWith(<String, Object>{'B2': 1, 'D4': 9});

    expect(sheet.sameOccupancy(SmlCellRef.parse('A1'), -1, 0).a1, 'A1');
    expect(sheet.sameOccupancy(SmlCellRef.parse('A1'), 0, -1).a1, 'A1');
    expect(sheet.sameOccupancy(SmlCellRef.parse('A1'), 1, 0).a1, 'A1');
    expect(sheet.sameOccupancy(SmlCellRef.parse('A1'), 0, 1).a1, 'A1');
    expect(sheet.sameOccupancy(SmlCellRef.parse('E2'), 1, 0).a1, 'E2');
    expect(sheet.sameOccupancy(SmlCellRef.parse('B2'), 0, 1).a1, 'B2');
    expect(sheet.sameOccupancy(SmlCellRef.parse('D4'), -1, 0).a1, 'D4');
  });

  test('Ctrl-arrow lands on the last filled cell of a column block', () {
    final SmlWorksheet sheet = sheetWith(<String, Object>{
      'A1': 'Line',
      'A2': 'Licenses',
      'A3': 'Hosting',
      'A4': 'Design',
      'A5': 'Support',
      'A6': 'Total',
      'B2': 4200,
      'A8': 'Average',
      'A9': 'Max line',
    });

    expect(sheet.sameOccupancy(SmlCellRef.parse('A1'), 0, 1).a1, 'A6');
    expect(sheet.sameOccupancy(SmlCellRef.parse('A6'), 0, 1).a1, 'A9');
    expect(sheet.sameOccupancy(SmlCellRef.parse('A9'), 0, 1).a1, 'A9');
    expect(sheet.sameOccupancy(SmlCellRef.parse('A7'), 0, 1).a1, 'A7');
    expect(sheet.sameOccupancy(SmlCellRef.parse('A7'), 0, -1).a1, 'A7');
    expect(sheet.sameOccupancy(SmlCellRef.parse('B2'), 0, 1).a1, 'B2');
  });

  test('insertRows and insertCols shift existing cells', () {
    final SmlWorksheet sheet = sheetWith(<String, Object>{
      'A1': 1,
      'B1': 2,
      'A2': 3,
    });
    sheet.insertRows(1);
    expect(sheet.cellA1('A1').value, 1);
    expect(sheet.cellA1('A2').hasContent, isFalse);
    expect(sheet.cellA1('A3').value, 3);
    sheet.insertCols(1);
    expect(sheet.cellA1('A1').value, 1);
    expect(sheet.cellA1('B1').hasContent, isFalse);
    expect(sheet.cellA1('C1').value, 2);
  });

  test('deleteRows and deleteCols close the gap', () {
    final SmlWorksheet sheet = sheetWith(<String, Object>{
      'A1': 1,
      'A2': 2,
      'A3': 3,
      'B1': 4,
      'C1': 5,
    });
    sheet.deleteRows(1);
    expect(sheet.cellA1('A1').value, 1);
    expect(sheet.cellA1('A2').value, 3);
    sheet.deleteCols(1);
    expect(sheet.cellA1('A1').value, 1);
    expect(sheet.cellA1('B1').value, 5);
  });
}
