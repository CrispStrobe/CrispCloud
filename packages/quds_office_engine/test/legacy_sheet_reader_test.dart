import 'dart:convert';
import 'dart:io';
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

    expect(data.merges.map((merge) => merge.origin.a1), contains('A12'));
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
    expect(
      reopened.styles!.format(
        1240.5,
        reopened.sheets.first.cellA1('B2').styleIndex,
      ),
      '1,240.50',
    );
  });

  test('BIFF print settings survive saving and reopening as XLSX', () {
    final book = LegacySheetReader.readBytes(_legacyPrintWorkbook());
    final sheet = book.sheets.single;
    sheet.tabColorRgb = 'AABBCC';
    final reopened = SheetDeserializer().readBytes(
      SheetSerializer().writeBytes(book, recalculate: false),
    );
    expect(reopened.sheets.single.tabColorRgb, 'AABBCC');
    for (final worksheet in [sheet, reopened.sheets.single]) {
      final setup = worksheet.pageSetup!;
      expect(setup.orientation, SmlPageOrientation.landscape);
      expect(setup.paperSize, 8);
      expect(setup.paperWidthIn, 11.69);
      expect(setup.scale, 72);
      expect(setup.fitToPage, isTrue);
      expect(setup.fitToWidth, 2);
      expect(setup.fitToHeight, 0);
      expect(setup.printGridlines, isTrue);
      expect(setup.printHeadings, isTrue);
      expect(setup.printAcrossThenDown, isTrue);
      expect(setup.centerHorizontally, isTrue);
      expect(setup.centerVertically, isTrue);
      expect(setup.firstPageNumber, 5);
      expect(setup.useFirstPageNumber, isTrue);
      expect(setup.blackAndWhite, isTrue);
      expect(setup.draft, isTrue);
      expect(
        [
          setup.marginLeftIn,
          setup.marginRightIn,
          setup.marginTopIn,
          setup.marginBottomIn,
          setup.headerMarginIn,
          setup.footerMarginIn,
        ],
        [0.25, 0.5, 0.75, 1.25, 0.375, 0.625],
      );
    }
  });

  test('undefined BIFF printer fields and malformed margins keep defaults', () {
    final setup = LegacySheetReader.readBytes(
      _legacyPrintWorkbook(noPrinterSettings: true),
    ).sheets.single.pageSetup!;
    expect(setup.paperSize, 9);
    expect(setup.orientation, SmlPageOrientation.portrait);
    expect(setup.scale, 100);
    expect(setup.marginLeftIn, 0.75);
    expect(setup.footerMarginIn, 0.5);
    expect(setup.fitToWidth, 2);
    expect(setup.firstPageNumber, 5);
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
      File(
        'test/fixtures/fidelity/legacy-shared-formula.xls',
      ).readAsBytesSync(),
    );
    final sheet = book.sheets.first;
    expect(sheet.cellA1('B1').formula, '(A1*2)');
    expect(sheet.cellA1('B2').formula, '(A2*2)');
    expect(sheet.cellA1('B50').formula, '(A50*2)');
    expect(sheet.cellA1('B50').value, 100);
  });
}

Uint8List _legacyPrintWorkbook({bool noPrinterSettings = false}) {
  List<int> record(int op, List<int> data) => [
    op & 0xff,
    op >> 8,
    data.length & 0xff,
    data.length >> 8,
    ...data,
  ];
  List<int> margin(int op, double value) => record(
    op,
    (ByteData(8)..setFloat64(0, value, Endian.little)).buffer.asUint8List(),
  );
  final globals = record(0x0809, [0, 6, 5, 0]);
  final eof = record(0x000a, []);
  final name = 'Print'.codeUnits;
  final boundSheet = Uint8List(8 + name.length);
  boundSheet[6] = name.length;
  boundSheet.setRange(8, boundSheet.length, name);
  ByteData.sublistView(boundSheet).setUint32(
    0,
    globals.length + boundSheet.length + 4 + eof.length,
    Endian.little,
  );
  final setup = ByteData(34)
    ..setUint16(0, 8, Endian.little)
    ..setUint16(2, 72, Endian.little)
    ..setInt16(4, 5, Endian.little)
    ..setUint16(6, 2, Endian.little)
    ..setUint16(10, noPrinterSettings ? 0x9d : 0x99, Endian.little)
    ..setFloat64(16, 0.375, Endian.little)
    ..setFloat64(24, noPrinterSettings ? -1 : 0.625, Endian.little);
  return (CfbfWriter()..addStream('Workbook', [
        ...globals,
        ...record(0x0085, boundSheet),
        ...eof,
        ...record(0x0809, [0, 6, 0x10, 0]),
        ...record(0x002a, [1, 0]),
        ...record(0x002b, [1, 0]),
        ...record(0x0081, [0, 1]),
        ...record(0x0083, [1, 0]),
        ...record(0x0084, [1, 0]),
        ...margin(0x0026, noPrinterSettings ? double.nan : 0.25),
        ...margin(0x0027, 0.5),
        ...margin(0x0028, 0.75),
        ...margin(0x0029, 1.25),
        ...record(0x00a1, setup.buffer.asUint8List()),
        ...eof,
      ]))
      .build();
}
