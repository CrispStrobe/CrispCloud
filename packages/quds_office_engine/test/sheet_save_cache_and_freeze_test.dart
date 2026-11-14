import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('a no-edit save keeps native formula caches', () async {
    final book = SmlWorkbook(
      sheets: [
        SmlWorksheet(name: 'Sheet1', sheetId: 1),
      ],
    );
    final sheet = book.firstSheet;
    sheet.cellA1('A1').value = '8.880,00 EUR';
    final cached = sheet.cellA1('B1')
      ..formula =
          '=NUMBERVALUE(SUBSTITUTE(SUBSTITUTE(A1," ",""),"EUR",""),",",".")'
      ..value = 8880
      ..type = SmlCellType.formula;
    expect(cached.formula, isNotNull);

    final preserved = await OfficeIsolateSave.workbook(
      book,
      recalculate: false,
    );
    final reopened = SheetDeserializer().readBytes(preserved);
    final cell = reopened.firstSheet.cellA1('B1');
    expect(cell.formula, contains('NUMBERVALUE'));
    expect(cell.value, 8880);

    // Recalculation remains available for edited workbooks, and it is the
    // caller's explicit choice rather than a side effect of saving.
    final recalculated = await OfficeIsolateSave.workbook(
      book,
      recalculate: true,
    );
    final recalculatedCell = SheetDeserializer()
        .readBytes(recalculated)
        .firstSheet
        .cellA1('B1');
    expect(recalculatedCell.value, isNot(8880));
  });

  test('a frozen pane is anchored by topLeftCell, not xSplit', () async {
    final book = SmlWorkbook(
      sheets: [
        SmlWorksheet(name: 'Sheet1', sheetId: 1),
      ],
    );
    book.firstSheet
      ..freezeCols = 36
      ..freezeRows = 1
      ..cellA1('AK2').value = 'anchor';
    final saved = await OfficeIsolateSave.workbook(book);
    final xml = OpcPackage.openBytes(saved)
        .getPart('/xl/worksheets/sheet1.xml')!
        .readText();
    expect(xml, contains('topLeftCell="AK2"'));

    // Excel writes xSplit="1" beside topLeftCell="AK2" when many narrow
    // columns fit in the frozen area; the anchor must still win on import.
    final excelStyle = xml
        .replaceFirst('xSplit="36"', 'xSplit="1"')
        .replaceFirst('state="frozen"', 'state="frozenSplit"');
    expect(excelStyle, isNot(xml));
    final package = OpcPackage.openBytes(saved);
    package.getPart('/xl/worksheets/sheet1.xml')!.writeText(excelStyle);
    final reopened = SheetDeserializer().read(package);
    expect(reopened.firstSheet.freezeCols, 36);
    expect(reopened.firstSheet.freezeRows, 1);

    final again = await OfficeIsolateSave.workbook(reopened);
    final reparsed = OpcPackage.openBytes(again)
        .getPart('/xl/worksheets/sheet1.xml')!
        .readText();
    expect(reparsed, contains('topLeftCell="AK2"'));
  });
}
