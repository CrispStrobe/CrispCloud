import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// Synthetic BIFF8 workbook (no private data): two sheets, styled header,
/// numbers, percentages, a date, formulas, a merged title and column widths.
void main() {
  sharedFormulaTests();
  final bytes = File(
    'test/fixtures/fidelity/legacy-sheet.xls',
  ).readAsBytesSync();

  test('reads BIFF8 values, types, formulas and styles', () {
    final book = LegacySheetReader.readBytes(bytes);
    expect(book.sheets.map((sheet) => sheet.name), ['Data', 'Notes']);
    final data = book.sheets.first;

    expect(data.cellA1('A1').asString, 'Quarter');
    expect(data.cellA1('A1').fontBold, isTrue);
    expect(data.cellA1('A1').fontSize, 12);
    expect(data.cellA1('A1').fillRgb, isNotEmpty);

    expect(data.cellA1('B2').value, 1240.5);
    expect(data.cellA1('C2').value, 0.31);
    expect(data.cellA1('C10').value, isTrue);

    final total = data.cellA1('B7');
    expect(total.formula, 'SUM(B2:B5)');
    expect(total.value, 4000.75);
    expect(total.type, SmlCellType.formula);
    expect(data.cellA1('B10').formula, '(B7/4)');
  });

  test('keeps number formats, merges, widths and row heights', () {
    final book = LegacySheetReader.readBytes(bytes);
    final data = book.sheets.first;
    final styles = book.styles!;

    expect(styles.format(1240.5, data.cellA1('B2').styleIndex), '1,240.50');
    expect(styles.format(0.31, data.cellA1('C2').styleIndex), '31.0%');
    expect(styles.format(45000, data.cellA1('A10').styleIndex), '15.03.2023');

    expect(
      data.merges.map((merge) => '${merge.origin.a1}'),
      contains('A12'),
    );
    expect(data.exportColumnWidth(0), closeTo(14.00390625, 0.0001));
    expect(data.exportColumnWidth(1), closeTo(22.00390625, 0.0001));
    expect(data.rowHeightAt(0), closeTo(32, 0.5));
    // Only the styled row is explicit; default rows are not materialized.
    expect(data.rowHeights.length, 1);
  });

  test('an imported .xls saves as a readable .xlsx', () async {
    final book = LegacySheetReader.readBytes(bytes);
    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final reopened = SheetDeserializer().readBytes(saved);
    expect(reopened.sheets.map((sheet) => sheet.name), ['Data', 'Notes']);
    expect(reopened.sheets.first.cellA1('A1').asString, 'Quarter');
    expect(reopened.sheets.first.cellA1('B7').formula, 'SUM(B2:B5)');
    expect(reopened.sheets.first.cellA1('B7').value, 4000.75);
    expect(reopened.styles!.format(1240.5, reopened.sheets.first.cellA1('B2').styleIndex), '1,240.50');
  });

  test('reads the HTML-table flavour of .xls', () {
    const html =
        '<html><head><xml><x:ExcelWorkbook><x:ExcelWorksheets>'
        '<x:ExcelWorksheet><x:Name>Ark1</x:Name></x:ExcelWorksheet>'
        '</x:ExcelWorksheets></x:ExcelWorkbook></xml></head><body>'
        '<table><tr><td>Name</td><td x:num="2">zwei</td></tr>'
        '<tr><td colspan="2">wide</td></tr></table></body></html>';
    final book = LegacySheetReader.readBytes(
      Uint8List.fromList(const Utf8Encoder().convert(html)),
    );
    expect(book.sheets.single.name, 'Ark1');
    expect(book.sheets.single.cellA1('A1').asString, 'Name');
    expect(book.sheets.single.cellA1('B1').value, 2);
    expect(book.sheets.single.merges.single.isSingle, isFalse);
  });

  test('rejects non-BIFF and truncated input', () {
    expect(
      () => LegacySheetReader.readBytes(Uint8List.fromList(List.filled(32, 0))),
      throwsA(isA<LegacySheetFormatException>()),
    );
    expect(
      () => LegacySheetReader.readBytes(bytes.sublist(0, 600)),
      throwsA(isA<LegacySheetFormatException>()),
    );
  });
}

void sharedFormulaTests() {
  test('shared formula groups expand across their range', () {
    final book = LegacySheetReader.readBytes(
      File('test/fixtures/fidelity/legacy-shared-formula.xls').readAsBytesSync(),
    );
    final sheet = book.sheets.first;
    expect(sheet.cellA1('B1').formula, '(A1*2)');
    expect(sheet.cellA1('B2').formula, '(A2*2)');
    expect(sheet.cellA1('B50').formula, '(A50*2)');
    expect(sheet.cellA1('B50').value, 100);
  });
}
