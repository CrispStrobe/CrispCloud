import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('a no-edit save keeps native formula caches', () async {
    final book = SmlWorkbook(
      sheets: [SmlWorksheet(name: 'Sheet1', sheetId: 1)],
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
      sheets: [SmlWorksheet(name: 'Sheet1', sheetId: 1)],
    );
    book.firstSheet
      ..freezeCols = 36
      ..freezeRows = 1
      ..cellA1('AK2').value = 'anchor';
    final saved = await OfficeIsolateSave.workbook(book);
    final xml = OpcPackage.openBytes(
      saved,
    ).getPart('/xl/worksheets/sheet1.xml')!.readText();
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
    final reparsed = OpcPackage.openBytes(
      again,
    ).getPart('/xl/worksheets/sheet1.xml')!.readText();
    expect(reparsed, contains('topLeftCell="AK2"'));
  });

  test('page setup and print options round-trip', () async {
    final book = SmlWorkbook(
      sheets: [
        SmlWorksheet(name: 'Sheet1', sheetId: 1)
          ..pageSetup = SmlPageSetup(
            orientation: SmlPageOrientation.landscape,
            marginLeftIn: 0.5,
            marginRightIn: 0.6,
            marginTopIn: 0.7,
            marginBottomIn: 0.8,
            headerMarginIn: 0.2,
            footerMarginIn: 0.25,
            scale: 85,
            fitToWidth: 2,
            fitToHeight: 0,
            printGridlines: true,
            printHeadings: true,
            centerHorizontally: true,
            firstPageNumber: 3,
            useFirstPageNumber: true,
            blackAndWhite: true,
            draft: true,
          ),
      ],
    );
    final saved = await OfficeIsolateSave.workbook(book);
    final xml = OpcPackage.openBytes(
      saved,
    ).getPart('/xl/worksheets/sheet1.xml')!.readText();
    expect(xml, contains('<pageMargins'));
    expect(xml, contains('<pageSetup'));
    expect(xml, contains('orientation="landscape"'));
    expect(xml, contains('fitToWidth="2"'));
    expect(xml, contains('fitToHeight="0"'));
    final reopened = SheetDeserializer().readBytes(saved).firstSheet.pageSetup!;
    expect(reopened.orientation, SmlPageOrientation.landscape);
    expect(reopened.marginLeftIn, closeTo(0.5, 0.0001));
    expect(reopened.marginRightIn, closeTo(0.6, 0.0001));
    expect(reopened.marginTopIn, closeTo(0.7, 0.0001));
    expect(reopened.marginBottomIn, closeTo(0.8, 0.0001));
    expect(reopened.headerMarginIn, closeTo(0.2, 0.0001));
    expect(reopened.footerMarginIn, closeTo(0.25, 0.0001));
    expect(reopened.scale, 85);
    expect(reopened.fitToWidth, 2);
    expect(reopened.fitToHeight, 0);
    expect(reopened.printGridlines, isTrue);
    expect(reopened.printHeadings, isTrue);
    expect(reopened.centerHorizontally, isTrue);
    expect(reopened.firstPageNumber, 3);
    expect(reopened.useFirstPageNumber, isTrue);
    expect(reopened.blackAndWhite, isTrue);
    expect(reopened.draft, isTrue);
  });

  test('data-bar conditional rules round-trip', () async {
    final book = SmlWorkbook(
      sheets: [SmlWorksheet(name: 'Sheet1', sheetId: 1)],
    );
    final sheet = book.firstSheet;
    for (var row = 0; row < 3; row++) {
      sheet.cellA1('A${row + 1}').value = row + 1;
    }
    sheet.conditionalFormats.add(
      SmlConditionalRule(
        range: SmlRange.parse('A1:A3'),
        kind: SmlConditionalKind.dataBar,
        dataBarColor: 'FF0000',
        colorScaleStops: const [
          SmlColorScaleStop(type: 'min', colorRgb: 'FF0000'),
          SmlColorScaleStop(type: 'max', colorRgb: 'FF0000'),
        ],
      ),
    );
    final saved = await OfficeIsolateSave.workbook(book);
    final xml = OpcPackage.openBytes(
      saved,
    ).getPart('/xl/worksheets/sheet1.xml')!.readText();
    expect(xml, contains('type="dataBar"'));
    final reopened = SheetDeserializer().readBytes(saved).firstSheet;
    final rule = reopened.conditionalFormats.single;
    expect(rule.kind, SmlConditionalKind.dataBar);
    expect(rule.dataBarColor, 'FF0000');
  });

  test('color-scale conditional rules round-trip', () async {
    final book = SmlWorkbook(
      sheets: [SmlWorksheet(name: 'Sheet1', sheetId: 1)],
    );
    final sheet = book.firstSheet;
    for (var row = 0; row < 3; row++) {
      sheet.cellA1('A${row + 1}').value = row + 1;
    }
    sheet.conditionalFormats.add(
      SmlConditionalRule(
        range: SmlRange.parse('A1:A3'),
        kind: SmlConditionalKind.colorScale,
        colorScaleStops: const [
          SmlColorScaleStop(type: 'min', colorRgb: 'FF0000'),
          SmlColorScaleStop(type: 'max', colorRgb: '00FF00'),
        ],
      ),
    );
    final saved = await OfficeIsolateSave.workbook(book);
    final xml = OpcPackage.openBytes(
      saved,
    ).getPart('/xl/worksheets/sheet1.xml')!.readText();
    expect(xml, contains('type="colorScale"'));
    final reopened = SheetDeserializer().readBytes(saved).firstSheet;
    final rule = reopened.conditionalFormats.single;
    expect(rule.kind, SmlConditionalKind.colorScale);
    expect(rule.colorScaleStops.length, 2);
    expect(rule.colorScaleStops.first.colorRgb, 'FF0000');
    expect(rule.colorScaleStops.last.colorRgb, '00FF00');
  });

  test('top, bottom and average conditional rules round-trip', () async {
    final book = SmlWorkbook(
      sheets: [SmlWorksheet(name: 'Sheet1', sheetId: 1)],
    );
    final sheet = book.firstSheet;
    for (var row = 0; row < 5; row++) {
      sheet.cellA1('A${row + 1}').value = row + 1;
    }
    sheet.conditionalFormats.addAll([
      SmlConditionalRule(
        range: SmlRange.parse('A1:A5'),
        kind: SmlConditionalKind.top,
        rank: 3,
        fillRgb: '00FF00',
      ),
      SmlConditionalRule(
        range: SmlRange.parse('A1:A5'),
        kind: SmlConditionalKind.bottomPercent,
        rank: 20,
        fillRgb: 'FF0000',
      ),
      SmlConditionalRule(
        range: SmlRange.parse('A1:A5'),
        kind: SmlConditionalKind.belowAverage,
        fillRgb: '0000FF',
      ),
    ]);
    final saved = await OfficeIsolateSave.workbook(book);
    final xml = OpcPackage.openBytes(
      saved,
    ).getPart('/xl/worksheets/sheet1.xml')!.readText();
    expect(xml, contains('type="top10"'));
    expect(xml, contains('bottom="1"'));
    expect(xml, contains('aboveAverage="0"'));
    final reopened = SheetDeserializer().readBytes(saved).firstSheet;
    expect(reopened.conditionalFormats[0].kind, SmlConditionalKind.top);
    expect(reopened.conditionalFormats[0].rank, 3);
    expect(reopened.conditionalFormats[0].fillRgb, '00FF00');
    expect(
      reopened.conditionalFormats[1].kind,
      SmlConditionalKind.bottomPercent,
    );
    expect(reopened.conditionalFormats[1].rank, 20);
    expect(reopened.conditionalFormats[1].fillRgb, 'FF0000');
    expect(
      reopened.conditionalFormats[2].kind,
      SmlConditionalKind.belowAverage,
    );
    expect(reopened.conditionalFormats[2].fillRgb, '0000FF');
  });
}
