import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('writes a readable ODS package with values, formulas and metadata', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1)
      ..setColumnWidth(0, 160);
    sheet.cellA1('A1')
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

  test('writes header and footer sections', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1)
      ..headerFooter = SmlHeaderFooter(
        headerLeft: 'Left',
        headerCenter: 'Page &P of &N',
        headerRight: '&A',
        footerLeft: '&D',
        footerCenter: '&F',
        footerRight: '&T',
      );
    final reopened = OdsSheetReader.readBytes(
      OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet])),
    );
    final headerFooter = reopened.sheets.first.headerFooter!;
    expect(headerFooter.headerLeft, 'Left');
    expect(headerFooter.headerCenter, 'Page &P of &N');
    expect(headerFooter.headerRight, '&A');
    expect(headerFooter.footerLeft, '&D');
    expect(headerFooter.footerCenter, '&F');
    expect(headerFooter.footerRight, '&T');
  });

  test('writes authored page setup', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1)
      ..pageSetup = SmlPageSetup(
        orientation: SmlPageOrientation.landscape,
        paperWidthIn: 11.6929,
        paperHeightIn: 8.2677,
        marginLeftIn: 0.5,
        marginRightIn: 0.6,
        marginTopIn: 0.7,
        marginBottomIn: 0.8,
        scale: 85,
        fitToWidth: 2,
        fitToHeight: 0,
        printGridlines: true,
        printHeadings: true,
        firstPageNumber: 3,
        useFirstPageNumber: true,
      );
    final reopened = OdsSheetReader.readBytes(
      OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet])),
    );
    final setup = reopened.sheets.first.pageSetup!;
    expect(setup.orientation, SmlPageOrientation.landscape);
    expect(setup.paperWidthIn, closeTo(11.6929, 0.01));
    expect(setup.paperHeightIn, closeTo(8.2677, 0.01));
    expect(setup.marginLeftIn, closeTo(0.5, 0.01));
    expect(setup.marginRightIn, closeTo(0.6, 0.01));
    expect(setup.marginTopIn, closeTo(0.7, 0.01));
    expect(setup.marginBottomIn, closeTo(0.8, 0.01));
    expect(setup.scale, 85);
    expect(setup.fitToWidth, 2);
    expect(setup.printGridlines, isTrue);
    expect(setup.printHeadings, isTrue);
    expect(setup.firstPageNumber, 3);
    expect(setup.useFirstPageNumber, isTrue);
  });

  test('writes row outline groups and geometry outside the cell extent', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('A1').value = 'Header';
    sheet.cellA1('A2').value = 'One';
    sheet.cellA1('A5').value = 'Four';
    sheet.rowOutlineLevels[1] = 1;
    sheet.rowOutlineLevels[2] = 1;
    sheet.rowOutlineLevels[3] = 2;
    sheet.rowOutlineLevels[4] = 1;
    sheet.hiddenRows.add(10);
    sheet.rowHeights[11] = 28;
    sheet.columnWidths[8] = 120;
    final reopened = OdsSheetReader.readBytes(
      OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet])),
    );
    final written = reopened.sheets.first;
    expect(written.rowOutlineLevels[1], 1);
    expect(written.rowOutlineLevels[2], 1);
    expect(written.rowOutlineLevels[3], 2);
    expect(written.rowOutlineLevels[4], 1);
    expect(written.hiddenRows, contains(10));
    expect(written.rowHeights[11], closeTo(28, 0.01));
    expect(written.columnWidths[8], closeTo(114, 0.01));
  });

  test('writes autofilter predicate values', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('A1').value = 'Name';
    sheet.cellA1('A2').value = 'Alpha';
    sheet.cellA1('A3').value = 'Beta';
    sheet.autoFilter = SmlAutoFilter(
      range: SmlRange.parse('A1:A3'),
      hiddenValues: {
        0: {'Beta'},
      },
    );
    final reopened = OdsSheetReader.readBytes(
      OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet])),
    );
    final filter = reopened.sheets.first.autoFilter!;
    expect(filter.hiddenValues[0], {'Beta'});
    expect(filter.isRowHidden(reopened.sheets.first, 2), isTrue);
    expect(filter.isRowHidden(reopened.sheets.first, 1), isFalse);
  });

  test('writes worksheet pictures into the package', () {
    final png = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
      ),
    );
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.drawings.add(
      SmlDrawing(
        col: 0,
        row: 0,
        visual: OfficeVisual(
          kind: OfficeVisualKind.picture,
          title: 'Logo',
          imageBytes: png,
          width: 72,
          height: 72,
        ),
      ),
    );
    final reopened = OdsSheetReader.readBytes(
      OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet])),
    );
    final drawing = reopened.sheets.first.drawings.single;
    expect(drawing.visual.title, 'Logo');
    expect(drawing.visual.imageBytes, png);
  });

  test('writes list validation prompts and errors', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('A1').value = 'Red';
    sheet.cellA1('A2').value = 'Green';
    sheet.validations.add(
      SmlDataValidation(
        range: SmlRange.parse('A1:A2'),
        kind: SmlValidationKind.list,
        formula1: 'Red,Green',
        allowBlank: false,
        promptTitle: 'Pick',
        prompt: 'Choose a colour',
        errorTitle: 'Bad',
        error: 'Not in list',
        errorStyle: 'warning',
      ),
    );
    final reopened = OdsSheetReader.readBytes(
      OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet])),
    );
    final rule = reopened.sheets.first.validations.first;
    expect(rule.listItems, ['Red', 'Green']);
    expect(rule.allowBlank, isFalse);
    expect(rule.promptTitle, 'Pick');
    expect(rule.prompt, 'Choose a colour');
    expect(rule.errorTitle, 'Bad');
    expect(rule.error, 'Not in list');
    expect(rule.errorStyle, 'warning');
  });

  test('writes range-backed list validations', () {
    final source = SmlWorksheet(name: 'Source', sheetId: 1);
    source.cellA1('A1').value = 'Red';
    source.cellA1('A2').value = 'Green';
    final data = SmlWorksheet(name: 'Data', sheetId: 2)
      ..validations.add(
        SmlDataValidation(
          range: SmlRange.parse('A1'),
          kind: SmlValidationKind.list,
          formula1: 'Red,Green',
          listSourceRange: SmlRange.parse('A1'),
          listSourceSheet: 'Source',
        ),
      );
    final reopened = OdsSheetReader.readBytes(
      OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [source, data])),
    );
    final rule = reopened.sheets[1].validations.single;
    expect(rule.kind, SmlValidationKind.list);
    expect(rule.listSourceSheet, 'Source');
    expect(rule.listSourceRange?.start.a1, 'A1');
    expect(rule.listSourceRange?.end.a1, 'A1');
  });

  test('writes icon-set conditional rules', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    for (var row = 1; row <= 3; row++) {
      sheet.cellA1('A$row').value = row;
    }
    sheet.conditionalFormats.add(
      SmlConditionalRule(
        range: SmlRange.parse('A1:A3'),
        kind: SmlConditionalKind.iconSet,
        iconSetType: '3TrafficLights1',
        colorScaleStops: const [
          SmlColorScaleStop(type: 'number', value: 1, colorRgb: '638EC6'),
          SmlColorScaleStop(type: 'number', value: 2, colorRgb: '638EC6'),
          SmlColorScaleStop(type: 'number', value: 3, colorRgb: '638EC6'),
        ],
      ),
    );
    final reopened = OdsSheetReader.readBytes(
      OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet])),
    );
    final rule = reopened.sheets.first.conditionalFormats.single;
    expect(rule.kind, SmlConditionalKind.iconSet);
    expect(rule.iconSetType, '3TrafficLights1');
    expect(rule.colorScaleStops.length, 3);
    expect(
      SmlConditionalResolver(
        sheet: reopened.sheets.first,
      ).resolve(SmlCellRef.parse('A3')).iconSetIndex,
      2,
    );
  });

  test('writes data-bar conditional rules', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    for (var row = 1; row <= 3; row++) {
      sheet.cellA1('A$row').value = row;
    }
    sheet.conditionalFormats.add(
      SmlConditionalRule(
        range: SmlRange.parse('A1:A3'),
        kind: SmlConditionalKind.dataBar,
        dataBarColor: 'FF0000',
        colorScaleStops: const [
          SmlColorScaleStop(type: 'minimum', colorRgb: 'FF0000'),
          SmlColorScaleStop(type: 'maximum', colorRgb: 'FF0000'),
        ],
      ),
    );
    final reopened = OdsSheetReader.readBytes(
      OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet])),
    );
    final rule = reopened.sheets.first.conditionalFormats.single;
    expect(rule.kind, SmlConditionalKind.dataBar);
    expect(rule.dataBarColor, 'FF0000');
    expect(rule.colorScaleStops.length, 2);
    final style = SmlConditionalResolver(
      sheet: reopened.sheets.first,
    ).resolve(SmlCellRef.parse('A1'));
    expect(style.dataBarFraction, 0);
    final last = SmlConditionalResolver(
      sheet: reopened.sheets.first,
    ).resolve(SmlCellRef.parse('A3'));
    expect(last.dataBarFraction, 1);
  });

  test('writes color-scale conditional rules', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    for (var row = 1; row <= 3; row++) {
      sheet.cellA1('A$row').value = row;
    }
    sheet.conditionalFormats.add(
      SmlConditionalRule(
        range: SmlRange.parse('A1:A3'),
        kind: SmlConditionalKind.colorScale,
        colorScaleStops: const [
          SmlColorScaleStop(type: 'minimum', colorRgb: 'FF0000'),
          SmlColorScaleStop(type: 'maximum', colorRgb: '00FF00'),
        ],
      ),
    );
    final reopened = OdsSheetReader.readBytes(
      OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet])),
    );
    final rule = reopened.sheets.first.conditionalFormats.single;
    expect(rule.kind, SmlConditionalKind.colorScale);
    expect(rule.colorScaleStops.length, 2);
    expect(rule.colorScaleStops.first.colorRgb, 'FF0000');
    expect(rule.colorScaleStops.last.colorRgb, '00FF00');
    SmlAnalysis.applyConditional(reopened.sheets.first);
    expect(reopened.sheets.first.cellA1('A1').fillRgb, 'FF0000');
    expect(reopened.sheets.first.cellA1('A3').fillRgb, '00FF00');
  });

  test('writes top and bottom conditional rules', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    for (var row = 1; row <= 5; row++) {
      sheet.cellA1('A$row').value = row;
    }
    sheet.conditionalFormats.addAll([
      SmlConditionalRule(
        range: SmlRange.parse('A1:A5'),
        kind: SmlConditionalKind.top,
        rank: 2,
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
        kind: SmlConditionalKind.aboveAverage,
        fillRgb: '0000FF',
      ),
    ]);
    final reopened = OdsSheetReader.readBytes(
      OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet])),
    );
    final rules = reopened.sheets.first.conditionalFormats;
    expect(rules[0].kind, SmlConditionalKind.top);
    expect(rules[0].rank, 2);
    expect(rules[1].kind, SmlConditionalKind.bottomPercent);
    expect(rules[1].rank, 20);
    expect(rules[2].kind, SmlConditionalKind.aboveAverage);
  });

  test('writes conditional formats and validates them on read', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.conditionalFormats.add(
      SmlConditionalRule(
        range: SmlRange.parse('A1:A10'),
        kind: SmlConditionalKind.greaterThan,
        formula: '3',
        fillRgb: '00FF00',
      ),
    );
    final reopened = OdsSheetReader.readBytes(
      OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet])),
    );
    final rule = reopened.sheets.first.conditionalFormats.single;
    expect(rule.kind, SmlConditionalKind.greaterThan);
    expect(rule.formula, '3');
    expect(rule.fillRgb, '00FF00');
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
