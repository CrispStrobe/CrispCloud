import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('writes a readable ODS package with values, formulas and metadata', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1)
      ..setColumnWidth(0, 160);
    final a1 = sheet.cellA1('A1')
      ..value = 'Item'
      ..type = SmlCellType.string
      ..fontBold = true
      ..fillRgb = 'C0FFC0';
    sheet.cellA1('B1').value = 'Qty';
    sheet.cellA1('A2').value = 'A';
    sheet.cellA1('B2').value = 2;
    sheet.cellA1('B3').value = 3;
    sheet.cellA1('C2')
      ..formula = '=SUM(B2:B3)'
      ..value = 5
      ..type = SmlCellType.formula;
    sheet.merges.add(SmlMerge.parse('D1:E2'));
    sheet.cellA1('D1').value = 'Wide';
    sheet.comments.add(
      SmlComment(ref: SmlCellRef.parse('A1'), text: 'Header', author: 'Alice'),
    );
    sheet.cellA1('E4')
      ..value = 'link'
      ..hyperlink = 'https://example.com';
    final book = SmlWorkbook(sheets: [sheet]);

    final bytes = OdsSheetWriter.writeBytes(book);
    final reopened = OdsSheetReader.readBytes(bytes);
    final data = reopened.sheets.single;

    expect(data.name, 'Data');
    expect(data.cellA1('A1').value, 'Item');
    expect(data.cellA1('A1').fontBold, isTrue);
    expect(data.cellA1('A1').fillRgb, 'C0FFC0');
    expect(data.cellA1('B2').value, 2);
    expect(data.cellA1('C2').formula, 'SUM(B2:B3)');
    expect(data.cellA1('C2').value, 5);
    expect(data.merges.single.a1, 'D1:E2');
    expect(data.cellA1('D1').value, 'Wide');
    expect(data.comments.single.text, 'Header');
    expect(data.comments.single.author, 'Alice');
    expect(data.cellA1('E4').hyperlink, 'https://example.com');
  });

  test('writes workbook metadata and reads it back', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1)
      ..printArea = SmlRange.parse('A1:B3')
      ..printTitleRows = SmlRange.parse('A1:A1')
      ..printTitleCols = SmlRange.parse('A1:A1')
      ..autoFilter = SmlAutoFilter(range: SmlRange.parse('A1:B3'));
    sheet.cellA1('A1').value = 'Name';
    sheet.cellA1('A2').value = 'A';
    sheet.cellA1('B2').value = 1;
    final book = SmlWorkbook(sheets: [sheet])
      ..namedRanges.add(
        SmlNamedRange(
          name: 'Sales',
          sheetName: 'Data',
          range: SmlRange.parse('A2:B3'),
        ),
      )
      ..formulaNames.add(
        SmlFormulaName(name: 'Total', formula: 'SUM(Data!B2:B3)'),
      );
    final reopened = OdsSheetReader.readBytes(OdsSheetWriter.writeBytes(book));
    final data = reopened.sheets.single;
    String a1(SmlRange range) => '${range.start.a1}:${range.end.a1}';
    expect(a1(data.printArea!), 'A1:B3');
    expect(a1(data.printTitleRows!), 'A1:A1');
    expect(a1(data.printTitleCols!), 'A1:A1');
    expect(a1(data.autoFilter!.range), 'A1:B3');
    expect(reopened.namedRanges.single.name, 'Sales');
    expect(reopened.formulaNames.single.name, 'Total');
  });

  test('writes authored number formats', () {
    final styles = SmlStyleSheet();
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('A1')
      ..value = 0.256
      ..styleIndex = styles.xfFor(numFmtCode: '0.0%');
    final book = SmlWorkbook(sheets: [sheet], styles: styles);
    final reopened = OdsSheetReader.readBytes(OdsSheetWriter.writeBytes(book));
    final cell = reopened.sheets.first.cellA1('A1');
    expect(reopened.styles!.format(cell.value, cell.styleIndex), '25.6%');
  });

  test('writes multiple sheets, hidden state and tab colours', () {
    final visible = SmlWorksheet(name: 'Visible', sheetId: 1)
      ..tabColorRgb = 'FF0000';
    visible.cellA1('A1').value = 1;
    final hidden = SmlWorksheet(name: 'Hidden', sheetId: 2, hidden: true);
    hidden.cellA1('A1').value = 2;
    final bytes = OdsSheetWriter.writeBytes(
      SmlWorkbook(sheets: [visible, hidden]),
    );
    final reopened = OdsSheetReader.readBytes(bytes);
    expect(reopened.sheets.length, 2);
    expect(reopened.sheets.first.tabColorRgb, 'FF0000');
    expect(reopened.sheets.last.hidden, isTrue);
    expect(reopened.sheets.last.cellA1('A1').value, 2);
  });

  test('translates a sheet-qualified formula before writing', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('A1').value = 1;
    sheet.cellA1('A2').value = 2;
    sheet.cellA1('B1')
      ..formula = '=SUM(Data!A1:A2)'
      ..value = 3
      ..type = SmlCellType.formula;
    final bytes = OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet]));
    final reopened = OdsSheetReader.readBytes(bytes);
    expect(reopened.sheets.first.cellA1('B1').formula, "SUM('Data'!A1:A2)");
  });
}
