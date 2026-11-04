import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('evaluates arithmetic, logic, lookup, and text functions', () {
    final SmlWorkbook book = SmlWorkbook();
    final SmlWorksheet s = book.firstSheet;
    s.cellA1('A1').value = 10;
    s.cellA1('A2').value = 20;
    s.cellA1('A3').value = 30;
    s.cellA1('B1').value = 'hello';
    final FormulaContext ctx = FormulaContext(
      workbook: book,
      sheet: s,
      origin: SmlCellRef.parse('C1'),
    );

    expect(evaluateFormula('=SUM(A1:A3)', ctx), 60);
    expect(evaluateFormula('=COUNTA(A1:A3)', ctx), 3);
    expect(evaluateFormula('=AVERAGE(A1:A3)', ctx), 20);
    expect(evaluateFormula('=IF(A1>5,"yes","no")', ctx), 'yes');
    expect(evaluateFormula('=AND(TRUE,1)', ctx), isTrue);
    expect(evaluateFormula('=CONCATENATE(B1,"!")', ctx), 'hello!');
    expect(evaluateFormula('=LEFT(B1,2)', ctx), 'he');
    expect(evaluateFormula('=ROUND(1.26,1)', ctx), closeTo(1.3, 0.0001));
    expect(evaluateFormula('=2^3+1', ctx), 9);
    expect(evaluateFormula('=A1+A2', ctx), 30);
    expect(evaluateFormula('=SUM(A1 : A3)', ctx), 60);
    expect(evaluateFormula('=SUM(A1; A3)', ctx), 40);
    expect(evaluateFormula('=A1*10%', ctx), 1);
    expect(evaluateFormula('=  A1 + A2  ', ctx), 30);

    s.cellA1('D1').value = 'x';
    s.cellA1('E1').value = 5;
    s.cellA1('D2').value = 'y';
    s.cellA1('E2').value = 9;
    expect(evaluateFormula('=VLOOKUP("y",D1:E2,2)', ctx), 9);
  });

  test('detects circular references and recalculates a workbook', () {
    final SmlWorkbook book = SmlWorkbook();
    book.firstSheet.cellA1('A1').value = 2;
    book.firstSheet.cellA1('A2').formula = '=A1*3';
    book.firstSheet.cellA1('A3').formula = '=SUM(A1:A2)';
    FormulaDepGraph(book).recalculate();
    expect(book.firstSheet.cellA1('A2').asNumber, 6);
    expect(book.firstSheet.cellA1('A3').asNumber, 8);

    book.firstSheet.cellA1('B1').formula = '=B2';
    book.firstSheet.cellA1('B2').formula = '=B1';
    final FormulaDepGraph g = FormulaDepGraph(book);
    g.recalculate();
    expect(g.circular, isNotEmpty);
  });

  test('merge and center keeps the origin and clears the rest', () {
    final SmlWorksheet sheet = SmlWorkbook().firstSheet;
    sheet.cellA1('A1').value = 'Title';
    sheet.cellA1('B1').value = 'other';
    sheet.mergeAndCenter(SmlRange.parse('A1:C1'));
    expect(sheet.merges, hasLength(1));
    expect(sheet.merges.first.a1, 'A1:C1');
    expect(sheet.cellA1('A1').asString, 'Title');
    expect(sheet.cellA1('A1').horizontalAlign, SmlHAlign.center);
    expect(sheet.cellA1('B1').hasContent, isFalse);
    expect(sheet.isCovered(1, 0), isTrue);
    expect(sheet.mergeAt(2, 0)?.origin.a1, 'A1');
    sheet.toggleMergeAndCenter(SmlRange.parse('A1:C1'));
    expect(sheet.merges, isEmpty);
    expect(sheet.cellA1('A1').asString, 'Title');
  });

  test('parses solid fills and paints them as RGB on the cell', () {
    const String xml =
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fills count="3">'
        '<fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FF000000"/></patternFill></fill>'
        '</fills>'
        '<cellXfs count="2">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>'
        '<xf numFmtId="0" fontId="0" fillId="2" borderId="0" applyFill="1"/>'
        '</cellXfs></styleSheet>';
    final SmlStyleSheet styles = SmlStyleSheet.parse(xml);
    expect(styles.fillAt(1), '000000');
    expect(SmlStyleSheet.applyTint('4F81BD', -0.25), isNot(equals('4F81BD')));
  });

  test('round-trips merged cells and center alignment', () {
    final SmlWorkbook book = SmlWorkbook();
    book.firstSheet.cellA1('B2').value = 'Banner';
    book.firstSheet.mergeAndCenter(SmlRange.parse('B2:D3'));
    final bytes = SheetSerializer().writeBytes(book);
    final String xml = OpcPackage.openBytes(
      bytes,
    ).getPart('/xl/worksheets/sheet1.xml')!.readText();
    expect(xml, contains('mergeCell'));
    expect(xml, contains('B2:D3'));
    final String? styles = OpcPackage.openBytes(
      bytes,
    ).getPart('/xl/styles.xml')?.readText();
    expect(styles, isNotNull);
    expect(styles, contains('horizontal="center"'));
    final SmlWorkbook opened = SheetDeserializer().readBytes(bytes);
    expect(opened.firstSheet.merges, hasLength(1));
    expect(opened.firstSheet.merges.first.a1, 'B2:D3');
    expect(opened.firstSheet.cellA1('B2').asString, 'Banner');
    expect(opened.firstSheet.cellA1('B2').horizontalAlign, SmlHAlign.center);
    expect(opened.firstSheet.isCovered(3, 2), isTrue);
  });

  test('round-trips cell fill and font colors', () {
    final SmlWorkbook book = SmlWorkbook();
    book.firstSheet.cellA1('A1')
      ..value = 'Bar'
      ..fillRgb = '000000'
      ..fontRgb = 'FFFFFF';
    final bytes = SheetSerializer().writeBytes(book);
    final String styles = OpcPackage.openBytes(
      bytes,
    ).getPart('/xl/styles.xml')!.readText();
    expect(styles, contains('patternType="solid"'));
    expect(styles, contains('000000'));
    final SmlWorkbook opened = SheetDeserializer().readBytes(bytes);
    expect(opened.firstSheet.cellA1('A1').fillRgb, '000000');
    expect(opened.firstSheet.cellA1('A1').fontRgb, 'FFFFFF');
  });

  test('insert and delete rows shift merged ranges', () {
    final SmlWorksheet sheet = SmlWorkbook().firstSheet;
    sheet.mergeAndCenter(SmlRange.parse('A2:B3'));
    sheet.insertRows(1);
    expect(sheet.merges.first.a1, 'A3:B4');
    sheet.deleteRows(1);
    expect(sheet.merges.first.a1, 'A2:B3');
    sheet.insertCols(0);
    expect(sheet.merges.first.a1, 'B2:C3');
  });

  test('round-trips frozen panes', () {
    final SmlWorkbook book = SmlWorkbook();
    book.firstSheet.freezeRows = 4;
    book.firstSheet.freezeCols = 2;
    book.firstSheet.cellA1('C5').value = 1;
    final bytes = SheetSerializer().writeBytes(book);
    final String xml = OpcPackage.openBytes(
      bytes,
    ).getPart('/xl/worksheets/sheet1.xml')!.readText();
    expect(xml, contains('xSplit="2"'));
    expect(xml, contains('ySplit="4"'));
    expect(xml, contains('topLeftCell="C5"'));
    expect(xml, contains('state="frozen"'));
    final SmlWorkbook opened = SheetDeserializer().readBytes(bytes);
    expect(opened.firstSheet.freezeRows, 4);
    expect(opened.firstSheet.freezeCols, 2);
  });

  test('round-trips sheetView rightToLeft', () {
    final SmlWorkbook book = SmlWorkbook();
    book.firstSheet.rightToLeft = true;
    book.firstSheet.cellA1('A1').value = 'مرحبا';
    final bytes = SheetSerializer().writeBytes(book);
    final String xml = OpcPackage.openBytes(
      bytes,
    ).getPart('/xl/worksheets/sheet1.xml')!.readText();
    expect(xml, contains('rightToLeft="1"'));
    expect(xml, contains('<sheetViews>'));
    final SmlWorkbook opened = SheetDeserializer().readBytes(bytes);
    expect(opened.firstSheet.rightToLeft, isTrue);
    expect(opened.firstSheet.cellA1('A1').asString, 'مرحبا');
  });

  test('round-trips a multi-sheet workbook', () {
    final SmlWorkbook book = SmlWorkbook(
      sheets: <SmlWorksheet>[
        SmlWorksheet(name: 'Data', sheetId: 1),
        SmlWorksheet(name: 'Calc', sheetId: 2),
      ],
    );
    book.sheets[0].cellA1('A1').value = 42;
    book.sheets[1].cellA1('A1').formula = '=Data!A1+1';
    FormulaDepGraph(book).recalculate();
    final bytes = SheetSerializer().writeBytes(book);
    final SmlWorkbook opened = SheetDeserializer().readBytes(bytes);
    expect(opened.sheets.length, 2);
    expect(opened.sheetByName('Data')!.cellA1('A1').asNumber, 42);
    expect(opened.sheetByName('Calc')!.cellA1('A1').formula, isNotNull);
  });

  test('parses quoted and unicode sheet names', () {
    final SmlWorkbook book = SmlWorkbook(
      sheets: <SmlWorksheet>[
        SmlWorksheet(name: 'Data', sheetId: 1),
        SmlWorksheet(name: 'لوحة', sheetId: 2),
      ],
    );
    book.sheets[0].cellA1('A1').value = 7;
    book.sheets[1].cellA1('B2').value = 11;
    final FormulaContext ctx = FormulaContext(
      workbook: book,
      sheet: book.sheets[1],
      origin: SmlCellRef.parse('A1'),
    );
    expect(evaluateFormula("='Data'!A1+1", ctx), 8);
    expect(evaluateFormula('=لوحة!B2', ctx), 11);
  });

  test(
    'applyInput caches the computed value and recalculate updates dependents',
    () {
      final SmlWorkbook book = SmlWorkbook();
      final SmlWorksheet s = book.firstSheet;
      FormulaEvaluator.applyInput(book, s, s.cellA1('A1'), '4');
      FormulaEvaluator.applyInput(book, s, s.cellA1('B1'), '6');
      FormulaEvaluator.applyInput(book, s, s.cellA1('C1'), '=A1+B1');
      expect(s.cellA1('C1').value, 10);
      expect(s.cellA1('C1').formula, '=A1+B1');
      expect(s.cellA1('C1').type, SmlCellType.formula);

      FormulaEvaluator.applyInput(book, s, s.cellA1('A1'), '9');
      FormulaEvaluator.recalculate(book);
      expect(s.cellA1('C1').value, 15);
      expect(FormulaEvaluator.evaluateCell(book, s, s.cellA1('C1')), 15);
    },
  );

  test('scans formula references with source offsets', () {
    final List<FormulaRefSpan> refs = FormulaRefScanner.scan('=A1+B1');
    expect(refs, hasLength(2));
    expect(refs[0].lexeme, 'A1');
    expect('=A1+B1'.substring(refs[0].start, refs[0].end), 'A1');
    expect(refs[0].range.start.a1, 'A1');
    expect(refs[1].lexeme, 'B1');
    expect('=A1+B1'.substring(refs[1].start, refs[1].end), 'B1');

    final List<FormulaRefSpan> range = FormulaRefScanner.scan('=SUM(A1:B2)');
    expect(range, hasLength(1));
    expect(range.first.lexeme, 'A1:B2');
    expect(range.first.range.start.a1, 'A1');
    expect(range.first.range.end.a1, 'B2');

    expect(FormulaRefScanner.scan('42'), isEmpty);
    expect(FormulaRefScanner.scan('="A1"+C3'), hasLength(1));
    expect(FormulaRefScanner.scan('="A1"+C3').first.lexeme, 'C3');

    final List<FormulaRefSpan> sheetRef = FormulaRefScanner.scan(
      "='لوحة'!B2+A1",
    );
    expect(sheetRef, hasLength(2));
    expect(sheetRef[0].sheetName, 'لوحة');
    expect(sheetRef[0].onSheet('لوحة'), isTrue);
    expect(sheetRef[0].onSheet('Budget'), isFalse);
    expect(sheetRef[1].onSheet('Budget'), isTrue);
    expect(sheetRef[0].colorKey, isNot(sheetRef[1].colorKey));
    final List<FormulaRefSpan> abs = FormulaRefScanner.scan('=A1+\$A\$1');
    expect(abs, hasLength(2));
    expect(abs[0].colorKey, abs[1].colorKey);
  });

  test('function guide searches names and ignores cell refs', () {
    expect(FormulaFunctionGuide.search('SU').first.name, 'SUM');
    expect(FormulaFunctionGuide.byName('STDEV.S')?.name, 'STDEV');
    expect(FormulaFunctionGuide.all, isNotEmpty);
    final FormulaNameQuery? q = FormulaFunctionGuide.queryAt('=SU', 3);
    expect(q?.prefix, 'SU');
    expect(FormulaFunctionGuide.queryAt('=A1', 3), isNull);
    expect(FormulaFunctionGuide.queryAt('hello', 3), isNull);
  });

  test('formats numbers via styles.xml codes', () {
    expect(applyNumberFormat(0.25, '0%'), '25%');
    expect(applyNumberFormat(0.256, '0.0%'), '25.6%');
    expect(applyNumberFormat(968000.0000000001, '#,##0'), '968,000');
    expect(applyNumberFormat(968000.0000000001, '#,##0.00'), '968,000.00');
    expect(applyNumberFormat(968000.0000000001, '0'), '968000');
    expect(applyNumberFormat(-1234.5, r'"$"#,##0.00'), r'-$1,234.50');
    expect(applyNumberFormat(-1234.5, '#,##0.00;(#,##0.00)'), '(1,234.50)');
    expect(applyNumberFormat(0, '#,##0;-#,##0;"-"'), '-');
    expect(applyNumberFormat(1234567, '#,##0,'), '1,235');
    expect(applyNumberFormat(7, '000'), '007');
    expect(applyNumberFormat(1.5, '0.0#'), '1.5');
    expect(applyNumberFormat(1234.5, r'#,##0.00 "SAR"'), '1,234.50 SAR');
    expect(applyNumberFormat(1234.5, r'[$€-407] #,##0.00'), '€ 1,234.50');
    expect(applyNumberFormat(-3, '[Red]0'), 'RED:-3');
    expect(applyNumberFormat(12.3, '0.00'), '12.30');
    final DateTime sep = DateTime.utc(2026, 9, 9);
    final double serial =
        sep.difference(DateTime.utc(1899, 12, 30)).inDays.toDouble();
    expect(applyNumberFormat(serial, 'd-mmm'), '9-Sep');
    expect(applyNumberFormat(serial, 'yyyy-mm-dd'), '2026-09-09');
  });

  test('swaps Excel theme lt/dk indices when resolving colors', () {
    const List<String> scheme = <String>[
      '000000',
      'FFFFFF',
      '1F497D',
      'EEECE1',
    ];
    expect(
      SmlStyleSheet.resolveColor(theme: '0', themeColors: scheme),
      'FFFFFF',
    );
    expect(
      SmlStyleSheet.resolveColor(theme: '1', themeColors: scheme),
      '000000',
    );
    expect(
      SmlStyleSheet.resolveColor(theme: '2', themeColors: scheme),
      'EEECE1',
    );
    expect(
      SmlStyleSheet.resolveColor(theme: '3', themeColors: scheme),
      '1F497D',
    );
    expect(SmlStyleSheet.themeSchemeIndex(4), 4);
  });

  test('column and row metrics stay inside Excel limits', () {
    final SmlWorksheet sheet = SmlWorksheet(name: 'Sheet1', sheetId: 1);
    expect(SmlWorksheet.excelColumnCount, 16384);
    expect(SmlWorksheet.excelRowCount, 1048576);
    expect(sheet.columnAt(0), 0);
    expect(sheet.columnAt(64), 1);
    expect(sheet.columnAt(64 * 20 + 1), 20);
    expect(sheet.rowAt(20 * 40 + 1), 40);
    sheet.setColumnWidth(2, 96);
    expect(sheet.columnLeft(2), 128);
    expect(sheet.columnLeft(3), 224);
    expect(sheet.columnAt(150), 2);
    sheet.setRowHeight(1, 40);
    expect(sheet.rowTop(1), 20);
    expect(sheet.rowTop(2), 60);
    expect(sheet.rowAt(50), 1);
  });

  test('reads Gantt-like builder fills, fonts, merges and freeze', () {
    final XlsxWorkbookBuilder book = XlsxWorkbookBuilder();
    final int title = book.style(
      bold: true,
      size: 16,
      color: 'FFFFFFFF',
      fillRgb: 'FF181464',
      horizontal: 'left',
    );
    final int month = book.style(
      bold: true,
      color: 'FF181464',
      fillRgb: 'FFECEAF7',
      horizontal: 'center',
    );
    final int bar = book.style(
      color: 'FF6B6A9E',
      fillRgb: 'FF6B6A9E',
      horizontal: 'center',
    );
    final XlsxSheetBuilder sheet = book.addSheet('Gantt');
    sheet.freezeRows = 5;
    sheet.freezeCols = 2;
    sheet.setCell(0, 0, 'Gantt chart — As Sabra', style: title);
    for (int c = 1; c <= 10; c++) {
      sheet.setCell(0, c, '', style: title);
    }
    sheet.merge(0, 0, 0, 10);
    sheet.setCell(3, 6, 'Sep 2026', style: month);
    for (int c = 7; c <= 10; c++) {
      sheet.setCell(3, c, '', style: month);
    }
    sheet.merge(3, 6, 3, 10);
    sheet.setCell(6, 6, '█', style: bar);
    final bytes = book.build();
    final SmlWorkbook opened = SheetDeserializer().readBytes(bytes);
    final SmlWorksheet ws = opened.firstSheet;
    expect(ws.freezeRows, 5);
    expect(ws.freezeCols, 2);
    expect(ws.merges.map((SmlMerge m) => m.a1).toList(), contains('A1:K1'));
    expect(ws.merges.map((SmlMerge m) => m.a1).toList(), contains('G4:K4'));
    expect(ws.cellA1('A1').asString, 'Gantt chart — As Sabra');
    expect(ws.cellA1('A1').fillRgb, '181464');
    expect(ws.cellA1('A1').fontRgb, 'FFFFFF');
    expect(ws.cellA1('A1').fontBold, isTrue);
    expect(ws.cellA1('A1').fontSize, 16);
    expect(ws.cellA1('G4').asString, 'Sep 2026');
    expect(ws.cellA1('G4').fillRgb, 'ECEAF7');
    expect(ws.cellA1('G4').horizontalAlign, SmlHAlign.center);
    expect(ws.cellA1('G7').asString, '█');
    expect(ws.cellA1('G7').fillRgb, '6B6A9E');
    expect(ws.cellA1('G7').fontRgb, '6B6A9E');
  });

  test('round-trips custom column widths and row heights', () {
    final SmlWorkbook book = SmlWorkbook();
    book.firstSheet.setColumnWidth(0, 96);
    book.firstSheet.setColumnWidth(1, 96);
    book.firstSheet.setRowHeight(2, 40);
    book.firstSheet.cellA1('A1').value = 1;
    final bytes = SheetSerializer().writeBytes(book);
    final String xml = OpcPackage.openBytes(
      bytes,
    ).getPart('/xl/worksheets/sheet1.xml')!.readText();
    expect(xml, contains('<cols>'));
    expect(xml, contains('customWidth="1"'));
    expect(xml, contains('customHeight="1"'));
    final SmlWorkbook opened = SheetDeserializer().readBytes(bytes);
    expect(opened.firstSheet.columnWidth(0), closeTo(96, 0.6));
    expect(opened.firstSheet.columnWidth(1), closeTo(96, 0.6));
    expect(opened.firstSheet.rowHeightAt(2), closeTo(40, 0.6));
  });

  test('FILTER UNIQUE SORT and LET evaluate', () {
    final SmlWorkbook book = SmlWorkbook();
    final SmlWorksheet s = book.firstSheet;
    s.cellA1('A1').value = 10;
    s.cellA1('A2').value = 20;
    s.cellA1('A3').value = 10;
    s.cellA1('B1').value = true;
    s.cellA1('B2').value = false;
    s.cellA1('B3').value = true;
    final FormulaContext ctx = FormulaContext(
      workbook: book,
      sheet: s,
      origin: SmlCellRef.parse('C1'),
    );
    expect(evaluateFormula('=FILTER(A1:A3,B1:B3)', ctx), '10,10');
    expect(evaluateFormula('=UNIQUE(A1:A3)', ctx), '10,20');
    expect(evaluateFormula('=SORT(A3:A1)', ctx), '10,10,20');
    expect(evaluateFormula('=LET(x,A1,x+5)', ctx), 15);
  });

  test('sorts filters and names a worksheet range', () {
    final SmlWorkbook book = SmlWorkbook();
    final SmlWorksheet sheet = book.firstSheet;
    sheet.cellA1('A1').value = 'Name';
    sheet.cellA1('B1').value = 'Score';
    sheet.cellA1('A2').value = 'Zed';
    sheet.cellA1('B2').value = 3;
    sheet.cellA1('A3').value = 'Ann';
    sheet.cellA1('B3').value = 9;
    final SmlRange table = SmlRange.parse('A1:B3');
    SmlAnalysis.sort(sheet, table, <SmlSortKey>[
      const SmlSortKey(column: 0, ascending: true),
    ]);
    expect(sheet.cellA1('A2').asString, 'Ann');
    expect(sheet.cellA1('B2').asNumber, 9);
    sheet.autoFilter = SmlAutoFilter(range: table)
      ..hiddenValues[0] = <String>{'Zed'};
    expect(sheet.autoFilter!.isRowHidden(sheet, 1), isFalse);
    expect(sheet.autoFilter!.isRowHidden(sheet, 2), isTrue);
    book.namedRanges.add(
      SmlNamedRange(name: 'Scores', sheetName: sheet.name, range: table),
    );
    final SmlWorkbook opened = SheetDeserializer().readBytes(
      SheetSerializer().writeBytes(book),
    );
    expect(opened.namedRanges.single.name, 'Scores');
    expect(opened.firstSheet.autoFilter, isNotNull);
  });

  test('resolves names and high-use formulas including SEQUENCE spill', () {
    final SmlWorkbook book = SmlWorkbook();
    final SmlWorksheet sheet = book.firstSheet;
    sheet.cellA1('A1').value = 2;
    book.namedRanges.add(
      SmlNamedRange(
        name: 'Two',
        sheetName: sheet.name,
        range: SmlRange.parse('A1:A1'),
      ),
    );
    final FormulaContext ctx = FormulaContext(
      workbook: book,
      sheet: sheet,
      origin: SmlCellRef.parse('C1'),
    );
    expect(evaluateFormula('=Two+3', ctx), 5);
    expect(evaluateFormula('=SIN(0)', ctx), closeTo(0, 0.0001));
    expect(evaluateFormula('=COS(0)', ctx), closeTo(1, 0.0001));
    expect(evaluateFormula('=TEXT(12,"0.00")', ctx), '12.00');
    expect(evaluateFormula('=INDIRECT("A1")', ctx), 2);
    expect(evaluateFormula('=OFFSET(A1,0,0)', ctx), 2);
    FormulaEvaluator.applyInput(book, sheet, sheet.cellA1('B1'), '=SEQUENCE(2,2,1,1)');
    expect(sheet.cellA1('B1').value, 1);
    expect(sheet.cellA1('C1').value, 2);
    expect(sheet.cellA1('B2').value, 3);
    expect(sheet.cellA1('C2').value, 4);
  });

  test('persists validation comments tables and hides filtered rows', () {
    final SmlWorkbook book = SmlWorkbook();
    final SmlWorksheet sheet = book.firstSheet;
    sheet.cellA1('A1').value = 'H';
    sheet.cellA1('A2').value = 'keep';
    sheet.cellA1('A3').value = 'hide';
    sheet.validations.add(
      SmlDataValidation(
        range: SmlRange.parse('B1:B1'),
        kind: SmlValidationKind.list,
        formula1: 'Yes,No',
      ),
    );
    sheet.conditionalFormats.add(
      SmlConditionalRule(
        range: SmlRange.parse('A2:A3'),
        kind: SmlConditionalKind.equal,
        formula: 'keep',
      ),
    );
    sheet.comments.add(
      SmlComment(ref: SmlCellRef.parse('A1'), text: 'Header'),
    );
    sheet.tables.add(
      SmlTable(name: 'T1', range: SmlRange.parse('A1:A3')),
    );
    sheet.protection = SmlSheetProtection(enabled: true);
    sheet.autoFilter = SmlAutoFilter(range: SmlRange.parse('A1:A3'))
      ..hiddenValues[0] = <String>{'hide'};
    expect(sheet.rowHeightAt(2), 0);
    expect(SmlAnalysis.validateInput(sheet, SmlCellRef.parse('B1'), 'Nope'), isNotNull);
    expect(SmlAnalysis.validateInput(sheet, SmlCellRef.parse('B1'), 'Yes'), isNull);
    final SmlWorkbook opened = SheetDeserializer().readBytes(
      SheetSerializer().writeBytes(book),
    );
    expect(opened.firstSheet.validations, isNotEmpty);
    expect(opened.firstSheet.conditionalFormats, isNotEmpty);
    expect(opened.firstSheet.comments.single.text, 'Header');
    expect(opened.firstSheet.tables.single.name, 'T1');
    expect(opened.firstSheet.protection?.enabled, isTrue);
  });

  test('evaluates a pivot table', () {
    final SmlWorkbook book = SmlWorkbook();
    final SmlWorksheet sheet = book.firstSheet;
    sheet.cellA1('A1').value = 'Cat';
    sheet.cellA1('B1').value = 'Amt';
    sheet.cellA1('A2').value = 'A';
    sheet.cellA1('B2').value = 4;
    sheet.cellA1('A3').value = 'A';
    sheet.cellA1('B3').value = 6;
    sheet.cellA1('A4').value = 'B';
    sheet.cellA1('B4').value = 3;
    final SmlPivotTable pivot = SmlPivotTable(
      source: SmlRange.parse('A1:B4'),
      rowField: 0,
      dataField: 1,
    );
    pivot.materialize(sheet, SmlCellRef.parse('D1'));
    expect(sheet.cellA1('D2').asString, 'A');
    expect(sheet.cellA1('E2').asNumber, 10);
    expect(sheet.cellA1('D3').asString, 'B');
    expect(sheet.cellA1('E3').asNumber, 3);
  });

  test('honest formulas structured refs fill and filter hide', () {
    final SmlWorkbook book = SmlWorkbook();
    final SmlWorksheet sheet = book.firstSheet;
    sheet.cellA1('A1').value = 'Amt';
    sheet.cellA1('A2').value = 2;
    sheet.cellA1('A3').value = 4;
    sheet.tables.add(
      SmlTable(name: 'Sales', range: SmlRange.parse('A1:A3')),
    );
    final FormulaContext ctx = FormulaContext(
      workbook: book,
      sheet: sheet,
      origin: SmlCellRef.parse('B1'),
    );
    expect(evaluateFormula('=SUM(Sales[Amt])', ctx), 6);
    sheet.cellA1('C1').formula = '=A2+A3';
    FormulaEvaluator.evaluateCell(book, sheet, sheet.cellA1('C1'));
    expect(evaluateFormula('=FORMULATEXT(C1)', ctx), '=A2+A3');
    final Object? rand = evaluateFormula('=RAND()', ctx);
    expect(rand, isA<num>());
    expect((rand as num) >= 0 && rand <= 1, isTrue);
    expect(evaluateFormula('=TIME(6,0,0)', ctx), closeTo(0.25, 0.0001));
    expect(evaluateFormula('=IRR(-100,60,60)', ctx), isA<num>());
    SmlAnalysis.fillSeries(sheet, SmlRange.parse('A2:A5'));
    expect(sheet.cellA1('A4').asNumber, 6);
    expect(sheet.cellA1('A5').asNumber, 8);
    sheet.autoFilter = SmlAutoFilter(
      range: SmlRange.parse('A1:A5'),
      hiddenValues: <int, Set<String>>{
        0: <String>{'2', '4'},
      },
    );
    expect(sheet.rowHeightAt(1), 0);
    expect(sheet.rowHeightAt(0), greaterThan(0));
    sheet.cellA1('B2').locked = false;
    sheet.protection = SmlSheetProtection(enabled: true, password: 'pw');
    expect(sheet.cellA1('B2').locked, isFalse);
    expect(sheet.protection!.password, 'pw');
  });

  test('evaluates hyperlink address cell info fixed and dollar', () {
    final SmlWorkbook book = SmlWorkbook();
    final SmlWorksheet sheet = book.firstSheet;
    sheet.cellA1('A1').value = 'Hello';
    final FormulaContext ctx = FormulaContext(
      workbook: book,
      sheet: sheet,
      origin: SmlCellRef.parse('B2'),
    );
    expect(
      evaluateFormula('=HYPERLINK("https://a.test","A")', ctx),
      'A',
    );
    expect(evaluateFormula('=HYPERLINK("https://a.test")', ctx), 'https://a.test');
    expect(evaluateFormula('=ADDRESS(2,3)', ctx), r'$C$2');
    expect(evaluateFormula('=ADDRESS(2,3,4)', ctx), 'C2');
    expect(evaluateFormula('=CELL("address",A1)', ctx), 'A1');
    expect(evaluateFormula('=CELL("row",A1)', ctx), 1);
    expect(evaluateFormula('=CELL("contents",A1)', ctx), 'Hello');
    expect(evaluateFormula('=INFO("system")', ctx), 'pcdos');
    expect(evaluateFormula('=FIXED(1234.5,1)', ctx), '1,234.5');
    expect(evaluateFormula('=DOLLAR(12.3,1)', ctx), r'$12.3');
    expect(evaluateFormula('=ASC("x")', ctx), 'x');
    expect(evaluateFormula('=BAHTTEXT(1.5)', ctx), '1.50');
  });
}
