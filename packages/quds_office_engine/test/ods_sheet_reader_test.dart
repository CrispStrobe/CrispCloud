import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// Synthetic LibreOffice-generated ODS (values, formulas, styles, merge).
void main() {
  final bytes = File(
    'test/fixtures/fidelity/legacy-sheet.ods',
  ).readAsBytesSync();

  test('reads ODS values, formulas, styles and merges', () {
    final book = OdsSheetReader.readBytes(bytes);
    expect(book.sheets.map((sheet) => sheet.name), ['Data', 'Notes']);
    final data = book.sheets.first;

    expect(data.cellA1('A1').asString, 'Item');
    expect(data.cellA1('A1').fontBold, isTrue);
    expect(data.cellA1('A1').fontSize, 12);
    expect(data.cellA1('A1').fillRgb, '4472C4');
    expect(data.cellA1('A1').fontRgb, 'FFFFFF');

    expect(data.cellA1('B2').value, 2);
    expect(data.cellA1('C2').value, 3.5);
    final total = data.cellA1('D2');
    expect(total.formula, 'B2*C2');
    expect(total.value, 7);
    expect(total.type, SmlCellType.formula);
    expect(data.cellA1('D6').formula, 'SUM(D2:D4)');

    expect(data.merges.single.origin.a1, 'A8');
    expect(data.merges.single.c1, 1);
    expect(data.exportColumnWidth(0), greaterThan(data.exportColumnWidth(1)));
    expect(data.allCells.length, lessThan(100));
  });

  test('an imported ODS saves as a readable .xlsx', () async {
    final book = OdsSheetReader.readBytes(bytes);
    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final reopened = SheetDeserializer().readBytes(saved);
    expect(reopened.sheets.map((sheet) => sheet.name), ['Data', 'Notes']);
    expect(reopened.sheets.first.cellA1('A1').asString, 'Item');
    expect(reopened.sheets.first.cellA1('D2').formula, 'B2*C2');
    expect(reopened.sheets.first.cellA1('D2').value, 7);
    expect(reopened.sheets.first.cellA1('B2').value, 2);
    expect(reopened.sheets.first.merges, hasLength(1));
  });

  test('rejects a non-ODF package', () {
    expect(
      () => OdsSheetReader.readBytes(Uint8List.fromList(List.filled(64, 0))),
      throwsA(isA<OdsSheetFormatException>()),
    );
  });
}
