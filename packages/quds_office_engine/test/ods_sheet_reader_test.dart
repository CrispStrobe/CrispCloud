import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// Synthetic LibreOffice-generated ODS (values, formulas, styles, merge).
void main() {
  edgeTests();
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

  test('covered cells and internal repeated empty rows keep positions', () {
    const content = '''
<office:document-content
 xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
 <office:body><office:spreadsheet><table:table table:name="Budget">
  <table:table-row>
   <table:table-cell office:value-type="string" table:number-columns-spanned="2"><text:p>Heading</text:p></table:table-cell>
   <table:covered-table-cell/>
   <table:table-cell office:value-type="float" office:value="7"/>
  </table:table-row>
  <table:table-row table:number-rows-repeated="2"/>
  <table:table-row><table:table-cell office:value-type="string"><text:p>Tail</text:p></table:table-cell></table:table-row>
 </table:table></office:spreadsheet></office:body>
</office:document-content>
''';
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes(
          'mimetype',
          utf8.encode('application/vnd.oasis.opendocument.spreadsheet'),
        ),
      )
      ..addFile(ArchiveFile.bytes('content.xml', utf8.encode(content)));
    final book = OdsSheetReader.readBytes(
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );
    final sheet = book.sheets.single;
    expect(sheet.name, 'Budget');
    expect(sheet.cellA1('A1').asString, 'Heading');
    expect(sheet.cellA1('C1').value, 7);
    expect(sheet.cellA1('A2').asString, isEmpty);
    expect(sheet.cellA1('A3').asString, isEmpty);
    expect(sheet.cellA1('A4').asString, 'Tail');
    expect(
      sheet.merges.single.c1,
      1,
      reason: 'A1 spans A1:B1; the covered placeholder must not add columns',
    );
  });

  test('rejects a non-ODF package', () {
    expect(
      () => OdsSheetReader.readBytes(Uint8List.fromList(List.filled(64, 0))),
      throwsA(isA<OdsSheetFormatException>()),
    );
  });
}

void edgeTests() {
  final edge = File(
    'test/fixtures/fidelity/legacy-sheet-edge.ods',
  ).readAsBytesSync();

  test('ODS keeps dates, times, booleans, formats and sheet references', () {
    final book = OdsSheetReader.readBytes(edge);
    final sheet = book.sheets.first;
    final styles = book.styles!;

    expect(sheet.cellA1('A1').value, 45293);
    expect(sheet.cellA1('A1').fontBold, isTrue);
    expect(sheet.cellA1('A1').fillRgb, 'C0FFC0');
    expect(styles.format(45293, sheet.cellA1('A1').styleIndex), '02.01.2024');

    expect(sheet.cellA1('A2').value, closeTo(0.5208333, 0.000001));
    expect(
      styles.format(sheet.cellA1('A2').value, sheet.cellA1('A2').styleIndex),
      '12:30',
    );

    expect(sheet.cellA1('A3').value, isTrue);
    expect(sheet.cellA1('B1').formula, 'Sheet2!A1+1');
    expect(sheet.cellA1('B1').value, 42);
    expect(sheet.cellA1('B2').formula, r'$A$1');
    expect(sheet.cellA1('C1').value, closeTo(0.256, 1e-9));
    expect(styles.format(0.256, sheet.cellA1('C1').styleIndex), '25.6%');
    expect(styles.format(1234.5, sheet.cellA1('C2').styleIndex), '1,234.50');

    final merge = sheet.merges.single;
    expect(merge.origin.a1, 'D1');
    expect(merge.c1, 4);
    expect(merge.r1, 1);
    expect(sheet.cellA1('D1').horizontalAlign, SmlHAlign.center);
    expect(book.sheets[1].cellA1('A1').value, 41);
  });

  test('edge ODS survives an xlsx round trip', () async {
    final saved = await OfficeIsolateSave.workbook(
      OdsSheetReader.readBytes(edge),
      recalculate: false,
    );
    final reopened = SheetDeserializer().readBytes(saved);
    expect(reopened.sheets.first.cellA1('A1').value, 45293);
    expect(reopened.sheets.first.cellA1('B1').formula, 'Sheet2!A1+1');
    expect(reopened.sheets.first.merges, hasLength(1));
    expect(
      reopened.styles!.format(
        45293,
        reopened.sheets.first.cellA1('A1').styleIndex,
      ),
      '02.01.2024',
    );
  });
}
