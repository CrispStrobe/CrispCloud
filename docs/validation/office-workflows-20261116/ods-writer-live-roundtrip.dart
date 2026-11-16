import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';

void require(bool value, String message) {
  if (!value) throw StateError(message);
}
void main(List<String> args) {
  const directory = '/tmp/crispcloud-ods-writer-live-20261116';
  if (args.isEmpty) {
    final styles = SmlStyleSheet();
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1)..setColumnWidth(0, 160)
      ..printArea = SmlRange.parse('A1:F4');
    sheet.cellA1('A1')..value = 'Item'..type = SmlCellType.string..fontBold = true..fillRgb = 'C0FFC0';
    sheet.cellA1('B1').value = 'Qty';
    sheet.cellA1('B2').value = 2;
    sheet.cellA1('B3').value = 3;
    sheet.cellA1('C2')..formula = '=SUM(B2:B3)'..value = 5..type = SmlCellType.formula;
    sheet.cellA1('F2')..value = 0.256..styleIndex = styles.xfFor(numFmtCode: '0.0%');
    sheet.merges.add(SmlMerge.parse('D1:E2'));
    sheet.cellA1('D1').value = 'Wide';
    sheet.comments.add(SmlComment(ref: SmlCellRef.parse('A1'), text: 'Header', author: 'Alice'));
    sheet.cellA1('E4')..value = 'link'..hyperlink = 'https://example.com';
    final book = SmlWorkbook(sheets: [sheet], styles: styles)
      ..namedRanges.add(SmlNamedRange(name: 'Sales', sheetName: 'Data', range: SmlRange.parse('B2:B3')));
    File('$directory/native.ods').writeAsBytesSync(OdsSheetWriter.writeBytes(book));
    print('Generated synthetic ODS: values, formula, style, merge, comment, hyperlink, percentage and named range.');
    return;
  }
  final book = SheetDeserializer().readBytes(File('$directory/converted/native.xlsx').readAsBytesSync());
  final sheet = book.sheets.single;
  require(sheet.name == 'Data', 'Worksheet name');
  require(sheet.cellA1('A1').value == 'Item', 'Text value');
  require(sheet.cellA1('A1').fontBold == true, 'Bold text');
  require(sheet.cellA1('B2').value == 2 && sheet.cellA1('B3').value == 3, 'Numeric values');
  require(sheet.cellA1('C2').formula?.contains('SUM(B2:B3)') == true, 'Formula');
  require(sheet.cellA1('C2').value == 5, 'Calculated formula result');
  require(sheet.merges.any((merge) => merge.a1 == 'D1:E2'), 'Merged range');
  require(sheet.comments.any((comment) => comment.text.contains('Header')), 'Comment');
  require(book.styles!.format(sheet.cellA1('F2').value, sheet.cellA1('F2').styleIndex).contains('25.6'), 'Percentage number format');
  print('PASS: independent LibreOffice ODS → XLSX roundtrip retained all checked values, formulas/results, font style, merges, comments, percentage formatting.');
}
