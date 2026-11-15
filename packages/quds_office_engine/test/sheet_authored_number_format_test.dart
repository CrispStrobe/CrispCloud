import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// A cell xf may introduce a custom number format id. The serializer must
/// write that id's `<numFmt>` entry, otherwise strict readers (openpyxl,
/// Open XML SDK) index past the end of `<numFmts>` and reject the package.
void main() {
  test('an authored custom number format is written and reloads', () async {
    final book = SmlWorkbook(
      sheets: [
        SmlWorksheet(name: 'Sheet1', sheetId: 1),
      ],
    );
    final sheet = book.firstSheet;
    final cell = sheet.cellA1('A1')..value = 1234.5;
    final styles = book.styles ??= SmlStyleSheet();
    while (styles.cellXfsAlign.length < 2) {
      styles.cellXfsNumFmt.add(0);
      styles.cellXfsAlign.add(SmlHAlign.general);
      styles.cellXfsFillId.add(0);
      styles.cellXfsFontId.add(0);
    }
    styles.numFmts[170] = '#,##0.00 "EUR"';
    styles.cellXfsNumFmt.add(170);
    styles.cellXfsAlign.add(SmlHAlign.general);
    styles.cellXfsFillId.add(0);
    styles.cellXfsFontId.add(0);
    cell
      ..styleIndex = styles.cellXfsNumFmt.length - 1
      ..hasExplicitStyleIndex = true;

    final bytes = await OfficeIsolateSave.workbook(book, recalculate: false);
    final text = OpcPackage.openBytes(bytes).getPart('/xl/styles.xml')!.readText();
    expect(text, contains('numFmtId="170"'));
    expect(text, contains('#,##0.00'));
    expect(text, contains(r'&quot;EUR&quot;'));
    expect(text.indexOf('<numFmts'), lessThan(text.indexOf('<fonts')));

    final reopened = SheetDeserializer().readBytes(bytes);
    expect(reopened.styles!.numFmts[170], '#,##0.00 "EUR"');
    expect(reopened.firstSheet.cellA1('A1').styleIndex, 2);
  });

  test('authored formats merge with a native numFmts collection', () async {
    final book = SheetDeserializer().readBytes(
      File('test/fixtures/fidelity/native.xlsx').readAsBytesSync(),
    );
    final styles = book.styles ??= SmlStyleSheet();
    styles.numFmts[200] = '0.0000';
    styles.cellXfsNumFmt.add(200);
    styles.cellXfsAlign.add(SmlHAlign.general);
    styles.cellXfsFillId.add(0);
    styles.cellXfsFontId.add(0);

    final bytes = await OfficeIsolateSave.workbook(book, recalculate: false);
    final text = OpcPackage.openBytes(bytes).getPart('/xl/styles.xml')!.readText();
    expect(text, contains('numFmtId="200"'));
    final reopened = SheetDeserializer().readBytes(bytes);
    expect(reopened.styles!.numFmts[200], '0.0000');
    expect(reopened.styles!.numFmts.length, greaterThan(1));
  });
}
